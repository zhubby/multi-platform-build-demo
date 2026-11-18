# TaskNotes Linux

目标为 Ubuntu 24.04 amd64。使用 Rust 1.90.0 与原生 GTK4 4.12+。

```sh
sudo apt-get update
sudo apt-get install build-essential pkg-config libgtk-4-dev libssl-dev ca-certificates git python3
./build.sh test
./build.sh check
./build.sh build
```

构建入口使用 `cargo --locked`，遵守 CARGO_TARGET_DIR。
制品：`../dist/tasknotes-linux-x64.tar.gz`。
运行宿主安装 `libgtk-4-1 ca-certificates`，解压后运行 `tasknotes/tasknotes`。
GTK 动态链接系统包；压缩包包含应用与说明，不打包 Ubuntu 系统库。

输入服务地址与令牌，连接后编辑。令牌只驻留内存。
任务支持增删改、完成标记、完成筛选与标题搜索。
笔记支持增删改与标题、正文搜索。双击列表记录载入编辑器。
未验证或刷新失败时缓存只读。启动、回前台与手动刷新读取完整快照。
失败保留编辑草稿；409 后刷新并检查草稿。新建或切换类型主动清空编辑器。
地址保存在 XDG_DATA_HOME/tasknotes/address.txt（默认 ~/.local/share）。
缓存按 URL SHA-256 隔离，只保存快照与最后刷新时间，不保存令牌。
HTTP 仅用于内网开发；正式分发使用 HTTPS。

联机回归仅显式执行：`cargo run --locked --no-default-features --example live -- <配置路径>`。
配置 JSON 包含 url 和 token；不要提交配置。回归自动清理本次记录。

连接同一地址更换令牌会保留草稿。地址编辑后先连接，再刷新或写入。
写入响应丢失或提交后刷新失败时，结果标为不确定。
先刷新并检查列表，点击“已核对写入结果”，再继续编辑，防止重复创建。
