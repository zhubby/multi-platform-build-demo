# [INPUT]: 已锁定 Go 模块与服务端源码。
# [OUTPUT]: 非 root、无 CGO 的 TaskNotes OCI 运行镜像。
# [POS]: 独立服务端镜像入口；不包含其他客户端工程。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
ARG GO_IMAGE=golang:1.27.3-bookworm
FROM ${GO_IMAGE} AS build
WORKDIR /src
COPY go.mod go.sum ./
ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY}
ENV GOFLAGS="-mod=readonly -modcacherw"
RUN go mod download
COPY . .
ARG VERSION=dev
ARG COMMIT=unknown
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}" -o /tasknotes ./cmd/tasknotes
RUN mkdir /data && chown 65532:65532 /data && chmod 700 /data

FROM scratch
COPY --from=build /tasknotes /tasknotes
COPY --from=build --chown=65532:65532 /data /data
USER 65532:65532
ENV TASKNOTES_ADDR=0.0.0.0:8080 TASKNOTES_DB=/data/tasknotes.db
VOLUME ["/data"]
EXPOSE 8080
ENTRYPOINT ["/tasknotes"]
