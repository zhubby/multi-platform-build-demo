<!--
[INPUT]: 冻结 API、Swift 测试与本机工具链验证结果。
[OUTPUT]: 提供双平台实现说明、构建入口与未完成的验收边界。
[POS]: Apple 客户端的交付和验证记录。
[PROTOCOL]: Update this header on change, then check AGENTS.md
-->
# Apple 客户端

SwiftUI 界面支持 iOS 17+ 与 macOS 14+。
两个独立应用 target 共用本地 `TaskNotesCore` Swift 包。
无第三方依赖。运行测试需 Swift 6+ / Xcode 16+。
Xcode 工程与共享 schemes 已保存在源码中。

## 实现

- `Sources/TaskNotesCore/`：RFC3339 日期、完整更新、revision 删除、HTTP 错误与共享状态机。
- `SnapshotCache`：服务地址 SHA-256 文件名，完整快照原子替换；读回再次核对地址。
- `Workspace`：启动缓存只读；两类读取全部成功并落盘后验证连接；连接世代拒绝旧请求覆盖新地址。
- `App/`：原生侧栏、任务 CRUD 与完成筛选、笔记 CRUD、当前快照搜索、刷新、前台刷新和连接配置。
- 编辑器保留失败草稿。409 后显示新版本供人工核对，再显式采用新 revision。
- 任务与笔记编辑器提供嵌套连接设置。401 后重输令牌无需关闭草稿。
  同地址验证成功后，返回外层编辑器继续保存原标题、正文与完成状态。
- 写入成功但刷新失败，或网络中断导致结果未知时，保留草稿并阻止重复提交。
- 草稿绑定原服务地址。另一个窗口切换服务后，旧草稿不能写入新服务。
- 仅服务地址进入 UserDefaults。令牌只在进程内存。URL 不接受账号、密码、查询或片段。
- 开发包允许内网 HTTP。正式分发需要 HTTPS 与正式签名配置。

## 构建入口

从仓库根运行：

```sh
./apple/build.sh check
ARTIFACTORY_WORK_DIR=/tmp/tasknotes-build ./apple/build.sh test
ARTIFACTORY_WORK_DIR=/tmp/tasknotes-build ./apple/build.sh ios
ARTIFACTORY_WORK_DIR=/tmp/tasknotes-build ./apple/build.sh macos
```

构建前须由使用者阅读并同意 Xcode 许可证，完成 Xcode 首次启动所需组件。
脚本只检查许可证与组件状态，不自动同意条款。
`DEVELOPER_DIR` 可指定完整 Xcode 的 Developer 目录。

应用构建先复制工程到 `ARTIFACTORY_WORK_DIR` 的独立子目录。
DerivedData、SwiftPM 产物和结果包均保存在工作目录。
构建不改写仓库工程、源码或锁文件。
版本从根 `VERSION` 传入，不改写 plist。

输出：

- `dist/tasknotes-ios-arm64-simulator.zip`：arm64 iOS Simulator 的 `TaskNotes.app`。
- `dist/tasknotes-macos-arm64.zip`：arm64 macOS 的 ad-hoc 签名 `TaskNotes.app`。

iOS ZIP 不是 IPA，不能安装到真实 iPhone。
macOS 开发包不含 Developer ID 签名或公证。

## 已执行验证（2026-11-18）

工具链：Apple Swift 6.4；完整 Xcode 27.2 已安装。

1. 先运行失败测试，再实现解码、网络、缓存与工作区。
   初次行为运行为 6 测试、9 个失败断言；工作区初次为 4 测试、13 个失败断言。
   本地校验和旧地址草稿边界均额外观察过失败再修复。
2. `build.sh test`：共享 Swift Testing 测试通过。
   包含 13 个独立行为测试，另有 1 个显式启用的真实服务联调测试。
   新增 401 后同地址替换令牌、完整刷新再提交原 revision 笔记的回归测试。
3. 修复 401 编辑器恢复入口后，真实 Go 服务联调与共享回归合计 14 个测试全部通过。
   完成任务与笔记创建、更新、409 拒绝、删除和缓存重启只读。
   随机前缀测试记录已清理。临时服务令牌未写入源码或缓存。
4. macOS arm64 / macOS 14 与 iOS arm64 Simulator / iOS 17 的共享模块和全部 SwiftUI 源文件直接编译器类型检查通过。
   类型检查未执行应用链接、签名、打包或运行。
5. `bash -n apple/build.sh` 通过；PBX 工程和两个 Info.plist 的 `plutil -lint` 通过。
6. `build.sh check` 在许可证检查处退出 69：本机尚未同意 Xcode 许可证。
   未执行自动同意操作，未宣称原生应用构建成功。

当前 CLT 不含完整测试框架路径。
测试入口只读引用已安装 Xcode 的 `Testing.framework`，采用 SwiftPM native 构建系统。
当前 SwiftPM 会输出 native 构建系统弃用提示。
普通回归发现 14 项，其中真实服务联调按显式配置启用；未配置时跳过 1 项。

401 恢复入口经过源码可达性复核：编辑器状态区 → 连接设置 / 重新输入令牌 →
嵌套连接窗口 → 同地址连接并刷新 → 返回草稿 → 保存。
嵌套窗口使用自己的关闭环境；不修改根列表持有的草稿标识。
标题、正文与完成状态仍属于外层编辑器，不随嵌套窗口销毁。
两个平台的修改后界面源码类型检查通过。
此复核与共享状态机回归不等于原生窗口的运行验收。

真实服务联调仅在显式指定配置文件时启用：

```sh
TASKNOTES_INTEGRATION_CONFIG=/absolute/path/to/temporary-config.json \
ARTIFACTORY_WORK_DIR=/tmp/tasknotes-build ./apple/build.sh test
```

配置文件格式为 JSON 对象，含 `url` 与 `token` 字符串。
配置必须位于忽略目录或仓库外，不能提交真实令牌。
普通测试运行会明确跳过真实服务联调。

## 验收限制

Xcode 许可证阻塞完整应用构建，因此本次没有生成 Apple 制品。
没有执行 iOS Simulator、真实 iPhone 或 macOS 应用的交互验收。
系统主题、布局、输入法和无障碍行为需要在原生应用运行后验收。
没有完成跨设备同时编辑、系统前后台切换与断网恢复的端到端操作验收。
共享状态机与真实 HTTP 测试覆盖对应数据边界，不能替代界面验收。
