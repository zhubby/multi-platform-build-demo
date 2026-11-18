<!--
[INPUT]: 2026-11-18 的实际编译、测试、联调与独立复核结果。
[OUTPUT]: 区分已通过行为、开发制品与尚未完成的平台验收。
[POS]: 本仓库验收事实入口，不以核心测试替代完整应用运行。
[PROTOCOL]: Update this header on change, then check AGENTS.md
-->
# 验收记录

日期：2026-11-18，Asia/Shanghai。源码分支：`codex/tasknotes`。
本次实现五端原生工程、Go 服务端、开发包入口、统一协议与交付校验。
**尚未完成 Artifactory 同一提交的全目标实际调度，以及 Apple/Windows 完整开发包验收。**

## 实际结果

| 目标 | 已通过 | 制品与限制 |
|---|---|---|
| iOS / macOS | 14 项 Swift 测试，含真实 Go CRUD、409、缓存与 401 恢复；两端全部 SwiftUI 类型检查 | 完整 Xcode 构建在许可证检查退出 69，未生成应用 ZIP，未运行原生应用 |
| Android | 8 项单测；实际 Gradle assembleDebug；API36 模拟器 UI、离线缓存、重启清空令牌与丢失写入响应恢复 | `dist/tasknotes-android-debug.apk`；未验证 API26 真机、正式签名；笔记修改/删除通过真实协议测试，未逐项 UI 点击 |
| Windows | 锁定 NuGet restore、C# 核心测试、真实 Go CRUD/409/丢响应、完整 WinUI C# 编译；版本读取 0.1.0 | 当前是 macOS 宿主，无法执行 Windows mt.exe/PRI 与原生窗口；未生成自包含发布 ZIP |
| Linux | Rust 4 项核心回归、真实 Go CRUD/409/丢响应、GTK4 check、Ubuntu24.04 amd64 完整 release、ldd 与 --help；Xvfb 下窗口映射并稳定运行 | `dist/tasknotes-linux-x64.tar.gz`；amd64 在 Apple Silicon Docker 中模拟执行，不记为实体 amd64 原生宿主构建 |
| 服务端 | go vet、go test -race、全新 HOME/模块缓存测试与 Linux x64 构建；源码及锁摘要不变 | `dist/tasknotes-server-linux-x64.tar.gz`；Go1.27.3、SQLite1.62.0 |
| OCI | Linux amd64 镜像构建；非 root、只读根文件系统、真实 HTTP CRUD；重建容器后 SQLite 命名卷数据保留 | 本机 `tasknotes-server:0.1.0`；未发布到外部 OCI 仓库 |

Android 清理 build 后禁用构建与配置缓存重跑，8 项单测通过；
36 个源码、配置和锁文件 SHA-256 前后完全一致。
开发签名每次构建重新生成，因此安装验收采用卸载后安装。

Linux 在 Xvfb+Cairo 下由 `xwininfo` 观察到标题为 TaskNotes 的 1060×720 原生窗口，
进程稳定运行 5 秒后主动退出。此检查不替代实体桌面的完整业务操作。

## 共同业务验证

四种客户端核心均连接同一个真实 Go 服务，完成中文任务与笔记的创建、修改、
过期 revision 返回 409、删除和完整快照缓存回读。测试记录均清理。
Swift 解析秒级与小数秒 RFC3339；不同地址的缓存隔离；缓存与配置不保存访问令牌。
未验证连接与读取失败后均只读。任务、笔记两次读取均成功后才交换完整快照。

补充恢复回归：

- 同地址更换令牌保留失败草稿；Apple 编辑器内可打开连接设置。
- 写入已落库但响应丢失时禁止重复提交；刷新后仍需人工核对解除。
- Windows/Linux 编辑地址后必须先连接，不能在显示 B 地址时向 A 写入。
- Android 在 API36 模拟器验证了未知写入结果、同地址重连与明确核对路径；服务只收到一次 POST。

## 工程与交付

- OpenAPI 3.1 通过 `openapi-spec-validator 0.7.2`；公共样例通过 JSON Schema 严格验证。
- 3 项交付测试通过：篡改摘要、路径越界、外部文件与符号链接拒绝。
- `scripts/check_repo.py` 检查内部协议引用、公共样例、L2/L3 与人工维护文件 800 行约束。
  上游生成的依赖锁文件不拆分，不适用人工文件行数约束。
- 构建入口生成平台、架构、版本、Git 提交、工具版本、文件大小与 SHA-256 清单。
- 独立全仓复核发现的 6 项问题已修复，限定复核 open=0；未把环境限制记为通过。

服务器镜像首轮因宿主 Docker 镜像代理 TLS 超时失败。
改用显式 `GO_IMAGE` 后，默认 Go 模块代理在容器中超时。
以 `GO_IMAGE=public.ecr.aws/docker/library/golang:1.27.3-bookworm`、
`GOPROXY=https://goproxy.cn,direct` 显式构建成功，没有修改全局 Docker 配置。

## 待完成的验收

1. 使用者接受 Xcode 许可证并完成首次启动组件后，构建两个 Apple ZIP，验证模拟器与 macOS 窗口。
2. 在原生 Windows 节点构建自包含 ZIP，解包启动并逐项操作任务与笔记。
3. 在实体 Linux amd64 图形会话验证输入法、前后台刷新和断网恢复。
4. 将固定源码提交推送到平台可读 Git，按 `artifactory.md` 创建五客户端及独立服务端目标。
5. 下载全部目标制品并复核清单，再逐端执行跨设备同步；构建和运行分开记录。

既有文档中的本机 Artifactory HTTP 入口未在线，当前默认 Kubernetes context 的旧地址连接被拒绝。
本次没有创建平台项目、实际构建任务、内部 Release 或外部镜像发布。

详细平台证据见 `apple/IMPLEMENTATION.md`、`android/IMPLEMENTATION.md`、
`windows/IMPLEMENTATION.md` 与 `linux/IMPLEMENTATION.md`。
临时日志与测试令牌保存在忽略目录 `.local/`，不随 Git 和开发包分发。
