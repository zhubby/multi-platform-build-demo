# Linux 实现与验证

实现 GTK4 原生任务与笔记双栏界面，完整 CRUD、完成标记、筛选与搜索。
后台工作线程执行有超时的 HTTP，主循环只接收结果并更新原生控件。
编辑草稿只存控件；网络刷新不改草稿，写入和刷新均成功后才清空。
快照按 URL SHA-256 隔离。两个读取均成功后才原子替换文件与内存。
未验证、401、409 与断网均撤销写权限。错误提示保留草稿与缓存时间。
启动、窗口激活与手动刷新读取；没有后台网络轮询和写入队列。
令牌仅驻留内存，配置只保存地址。

2026-11-18：macOS arm64 使用 Rust 1.90.0 执行无 GTK 核心测试。
首轮 Unicode 标题测试出现预期失败，再实现核心。
四个核心测试通过：Unicode 标题、共享 JSON 与中文 emoji、URL 缓存隔离、
原子缓存替换、令牌排除、真实本地 TCP 部分刷新与只读写入拒绝。

显式配置联机回归通过：真实 Go 服务任务/笔记创建、修改、
409 撤销写权限、刷新、删除与删除后缓存。创建记录已清理。
命令：cargo run --locked --no-default-features --example live -- <配置路径>。

Ubuntu 24.04 amd64 模拟容器中 GTK 编译检查通过。
环境：Rust 1.90.0，GTK 4.14.5；改用 DropDown 后无警告。
release 构建通过，用时 2 分 13 秒。
制品：dist/tasknotes-linux-x64.tar.gz，包含 ELF 与 README。
Ubuntu 容器 ldd 未发现缺失动态库；原生 --help 返回 0。
随后执行 Xvfb 原生窗口启动检查。
xwininfo 观察到 TaskNotes 1060×720 窗口，进程稳定 5 秒后主动结束。
此检查确认 GTK 初始化与窗口映射，不等同 GUI 业务操作验收。
GUI 交互与真实 Ubuntu 桌面运行仍需逐端验收。
跨端核心已连接同一真实 Go 服务验证。
容器在 arm64 Mac 上模拟 amd64，不等同实体 amd64 桌面运行。

复核修正：同 URL 重连仅更新内存令牌，不清草稿。
输入地址与已连接地址不一致时，刷新、保存和删除均拒绝。
写入成功后刷新失败，或写入响应丢失时，保留草稿并阻止再次写入。
成功刷新后仍需显式核对列表，才解除不确定状态。
新增回归通过：地址 A/B 防串写、成功提交后刷新失败、
真实 Go 服务已保存 POST 后主动丢响应、刷新后阻止重复 POST。
真实服务测试记录均已清理。

根入口验证通过：scripts/build.sh linux build。
统一清单已生成，摘要复核通过。打包 ELF 与 release ELF 摘要一致。
临时容器 tasknotes-linux-release 和 linux/.local/ 下的日志保留供复核。

GUI 启动证据：linux/.local/gui-window-tree.log 与 gui-startup.log。
Xvfb 日志含无 DRI3 与无会话总线提示；使用 Cairo 渲染仍成功映射窗口。
检查结束已退出应用和 Xvfb；保留构建容器。
