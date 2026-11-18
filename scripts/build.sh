#!/bin/sh
# [INPUT]: 目标、动作与预装的原生 SDK。
# [OUTPUT]: 执行平台入口，生成统一制品清单并立即校验。
# [POS]: Artifactory 与开发者共用的根构建接口。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
target=${1:-}
action=${2:-build}
tool_version=""
case "$target" in
  server) sh "$root/server/build.sh" "$action"; arch=x64; artifact=tasknotes-server-linux-x64.tar.gz; tool_version="go=$(cd "$root/server" && go version)" ;;
  android)
    if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
      JAVA_HOME=$(/usr/libexec/java_home -v 17)
      export JAVA_HOME
    fi
    sh "$root/android/build.sh" "$action"
    arch=universal; artifact=tasknotes-android-debug.apk
    tool_version="java=$("${JAVA_HOME:+$JAVA_HOME/bin/}java" -version 2>&1 | head -n 1)"
    ;;
  ios|macos)
    if [ "$action" = build ]; then platform_action=$target; else platform_action=$action; fi
    bash "$root/apple/build.sh" "$platform_action"
    arch=arm64
    if [ "$target" = ios ]; then artifact=tasknotes-ios-arm64-simulator.zip; else artifact=tasknotes-macos-arm64.zip; fi
    developer_root=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
    tool_version="xcode=$(DEVELOPER_DIR="$developer_root" xcodebuild -version | tr '\n' ' ')"
    ;;
  linux) bash "$root/linux/build.sh" "$action"; arch=x64; artifact=tasknotes-linux-x64.tar.gz; tool_version="rust=$(cd "$root/linux" && rustc --version)" ;;
  windows)
    printf '请在 Windows 原生节点运行 windows/build.ps1；清单命令见 docs/artifactory.md。\n' >&2
    exit 2 ;;
  *) printf '用法: scripts/build.sh server|android|ios|macos|linux check|test|build\n' >&2; exit 2 ;;
esac
if [ "$action" = build ]; then
  python3 "$root/scripts/package.py" create --target "$target" --arch "$arch" \
    --artifact "$root/dist/$artifact" --tool "$tool_version"
  python3 "$root/scripts/package.py" verify "$root/dist/tasknotes-$target-$arch-manifest.json"
fi
