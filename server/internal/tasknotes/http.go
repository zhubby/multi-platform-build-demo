// [INPUT]: net/http、版本化 JSON 契约与 Store。
// [OUTPUT]: 提供 NewHandler，执行鉴权、字段校验与 CRUD。
// [POS]: 对外 HTTP 边界；隐藏存储错误并保留稳定状态码。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
package tasknotes

import (
	"crypto/subtle"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"
)

const maxRequestBytes = 2 * 1024 * 1024

type handler struct {
	store *Store
	token string
}

func NewHandler(store *Store, token string) http.Handler { return &handler{store: store, token: token} }

func (h *handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	if r.URL.Path == "/healthz" && r.Method == http.MethodGet {
		writeJSON(w, 200, map[string]string{"status": "ok"})
		return
	}
	expected := "Bearer " + h.token
	if h.token == "" || subtle.ConstantTimeCompare([]byte(r.Header.Get("Authorization")), []byte(expected)) != 1 {
		w.Header().Set("WWW-Authenticate", `Bearer realm="TaskNotes"`)
		writeError(w, 401, "unauthorized", "访问令牌无效，请重新连接。")
		return
	}
	segments := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(segments) < 3 || len(segments) > 4 || segments[0] != "api" || segments[1] != "v1" || (segments[2] != "tasks" && segments[2] != "notes") {
		writeError(w, 404, "not_found", "记录不存在。")
		return
	}
	kind := segments[2]
	id := ""
	if len(segments) == 4 {
		id = segments[3]
	}
	switch {
	case r.Method == http.MethodGet && id == "":
		records, err := h.store.List(r.Context(), kind)
		if h.storeError(w, err) {
			return
		}
		items := make([]map[string]any, 0, len(records))
		for _, record := range records {
			items = append(items, record.public(kind))
		}
		writeJSON(w, 200, map[string]any{"items": items})
	case r.Method == http.MethodGet && id != "":
		record, err := h.store.Get(r.Context(), kind, id)
		if h.storeError(w, err) {
			return
		}
		writeJSON(w, 200, record.public(kind))
	case (r.Method == http.MethodPost && id == "") || (r.Method == http.MethodPut && id != ""):
		input, ok := decodeWrite(w, r, kind, r.Method == http.MethodPut)
		if !ok {
			return
		}
		var record Record
		var err error
		status := 200
		if r.Method == http.MethodPost {
			record, err = h.store.Create(r.Context(), kind, input)
			status = 201
		} else {
			record, err = h.store.Update(r.Context(), kind, id, input)
		}
		if h.storeError(w, err) {
			return
		}
		if status == 201 {
			w.Header().Set("Location", "/api/v1/"+kind+"/"+record.ID)
		}
		writeJSON(w, status, record.public(kind))
	case r.Method == http.MethodDelete && id != "":
		revision, err := strconv.ParseInt(r.URL.Query().Get("revision"), 10, 64)
		if err != nil || revision < 1 {
			writeError(w, 400, "invalid_request", "删除操作需要有效的修订号。")
			return
		}
		if h.storeError(w, h.store.Delete(r.Context(), kind, id, revision)) {
			return
		}
		w.WriteHeader(204)
	default:
		if id == "" {
			w.Header().Set("Allow", "GET, POST")
		} else {
			w.Header().Set("Allow", "GET, PUT, DELETE")
		}
		writeError(w, 405, "method_not_allowed", "此路径不支持该请求方法。")
	}
}

func decodeWrite(w http.ResponseWriter, r *http.Request, kind string, updating bool) (writeRequest, bool) {
	var input writeRequest
	r.Body = http.MaxBytesReader(w, r.Body, maxRequestBytes)
	decoder := json.NewDecoder(r.Body)
	var fields map[string]json.RawMessage
	err := decoder.Decode(&fields)
	if err == nil {
		allowed := map[string]bool{"title": true}
		if kind == "tasks" {
			allowed["completed"] = true
		} else {
			allowed["body"] = true
		}
		if updating {
			allowed["revision"] = true
		}
		for name := range fields {
			if !allowed[name] {
				err = errors.New("unexpected field")
				break
			}
		}
		if fields == nil {
			err = errors.New("object required")
		}
		if err == nil {
			data, _ := json.Marshal(fields)
			err = json.Unmarshal(data, &input)
		}
	}
	if err == nil {
		var extra any
		if trailing := decoder.Decode(&extra); trailing != io.EOF {
			if trailing == nil {
				trailing = errors.New("extra JSON")
			}
			err = trailing
		}
	}
	if err != nil {
		var tooLarge *http.MaxBytesError
		if errors.As(err, &tooLarge) {
			writeError(w, 413, "request_too_large", "请求体超过 2 MiB。")
		} else {
			writeError(w, 400, "invalid_request", "请求必须是符合接口契约的 JSON 对象。")
		}
		return input, false
	}
	if input.Title == nil {
		writeError(w, 400, "invalid_request", "请填写标题。")
		return input, false
	}
	trimmed := strings.TrimSpace(*input.Title)
	input.Title = &trimmed
	if utf8.RuneCountInString(trimmed) < 1 || utf8.RuneCountInString(trimmed) > 200 {
		writeError(w, 400, "invalid_request", "标题必须包含 1–200 个字符。")
		return input, false
	}
	validFields := (kind == "tasks" && input.Completed != nil && input.Body == nil) || (kind == "notes" && input.Body != nil && input.Completed == nil && len(*input.Body) <= 1024*1024)
	validRevision := (!updating && input.Revision == nil) || (updating && input.Revision != nil && *input.Revision > 0)
	if !validFields || !validRevision {
		writeError(w, 400, "invalid_request", "字段缺失、正文过长或修订号无效。")
		return input, false
	}
	return input, true
}

func (h *handler) storeError(w http.ResponseWriter, err error) bool {
	if err == nil {
		return false
	}
	switch {
	case errors.Is(err, ErrNotFound):
		writeError(w, 404, "not_found", "记录不存在。")
	case errors.Is(err, ErrConflict):
		writeError(w, 409, "conflict", "记录已在其他设备修改，请刷新后重试。")
	default:
		slog.Error("数据库操作失败", "error", err)
		writeError(w, 500, "internal_error", "服务暂时不可用，请稍后重试。")
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}
func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]any{"error": map[string]string{"code": code, "message": message}})
}
