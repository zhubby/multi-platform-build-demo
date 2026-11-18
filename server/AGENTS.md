# server/
> L2 | Parent: ../AGENTS.md

go.mod: Go 模块与纯 Go SQLite 依赖版本。
go.sum: 直接与间接依赖内容校验。
cmd/: HTTP 服务启动与退出信号入口。
internal/: SQLite 存储、业务校验与 HTTP 契约实现。
build.sh: 服务检查、测试与 Linux 开发包构建。
Dockerfile: 无 CGO 服务端的多阶段 OCI 构建。
.dockerignore: 排除本机数据、缓存与无关平台工程。

[PROTOCOL]: Update this header on change, then check AGENTS.md
