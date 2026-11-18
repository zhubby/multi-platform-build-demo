# scripts/
> L2 | Parent: ../AGENTS.md

build.sh: 按目标分派原生构建，统一生成与校验制品清单。
package.py: 生成版本、提交、工具版本与 SHA-256 清单，校验下载制品。
test_package.py: 验证摘要篡改、路径越界与版本清单行为。
check_repo.py: 检查 OpenAPI 引用、公共样例、文件大小与 GEB 文档。
smoke_server.py: 以真实 HTTP 验证创建、冲突、重启后可用的业务接口。

[PROTOCOL]: Update this header on change, then check AGENTS.md
