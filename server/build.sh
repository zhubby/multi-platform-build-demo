#!/bin/sh
# [INPUT]: Go、VERSION、Git 与可选 ARTIFACTORY_WORK_DIR。
# [OUTPUT]: 检查、测试或生成 Linux x64 服务端归档。
# [POS]: 本机与原生构建节点共用的服务端入口。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
action=${1:-build}
cd "$root/server"
export GOFLAGS="-mod=readonly -modcacherw ${GOFLAGS:-}"
case "$action" in
  check) go vet ./... ;;
  test) go test -race ./... ;;
  build)
    work=${ARTIFACTORY_WORK_DIR:-"$root/.local/server"}
    mkdir -p "$root/dist" "$work/package"
    version=$(cat "$root/VERSION")
    commit=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null) || commit=unknown
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
      -ldflags "-s -w -X main.version=$version -X main.commit=$commit" \
      -o "$work/package/tasknotes-server" ./cmd/tasknotes
    cp "$root/docs/server-quickstart.md" "$work/package/README.md"
    tar -czf "$root/dist/tasknotes-server-linux-x64.tar.gz" -C "$work/package" tasknotes-server README.md
    ;;
  *) printf '用法: server/build.sh check|test|build\n' >&2; exit 2 ;;
esac
