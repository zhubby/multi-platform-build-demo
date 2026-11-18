//! [INPUT]: 显式传入包含 url 和 token 的本机配置。
//! [OUTPUT]: 验证真实服务 CRUD、409、缓存和修订号，清理创建记录。
//! [POS]: 手动联机验收入口；不在默认测试访问外部服务。
//! [PROTOCOL]: Update this header on change, then check AGENTS.md
use tasknotes::{Cache, Session};
fn exercise(session: &mut Session, marker: &str) -> Result<(), String> {
    session.refresh()?;
    session.write(
        "POST",
        "tasks",
        Some(serde_json::json!({"title":marker,"completed":false})),
    )?;
    session.write(
        "POST",
        "notes",
        Some(serde_json::json!({"title":marker,"body":"真实服务中文 🚀"})),
    )?;
    let task = session
        .snapshot
        .tasks
        .iter()
        .find(|v| v.title == marker)
        .ok_or("任务创建缺失")?
        .clone();
    let note = session
        .snapshot
        .notes
        .iter()
        .find(|v| v.title == marker)
        .ok_or("笔记创建缺失")?
        .clone();
    session.write(
        "PUT",
        &format!("tasks/{}", task.id),
        Some(serde_json::json!({"title":marker,"completed":true,"revision":task.revision})),
    )?;
    session.write(
        "PUT",
        &format!("notes/{}", note.id),
        Some(serde_json::json!({"title":marker,"body":"更新正文","revision":note.revision})),
    )?;
    if !session
        .snapshot
        .tasks
        .iter()
        .find(|v| v.id == task.id)
        .ok_or("更新任务缺失")?
        .completed
    {
        return Err("完成状态未同步".into());
    }
    let conflict = session.write(
        "PUT",
        &format!("tasks/{}", task.id),
        Some(serde_json::json!({"title":marker,"completed":false,"revision":task.revision})),
    );
    if !matches!(conflict, Err(ref e) if e.starts_with("409")) || session.online {
        return Err("409 未撤销写权限".into());
    }
    session.refresh()?;
    Ok(())
}
fn lost_response(url: &str, token: &str, marker: &str) -> Result<(), String> {
    use std::io::{Read, Write};
    let listener = std::net::TcpListener::bind("127.0.0.1:0").map_err(|e| e.to_string())?;
    let proxy_url = format!(
        "http://{}",
        listener.local_addr().map_err(|e| e.to_string())?
    );
    let upstream = url.to_string();
    let secret = token.to_string();
    let proxy = std::thread::spawn(move || -> Result<(), String> {
        for _ in 0..5 {
            let (mut socket, _) = listener.accept().map_err(|e| e.to_string())?;
            socket
                .set_read_timeout(Some(std::time::Duration::from_secs(10)))
                .map_err(|e| e.to_string())?;
            let mut bytes = Vec::new();
            let mut buffer = [0; 8192];
            let header_end = loop {
                let count = socket.read(&mut buffer).map_err(|e| e.to_string())?;
                if count == 0 {
                    return Err("代理请求为空".into());
                }
                bytes.extend_from_slice(&buffer[..count]);
                if let Some(index) = bytes.windows(4).position(|v| v == b"\r\n\r\n") {
                    break index + 4;
                }
            };
            let headers = String::from_utf8_lossy(&bytes[..header_end]);
            let first = headers.lines().next().ok_or("请求行为空")?;
            let parts: Vec<_> = first.split_whitespace().collect();
            let method = parts[0].to_string();
            let path = parts[1].to_string();
            let length = headers
                .lines()
                .find_map(|line| {
                    line.to_lowercase()
                        .strip_prefix("content-length:")
                        .and_then(|v| v.trim().parse::<usize>().ok())
                })
                .unwrap_or(0);
            while bytes.len() < header_end + length {
                let count = socket.read(&mut buffer).map_err(|e| e.to_string())?;
                if count == 0 {
                    return Err("请求正文不完整".into());
                }
                bytes.extend_from_slice(&buffer[..count]);
            }
            let request = ureq::request(&method, &format!("{}{}", upstream, path))
                .set("Authorization", &format!("Bearer {}", secret))
                .set("Content-Type", "application/json");
            let response = if method == "POST" {
                request.send_bytes(&bytes[header_end..header_end + length])
            } else {
                request.call()
            }
            .map_err(|_| "真实服务代理请求失败".to_string())?;
            let status = response.status();
            let text = response.into_string().map_err(|e| e.to_string())?;
            if method == "POST" {
                continue;
            }
            write!(
                socket,
                "HTTP/1.1 {} OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                status,
                text.len(),
                text
            )
            .map_err(|e| e.to_string())?;
        }
        Ok(())
    });
    let root = std::env::temp_dir().join(format!("{}-proxy", marker));
    let mut session = Session::new(proxy_url, token.into(), root.clone());
    session.refresh()?;
    let title = format!("{}-lost", marker);
    if session
        .write(
            "POST",
            "notes",
            Some(serde_json::json!({"title":title,"body":"保留草稿"})),
        )
        .is_ok()
        || !session.pending_write_review
    {
        return Err("丢响应未标记不确定".into());
    }
    session.set_token(token.into());
    session.refresh()?;
    if session
        .snapshot
        .notes
        .iter()
        .filter(|v| v.title == title)
        .count()
        != 1
    {
        return Err("真实服务丢响应记录不存在".into());
    }
    if session
        .write(
            "POST",
            "notes",
            Some(serde_json::json!({"title":title,"body":"保留草稿"})),
        )
        .is_ok()
    {
        return Err("重复 POST 未阻止".into());
    }
    session.acknowledge_write()?;
    proxy.join().map_err(|_| "代理线程失败")??;
    let _ = std::fs::remove_dir_all(root);
    Ok(())
}
fn main() -> Result<(), String> {
    let path = std::env::args()
        .nth(1)
        .ok_or("用法：cargo run --locked --no-default-features --example live -- <显式配置路径>")?;
    let config: serde_json::Value =
        serde_json::from_slice(&std::fs::read(path).map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
    let url = config["url"].as_str().ok_or("配置缺少 url")?.to_string();
    let token = config["token"]
        .as_str()
        .ok_or("配置缺少 token")?
        .to_string();
    let marker = format!(
        "Rust验收-{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    );
    let root = std::env::temp_dir().join(&marker);
    let mut session = Session::new(url.clone(), token.clone(), root.clone());
    let result = exercise(&mut session, &marker).and_then(|_| lost_response(&url, &token, &marker));
    let cleanup = (|| -> Result<(), String> {
        session.refresh()?;
        let tasks = session.snapshot.tasks.clone();
        let notes = session.snapshot.notes.clone();
        for task in tasks.into_iter().filter(|v| v.title.starts_with(&marker)) {
            session.write(
                "DELETE",
                &format!("tasks/{}?revision={}", task.id, task.revision),
                None,
            )?;
        }
        for note in notes.into_iter().filter(|v| v.title.starts_with(&marker)) {
            session.write(
                "DELETE",
                &format!("notes/{}?revision={}", note.id, note.revision),
                None,
            )?;
        }
        let cached = Cache::new(&root).load(&url).ok_or("缓存未生成")?;
        if cached.tasks.iter().any(|v| v.title.starts_with(&marker))
            || cached.notes.iter().any(|v| v.title.starts_with(&marker))
        {
            return Err("删除后缓存残留".into());
        }
        Ok(())
    })();
    let _ = std::fs::remove_dir_all(root);
    result?;
    cleanup?;
    println!("真实 Go 服务回归通过：任务/笔记创建、修改、409、删除、缓存刷新；创建记录已清理。");
    Ok(())
}
