# linux/
> L2 | Parent: ../AGENTS.md
src/：GTK4 入口与无界面核心。
examples/：显式配置驱动的真实服务回归。
tests/：公共 JSON、缓存与 HTTP 原子快照回归。
Cargo.toml：Rust 2021 包；desktop 特性隔离 GTK。
Cargo.lock：完整依赖锁图，所有构建使用 --locked。
rust-toolchain.toml：锁定 Rust 1.90.0 和 rustfmt。
build.sh：Ubuntu amd64 检查、测试与 tar.gz 发布。
README.md：系统包、安装、操作与离线规则。
IMPLEMENTATION.md：实现范围、验证证据与平台缺口。
[PROTOCOL]: Update this header on change, then check AGENTS.md
