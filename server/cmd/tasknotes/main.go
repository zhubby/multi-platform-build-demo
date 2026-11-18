// [INPUT]: TASKNOTES_ADDR、TASKNOTES_DB、TASKNOTES_TOKEN 与退出信号。
// [OUTPUT]: 提供 TaskNotes HTTP 服务与优雅关闭。
// [POS]: 服务端进程入口；令牌不进入日志和命令行。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/zhubby/multi-platform-build-demo/server/internal/tasknotes"
)

var version = "dev"
var commit = "unknown"

func main() {
	showVersion := flag.Bool("version", false, "显示版本与源码提交")
	flag.Parse()
	if *showVersion {
		fmt.Printf("TaskNotes %s (%s)\n", version, commit)
		return
	}
	if err := run(); err != nil {
		slog.Error("服务退出", "error", err)
		os.Exit(1)
	}
}

func run() error {
	token := os.Getenv("TASKNOTES_TOKEN")
	if token == "" {
		return errors.New("请通过 TASKNOTES_TOKEN 设置访问令牌")
	}
	store, err := tasknotes.OpenStore(env("TASKNOTES_DB", "data/tasknotes.db"))
	if err != nil {
		return fmt.Errorf("打开数据库: %w", err)
	}
	defer store.Close()
	server := &http.Server{Addr: env("TASKNOTES_ADDR", "127.0.0.1:8080"), Handler: tasknotes.NewHandler(store, token), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 15 * time.Second, WriteTimeout: 20 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 32 * 1024}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	result := make(chan error, 1)
	go func() {
		slog.Info("TaskNotes 服务启动", "addr", server.Addr, "version", version, "commit", commit)
		result <- server.ListenAndServe()
	}()
	select {
	case err := <-result:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	case <-ctx.Done():
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return server.Shutdown(shutdown)
	}
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
