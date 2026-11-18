<!--
[INPUT]: 服务端归档或 Compose 镜像与内网地址。
[OUTPUT]: 提供单用户令牌、持久化目录与启动步骤。
[POS]: 与二进制开发包一同分发的服务入口。
[PROTOCOL]: Update this header on change, then check AGENTS.md
-->
# 服务端快速启动

解压后在 Linux x64 执行。通过环境变量提供随机访问令牌，不把令牌提交到 Git。

```sh
export TASKNOTES_TOKEN="$(openssl rand -hex 24)"
export TASKNOTES_ADDR=127.0.0.1:8080
export TASKNOTES_DB="$PWD/data/tasknotes.db"
./tasknotes-server
```

手机连接时，将监听地址改为 `0.0.0.0:8080`，客户端填写宿主的内网 IP 地址，
例如 `http://192.168.1.20:8080`。访问令牌与 `TASKNOTES_TOKEN` 相同。
iOS 模拟器可用 `http://127.0.0.1:8080`；Android 模拟器可用 `http://10.0.2.2:8080`。
开发客户端允许内网 HTTP；不要通过公网转发该开发入口。

在仓库根目录使用 Compose：

```sh
export TASKNOTES_TOKEN="$(openssl rand -hex 24)"
docker compose up --build -d
curl http://127.0.0.1:8080/healthz
```

默认只发布环回端口。手机访问前设置 `TASKNOTES_BIND_ADDRESS=0.0.0.0` 并重建容器。
数据保存在 `tasknotes-data` 命名卷；普通重启和重新构建保留数据。
若节点不能访问默认镜像或模块代理，构建前显式设置：

```sh
export TASKNOTES_GO_IMAGE=public.ecr.aws/docker/library/golang:1.27.3-bookworm
export TASKNOTES_GOPROXY=https://goproxy.cn,direct
```

启动配置必须持续使用同一个令牌。令牌变更后，各客户端重新连接。
退出进程后客户端不保留令牌；任务与笔记缓存仍可离线阅读。
