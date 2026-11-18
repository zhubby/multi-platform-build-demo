# internal/tasknotes/
> L2 | Parent: ../AGENTS.md

model.go: 定义任务、笔记、请求与统一错误的数据边界。
store.go: SQLite 建表、排序、原子修订与数据持久化。
http.go: 将版本化 HTTP 契约映射到存储，隔离鉴权与错误。
http_test.go: 使用真实 SQLite 与 HTTP 验证鉴权、CRUD、冲突和重启。

[PROTOCOL]: Update this header on change, then check AGENTS.md
