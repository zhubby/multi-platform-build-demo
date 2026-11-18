//! [INPUT]: 使用 Serde JSON、UTC 时钟、内存令牌和服务地址。
//! [OUTPUT]: 导出记录、原子缓存和带写入核对状态的 HTTP 会话。
//! [POS]: GTK 与无界面测试共用核心；不依赖 GTK。
//! [PROTOCOL]: Update this header on change, then check AGENTS.md
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs,
    path::{Path, PathBuf},
    time::Duration,
};

pub fn valid_title(s: &str) -> bool {
    (1..=200).contains(&s.trim().chars().count())
}
pub fn cache_key(url: &str) -> String {
    format!("{:x}", Sha256::digest(url.as_bytes()))
}
pub fn normalize_url(url: &str) -> Result<String, String> {
    let url = url.trim().trim_end_matches("/");
    let parsed = url::Url::parse(url).map_err(|_| "服务地址无效".to_string())?;
    if !["http", "https"].contains(&parsed.scheme())
        || parsed.host().is_none()
        || parsed.query().is_some()
        || parsed.fragment().is_some()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
    {
        return Err("请输入完整 HTTP 或 HTTPS 地址，且不含查询参数".into());
    }
    Ok(url.into())
}
pub fn address_matches(input: &str, connected: &str) -> bool {
    normalize_url(input).is_ok_and(|url| url == connected)
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub completed: bool,
    pub revision: u64,
    pub created_at: String,
    pub updated_at: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct Note {
    pub id: String,
    pub title: String,
    pub body: String,
    pub revision: u64,
    pub created_at: String,
    pub updated_at: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, Default, PartialEq)]
pub struct Snapshot {
    pub url: String,
    pub tasks: Vec<Task>,
    pub notes: Vec<Note>,
    pub refreshed_at: String,
}
#[derive(Deserialize)]
struct Items<T> {
    items: Vec<T>,
}
pub struct Cache {
    root: PathBuf,
}
impl Cache {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }
    pub fn load(&self, url: &str) -> Option<Snapshot> {
        let bytes = fs::read(self.root.join(format!("{}.json", cache_key(url)))).ok()?;
        let value: Snapshot = serde_json::from_slice(&bytes).ok()?;
        (value.url == url).then_some(value)
    }
    pub fn save(&self, snapshot: &Snapshot) -> Result<(), String> {
        fs::create_dir_all(&self.root).map_err(|e| e.to_string())?;
        let path = self.root.join(format!("{}.json", cache_key(&snapshot.url)));
        let tmp = path.with_extension(format!(
            "{}-{}.tmp",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        fs::write(
            &tmp,
            serde_json::to_vec(snapshot).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        fs::rename(tmp, path).map_err(|e| e.to_string())
    }
}
pub fn data_root() -> PathBuf {
    std::env::var_os("XDG_DATA_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            Path::new(&std::env::var("HOME").unwrap_or_default()).join(".local/share")
        })
        .join("tasknotes")
}
pub struct Session {
    pub url: String,
    token: String,
    pub snapshot: Snapshot,
    pub online: bool,
    pub pending_write_review: bool,
    cache: Cache,
    agent: ureq::Agent,
}
impl Session {
    pub fn new(url: String, token: String, root: PathBuf) -> Self {
        let cache = Cache::new(root);
        let snapshot = cache.load(&url).unwrap_or_else(|| Snapshot {
            url: url.clone(),
            ..Default::default()
        });
        Self {
            url,
            token,
            snapshot,
            online: false,
            pending_write_review: false,
            cache,
            agent: ureq::AgentBuilder::new()
                .timeout(Duration::from_secs(12))
                .build(),
        }
    }
    pub fn set_token(&mut self, token: String) {
        self.token = token;
        self.online = false;
    }
    pub fn acknowledge_write(&mut self) -> Result<(), String> {
        if !self.online {
            return Err("请先刷新并检查列表".into());
        }
        self.pending_write_review = false;
        Ok(())
    }
    fn request(
        &self,
        method: &str,
        path: &str,
        body: Option<serde_json::Value>,
    ) -> Result<Option<serde_json::Value>, String> {
        let request = self
            .agent
            .request(method, &format!("{}/api/v1/{}", self.url, path))
            .set("Authorization", &format!("Bearer {}", self.token));
        let response = match body {
            Some(value) => request.send_json(value),
            None => request.call(),
        };
        match response {
            Ok(response) => {
                if response.status() == 204 {
                    Ok(None)
                } else {
                    response
                        .into_json()
                        .map(Some)
                        .map_err(|_| "服务返回无效 JSON".into())
                }
            }
            Err(ureq::Error::Status(status, response)) => {
                let detail = response
                    .into_json::<serde_json::Value>()
                    .ok()
                    .and_then(|v| v["error"]["message"].as_str().map(String::from))
                    .unwrap_or_else(|| "请求失败".into());
                Err(match status {
                    401 => "401：请重新输入令牌".into(),
                    409 => "409：记录已在其他设备修改。请刷新后检查保留的草稿。".into(),
                    _ => format!("{}：{}", status, detail),
                })
            }
            Err(_) => Err("无法连接服务。缓存只读；请检查地址与网络后重试。".into()),
        }
    }
    pub fn refresh(&mut self) -> Result<(), String> {
        self.online = false;
        let tasks: Items<Task> =
            serde_json::from_value(self.request("GET", "tasks", None)?.ok_or("任务响应为空")?)
                .map_err(|_| "任务格式错误")?;
        let notes: Items<Note> =
            serde_json::from_value(self.request("GET", "notes", None)?.ok_or("笔记响应为空")?)
                .map_err(|_| "笔记格式错误")?;
        let refreshed_at = chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true);
        let next = Snapshot {
            url: self.url.clone(),
            tasks: tasks.items,
            notes: notes.items,
            refreshed_at,
        };
        self.cache.save(&next)?;
        self.snapshot = next;
        self.online = true;
        Ok(())
    }
    pub fn write(
        &mut self,
        method: &str,
        path: &str,
        body: Option<serde_json::Value>,
    ) -> Result<(), String> {
        if !self.online {
            return Err("当前只读，请先成功刷新".into());
        }
        if self.pending_write_review {
            return Err("上次写入结果不确定。请刷新、检查列表并点击已核对结果。".into());
        }
        if let Err(e) = self.request(method, path, body) {
            self.online = false;
            self.pending_write_review = !["400", "401", "404", "409", "405", "413"]
                .iter()
                .any(|status| e.starts_with(status));
            return Err(e);
        }
        let result = self.refresh();
        if result.is_err() {
            self.pending_write_review = true;
        }
        result
    }
}
