#!/usr/bin/env bash
# [INPUT]: 使用 Rust 锁文件、GTK4 开发包与可选 CARGO_TARGET_DIR。
# [OUTPUT]: 检查、测试或生成 Ubuntu x64 完整 tar.gz。
# [POS]: Linux 唯一构建入口；不改源码和锁文件。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
set -euo pipefail
cd "$(dirname "$0")"
action="${1:-build}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$PWD/target}"
case "$CARGO_TARGET_DIR" in /*) ;; *) CARGO_TARGET_DIR="$PWD/$CARGO_TARGET_DIR"; export CARGO_TARGET_DIR;; esac
if [[ "$action" == test ]]; then cargo test --locked --no-default-features; exit; fi
[[ "$(uname -s)" == Linux && "$(uname -m)" == x86_64 ]] || { echo "完整构建需要 Ubuntu 24.04 amd64；核心测试可用 build.sh test" >&2; exit 1; }
pkg-config --atleast-version=4.12 gtk4
if [[ "$action" == check ]]; then cargo check --locked; exit; fi
[[ "$action" == build ]] || { echo "用法：$0 check|test|build" >&2; exit 2; }
cargo build --release --locked
version="$(cat ../VERSION)"
mkdir -p ../dist
stage="$(mktemp -d)"; trap "rm -rf \"$stage\"" EXIT
mkdir -p "$stage/tasknotes"
cp "$CARGO_TARGET_DIR/release/tasknotes" "$stage/tasknotes/"
cp README.md "$stage/tasknotes/"
tar -C "$stage" -czf "../dist/tasknotes-linux-x64.tar.gz" tasknotes
