# Android 实现与验证

原生 Kotlin + Jetpack Compose。最低 Android 8（API 26）。
编译与目标 SDK 36，Build Tools 36.0.0，JDK 17。
应用 ID：`com.tasknotes.app`。版本读取根 `VERSION`。

## 构建与安装

在仓库根执行：

```sh
./android/build.sh check
./android/build.sh test
./android/build.sh build
```

支持 `JAVA_HOME` 与 `ANDROID_SDK_ROOT`。macOS 自动发现 JDK 17。
默认 SDK 位于 `$HOME/Library/Android/sdk`。其他宿主须设置 SDK 环境变量。
构建不写 `local.properties`，不安装 SDK，不修改全局配置。
Gradle 8.11.1、AGP 8.10.1、Kotlin 2.1.20 和 Compose BOM 2025.04.01 固定。
版本目录为 `gradle/libs.versions.toml`。
官方 Gradle 发行版由 wrapper 内的 SHA256 校验。
`app/gradle.lockfile` 冻结依赖图。正常构建使用严格锁，不更新锁。
`settings-gradle.lockfile` 冻结 Gradle 设置配置。

APK 输出为根 `dist/tasknotes-android-debug.apk`。
每次 `build` 生成新的调试签名。安装前必须卸载旧包：

```sh
adb uninstall com.tasknotes.app
adb install dist/tasknotes-android-debug.apk
```

首次安装省略卸载命令。卸载会清空缓存及服务地址。
开发 APK 不提供正式签名。不能覆盖安装不同签名的旧开发包。

本机验证发现用户级 Gradle 配置包含失效代理。
验证调用使用下列临时参数，不修改该配置：

```sh
GRADLE_ARGS='-Dhttp.proxyHost= -Dhttps.proxyHost= -Dhttp.nonProxyHosts=*' ./android/build.sh test
```

官方 Gradle 下载路径在本机超时。
验证先用镜像下载发行版并核对官方 SHA256，再填充本机 wrapper 缓存。
工程仍使用官方发行版地址；未固化镜像或本机路径。

## 业务边界

任务支持创建、修改、删除、完成状态及本地筛选。
笔记支持创建、修改、删除和正文编辑。
搜索在完整快照执行，笔记匹配标题与正文。
界面采用中文系统主题与原生 Compose 控件。

设置仅持久化服务地址。令牌只保存在进程内存。
应用进程重启后须重新输入令牌。缓存和配置不包含令牌。
缓存以规范化 URL 的 SHA256 隔离，保存在应用私有目录。
任务与笔记均读取成功后，原子替换一个完整快照。
启动、回到前台与手动刷新触发读取。没有后台轮询。
未验证连接或刷新失败时只读，显示缓存时间与重试入口。
开发清单允许内网 HTTP。正式分发须使用 HTTPS 与正式签名。

草稿按服务地址保留在内存，同地址重连不清除草稿。
写入失败或写入后刷新失败不会关闭编辑器或丢弃草稿。
409 要求刷新并核对新内容，不自动覆盖其他设备更新。
已收到成功写入结果但刷新失败时，草稿保留服务端 ID 和修订号。
传输失败或未知服务错误导致写入结果不确定时，禁止再次保存和删除。
刷新成功仍保留锁定，用户核对后点击“已核对结果，继续编辑”才解除。
若列表已有该记录，应丢弃新建草稿并从列表打开。
没有离线写入队列，不自动重试写入。

## 2026-11-18 验证记录

- `check` 通过；JDK 17、SDK 36 与 Gradle wrapper 均可用。
- 正式 Gradle JVM 单测共 8 项通过。
- 共享样例、中文与 emoji、URL 缓存隔离和 HTTP 409 先失败后通过。
- 响应丢失、未知错误和显式确认规则先出现 3 项失败，再全部通过。
- 真实 Go 服务通过任务与笔记 CRUD、旧修订号 409、完整刷新与缓存回读。
- API 36 模拟器实际安装和启动开发 APK。
- 模拟器通过连接配置、任务创建、完成状态、搜索与删除，以及笔记创建。
- 模拟器检查私有配置和缓存，确认不存在测试令牌。
- 真实代理在 Go 提交 POST 后丢弃响应。界面保留草稿并锁定保存。
- 刷新和同 URL 重连后仍锁定，用户确认后解锁；服务只收到一次 POST。
- 离线刷新后缓存字节不变，记录继续可读，写入按钮禁用。
- 进程重启读取只读缓存，并要求重新输入内存令牌。
- 测试创建的服务端记录均已删除。
- `clean` 后禁用构建缓存与配置缓存，8 项单测及 APK 重建通过。
- 重建复用已下载的依赖缓存；不是空依赖缓存联网验收。
- 36 个源码、配置与锁文件的 SHA256 在清理重建前后完全一致。

单测报告位于 `app/build/reports/tests/testDebugUnitTest/index.html`。
AGP 对本机新 SDK 元数据发出版本提示，但单测和打包成功。
图形路径库保留原生调试符号，未阻止 APK 打包与模拟器运行。

未验证 API 26 真机、不同厂商系统及正式签名分发。
模拟器上的笔记修改与删除未逐项点击验收；协议层对应 CRUD 已连接真实服务验证。

[PROTOCOL]: Update this header on change, then check AGENTS.md
