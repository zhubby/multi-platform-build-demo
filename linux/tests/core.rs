// [INPUT]: 使用 tasknotes 核心与公共 JSON 样例。
// [OUTPUT]: 验证 Unicode 约束、缓存隔离与协议解码。
// [POS]: 不依赖 GTK 的真实领域测试。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
#[test]
fn unicode_titles_and_url_isolation() {
    assert!(!tasknotes::address_matches("http://b", "http://a"));
    assert!(tasknotes::address_matches("http://a/", "http://a"));
    assert!(!tasknotes::address_matches("invalid", "http://a"));
    assert!(tasknotes::valid_title("  任务 🚀  "));
    assert!(!tasknotes::valid_title("  "));
    assert!(!tasknotes::valid_title(&"文".repeat(201)));
    assert_ne!(
        tasknotes::cache_key("http://a"),
        tasknotes::cache_key("http://b")
    );
}

#[test]
fn fixtures_decode_and_atomic_cache_never_contains_token() {
    use tasknotes::{Cache, Note, Snapshot, Task};
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("../../contracts/fixtures.json")).unwrap();
    let tasks: Vec<Task> = serde_json::from_value(fixture["tasks"]["items"].clone()).unwrap();
    let notes: Vec<Note> = serde_json::from_value(fixture["notes"]["items"].clone()).unwrap();
    assert_eq!(notes[0].revision, 2);
    assert!(notes[0].body.contains("🚀"));
    let root = std::env::temp_dir().join(format!("tasknotes-test-{}", std::process::id()));
    let cache = Cache::new(&root);
    let snapshot = Snapshot {
        url: "http://a".into(),
        tasks,
        notes,
        refreshed_at: "2026-11-18T00:00:00Z".into(),
    };
    cache.save(&snapshot).unwrap();
    assert_eq!(cache.load("http://a"), Some(snapshot.clone()));
    assert!(cache.load("http://b").is_none());
    cache.save(&snapshot).unwrap();
    let text =
        std::fs::read_to_string(root.join(format!("{}.json", tasknotes::cache_key("http://a"))))
            .unwrap();
    assert!(!text.contains("token"));
    assert!(!text.contains("Authorization"));
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn partial_refresh_preserves_whole_snapshot_and_enters_read_only() {
    use std::io::Write;
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("../../contracts/fixtures.json")).unwrap();
    let server = std::thread::spawn(move || {
        for (status, value) in [
            ("200 OK", fixture["tasks"].to_string()),
            ("200 OK", fixture["notes"].to_string()),
            ("200 OK", "{\"items\":[]}".into()),
            (
                "500 Internal Server Error",
                "{\"error\":{\"message\":\"fail\"}}".into(),
            ),
        ] {
            let (mut socket, _) = listener.accept().unwrap();
            let request = read_request(&mut socket);
            let text = String::from_utf8_lossy(&request);
            assert!(text
                .to_lowercase()
                .contains("authorization: bearer test-secret"));
            write!(socket, "HTTP/1.1 {}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}", status, value.len(), value).unwrap();
        }
    });
    let root = std::env::temp_dir().join(format!("tasknotes-session-{}", std::process::id()));
    let mut session = tasknotes::Session::new(url, "test-secret".into(), root.clone());
    assert!(session.write("POST", "tasks", None).is_err());
    session.refresh().unwrap();
    let before = session.snapshot.clone();
    assert!(session.online);
    assert!(session.refresh().is_err());
    assert!(!session.online);
    assert_eq!(session.snapshot, before);
    assert!(session.write("POST", "tasks", None).is_err());
    server.join().unwrap();
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn accepted_write_then_failed_refresh_requires_explicit_review() {
    use std::io::Write;
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let fixture: serde_json::Value =
        serde_json::from_str(include_str!("../../contracts/fixtures.json")).unwrap();
    let server = std::thread::spawn(move || {
        let tasks = fixture["tasks"].to_string();
        let notes = fixture["notes"].to_string();
        for (status, value) in [
            ("200 OK", tasks.clone()),
            ("200 OK", notes.clone()),
            ("201 Created", fixture["tasks"]["items"][0].to_string()),
            ("200 OK", tasks.clone()),
            (
                "500 Internal Server Error",
                "{\"error\":{\"message\":\"fail\"}}".into(),
            ),
            ("200 OK", tasks),
            ("200 OK", notes),
        ] {
            let (mut socket, _) = listener.accept().unwrap();
            let _request = read_request(&mut socket);
            write!(
                socket,
                "HTTP/1.1 {}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                status,
                value.len(),
                value
            )
            .unwrap();
        }
    });
    let root = std::env::temp_dir().join(format!("tasknotes-uncertain-{}", std::process::id()));
    let mut session = tasknotes::Session::new(url, "secret".into(), root.clone());
    session.refresh().unwrap();
    assert!(session
        .write(
            "POST",
            "tasks",
            Some(serde_json::json!({"title":"draft","completed":false}))
        )
        .is_err());
    assert!(session.pending_write_review);
    assert!(!session.online);
    session.set_token("secret".into());
    assert!(session.pending_write_review);
    session.refresh().unwrap();
    assert!(session.pending_write_review);
    assert!(session
        .write(
            "POST",
            "tasks",
            Some(serde_json::json!({"title":"draft","completed":false}))
        )
        .is_err());
    session.acknowledge_write().unwrap();
    assert!(!session.pending_write_review);
    server.join().unwrap();
    std::fs::remove_dir_all(root).unwrap();
}

fn read_request(socket: &mut std::net::TcpStream) -> Vec<u8> {
    use std::io::Read;
    socket
        .set_read_timeout(Some(std::time::Duration::from_secs(5)))
        .unwrap();
    let mut bytes = Vec::new();
    let mut buffer = [0; 8192];
    let header_end = loop {
        let count = socket.read(&mut buffer).unwrap();
        assert!(count > 0);
        bytes.extend_from_slice(&buffer[..count]);
        if let Some(index) = bytes.windows(4).position(|v| v == b"\r\n\r\n") {
            break index + 4;
        }
    };
    let headers = String::from_utf8_lossy(&bytes[..header_end]);
    let length = headers
        .lines()
        .find_map(|line| {
            line.to_lowercase()
                .strip_prefix("content-length:")
                .and_then(|v| v.trim().parse::<usize>().ok())
        })
        .unwrap_or(0);
    while bytes.len() < header_end + length {
        let count = socket.read(&mut buffer).unwrap();
        assert!(count > 0);
        bytes.extend_from_slice(&buffer[..count]);
    }
    bytes
}
