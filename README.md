<!--
[INPUT]: 五个原生客户端、Go 服务端与构建验收文档。
[OUTPUT]: 提供产品说明、快速启动与平台入口。
[POS]: 仓库阅读入口；构建结果以验收记录为准。
[PROTOCOL]: Update this header on change, then check AGENTS.md
-->
# TaskNotes

用于验证 [Artifactory](https://github.com/zhubby/artifactory) 的真实多平台构建仓库。
手机记录任务与笔记，桌面整理，通过内网自托管服务同步。

五端均使用原生界面：SwiftUI、Jetpack Compose、WinUI 3、GTK4。
支持任务完成状态、笔记编辑、搜索与缓存。断网时只读，恢复连接后刷新；
修订冲突保留草稿，不覆盖另一端的修改。访问令牌只保留在当前会话。

| 工程 | 技术 | 开发制品 |
|---|---|---|
| `apple/` | Swift 6、SwiftUI，iOS/macOS 共用领域模块 | iOS arm64 模拟器 ZIP、macOS arm64 ad-hoc ZIP |
| `android/` | Kotlin、Jetpack Compose、Gradle | Debug APK |
| `windows/` | C#、WinUI 3 | Windows x64 自包含 ZIP |
| `linux/` | Rust、GTK4 | Ubuntu 24.04 x64 tar.gz |
| `server/` | Go、纯 Go SQLite | Linux x64 二进制包、OCI 镜像 |

## 启动服务端

需要 Go 1.27.3。以下命令在仓库根目录运行：

```sh
export TASKNOTES_TOKEN="$(openssl rand -hex 24)"
(cd server && go run -mod=readonly -modcacherw ./cmd/tasknotes)
```

服务默认监听 `127.0.0.1:8080`。客户端填写服务地址和同一个访问令牌。
手机连接内网服务时使用宿主 IP；Android 模拟器访问宿主使用 `10.0.2.2`。
容器和持久化配置见 [服务端快速启动](docs/server-quickstart.md)。

## 构建与验证

在具有对应 SDK 的原生宿主执行。所有开发制品输出到 `dist/`。

```sh
python3 scripts/check_repo.py
python3 -m unittest discover -s scripts -p 'test_*.py' -v
sh scripts/build.sh server test
sh scripts/build.sh server build
sh scripts/build.sh android build
sh scripts/build.sh ios build
sh scripts/build.sh macos build
sh scripts/build.sh linux build
```

Windows 使用 PowerShell：

```powershell
./windows/build.ps1 -Action test
./windows/build.ps1 -Action build
python scripts/package.py create --target windows --arch x64 --artifact dist/tasknotes-windows-x64.zip
```

根构建入口同时生成清单和 SHA256SUMS。下载后重新校验：

```sh
python3 scripts/package.py verify dist/tasknotes-server-x64-manifest.json
```

不同平台的构建命令需要各自的原生宿主，不能在 macOS 上据此宣称 Windows 或 Linux 构建通过。
开发包不包含正式发行签名、公证或 iPhone 真机 IPA。

## 文档

- [开发与各端启动](docs/development.md)
- [API 契约](contracts/API.md) · [OpenAPI 3.1](contracts/openapi.json)
- [Artifactory 目标与构建约定](docs/artifactory.md)
- [真实验收结果与缺口](docs/acceptance.md)
- [实施计划](docs/implementation-plan.md)
