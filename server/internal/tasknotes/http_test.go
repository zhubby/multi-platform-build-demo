// [INPUT]: 真实 SQLite、httptest 与共享 API 约定。
// [OUTPUT]: 验证鉴权、任务与笔记 CRUD、修订竞争和持久化。
// [POS]: HTTP 对外行为回归，不依赖实现细节。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
package tasknotes

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

const testToken = "tasknotes-test-token"

func fixture(t *testing.T) (http.Handler, *Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "data.db")
	store, err := OpenStore(path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	return NewHandler(store, testToken), store, path
}

func request(t *testing.T, handler http.Handler, method, path, body, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	res := httptest.NewRecorder()
	handler.ServeHTTP(res, req)
	return res
}

func decode(t *testing.T, res *httptest.ResponseRecorder) map[string]any {
	t.Helper()
	var result map[string]any
	if err := json.Unmarshal(res.Body.Bytes(), &result); err != nil {
		t.Fatalf("decode %s: %v", res.Body.String(), err)
	}
	return result
}

func assertStatus(t *testing.T, res *httptest.ResponseRecorder, want int) {
	t.Helper()
	if res.Code != want {
		t.Fatalf("want %d, got %d: %s", want, res.Code, res.Body.String())
	}
}

func TestHealthAndAuthorization(t *testing.T) {
	handler, _, _ := fixture(t)
	assertStatus(t, request(t, handler, "GET", "/healthz", "", ""), 200)
	for _, token := range []string{"", "wrong"} {
		res := request(t, handler, "GET", "/api/v1/tasks", "", token)
		assertStatus(t, res, 401)
		if !strings.Contains(res.Body.String(), "unauthorized") {
			t.Fatal(res.Body.String())
		}
	}
	res := request(t, handler, "GET", "/api/v1/tasks", "", testToken)
	assertStatus(t, res, 200)
	if !bytes.Contains(res.Body.Bytes(), []byte(`"items":[]`)) {
		t.Fatal("empty list must be [], not null", res.Body.String())
	}
}

func TestTaskLifecycleAndConflict(t *testing.T) {
	handler, _, _ := fixture(t)
	created := request(t, handler, "POST", "/api/v1/tasks", `{"title":"  买牛奶 🚀  ","completed":false}`, testToken)
	assertStatus(t, created, 201)
	item := decode(t, created)
	if item["title"] != "买牛奶 🚀" || item["completed"] != false || item["revision"] != float64(1) {
		t.Fatal(item)
	}
	if _, exists := item["body"]; exists {
		t.Fatal("tasks must not expose note body")
	}
	path := "/api/v1/tasks/" + item["id"].(string)
	assertStatus(t, request(t, handler, "GET", path, "", testToken), 200)
	update := request(t, handler, "PUT", path, `{"title":"牛奶已买","completed":true,"revision":1}`, testToken)
	assertStatus(t, update, 200)
	if decode(t, update)["revision"] != float64(2) {
		t.Fatal(update.Body.String())
	}
	assertStatus(t, request(t, handler, "PUT", path, `{"title":"旧草稿","completed":false,"revision":1}`, testToken), 409)
	assertStatus(t, request(t, handler, "DELETE", path+"?revision=1", "", testToken), 409)
	deleted := request(t, handler, "DELETE", path+"?revision=2", "", testToken)
	assertStatus(t, deleted, 204)
	if deleted.Body.Len() != 0 {
		t.Fatal("204 must not have a body")
	}
	assertStatus(t, request(t, handler, "GET", path, "", testToken), 404)
	assertStatus(t, request(t, handler, "DELETE", path+"?revision=2", "", testToken), 404)
}

func TestNotesPersistAcrossStoreReopen(t *testing.T) {
	handler, store, path := fixture(t)
	created := request(t, handler, "POST", "/api/v1/notes", `{"title":"内网说明","body":"第一行\n第二行 🚀"}`, testToken)
	assertStatus(t, created, 201)
	item := decode(t, created)
	if _, exists := item["completed"]; exists {
		t.Fatal("notes must not expose task state")
	}
	if err := store.Close(); err != nil {
		t.Fatal(err)
	}
	reopened, err := OpenStore(path)
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	res := request(t, NewHandler(reopened, testToken), "GET", "/api/v1/notes/"+item["id"].(string), "", testToken)
	assertStatus(t, res, 200)
	if decode(t, res)["body"] != "第一行\n第二行 🚀" {
		t.Fatal(res.Body.String())
	}
}

func TestStrictValidation(t *testing.T) {
	handler, _, _ := fixture(t)
	for _, body := range []string{`{}`, `{"title":"","completed":false}`, `{"title":"x"}`, `{"title":"x","completed":false,"extra":1}`, `{"title":"x","completed":false} {}`, `{"title":"x","completed":"no"}`, `null`, `{"title":"x","completed":false,"body":null}`, `{"title":"x","completed":false,"revision":null}`} {
		t.Run(body, func(t *testing.T) {
			assertStatus(t, request(t, handler, "POST", "/api/v1/tasks", body, testToken), 400)
		})
	}
	tooLong, _ := json.Marshal(map[string]any{"title": strings.Repeat("中", 201), "completed": false})
	assertStatus(t, request(t, handler, "POST", "/api/v1/tasks", string(tooLong), testToken), 400)
	assertStatus(t, request(t, handler, "POST", "/api/v1/notes", `{"title":"标题"}`, testToken), 400)
	assertStatus(t, request(t, handler, "DELETE", "/api/v1/tasks/unknown", "", testToken), 400)
	assertStatus(t, request(t, handler, "PATCH", "/api/v1/tasks", "", testToken), 405)
	assertStatus(t, request(t, handler, "GET", "/api/v1/unknown", "", testToken), 404)
	res := request(t, handler, "POST", "/api/v1/notes", `{"title":"x","body":"`+strings.Repeat("x", 2*1024*1024)+`"}`, testToken)
	assertStatus(t, res, 413)
}

func TestConcurrentRevisionAllowsOneWriter(t *testing.T) {
	handler, _, _ := fixture(t)
	res := request(t, handler, "POST", "/api/v1/notes", `{"title":"初始","body":""}`, testToken)
	assertStatus(t, res, 201)
	path := "/api/v1/notes/" + decode(t, res)["id"].(string)
	statuses := make(chan int, 2)
	var group sync.WaitGroup
	for n := 0; n < 2; n++ {
		group.Add(1)
		go func(n int) {
			defer group.Done()
			response := request(t, handler, "PUT", path, fmt.Sprintf(`{"title":"版本%d","body":"","revision":1}`, n), testToken)
			statuses <- response.Code
		}(n)
	}
	group.Wait()
	close(statuses)
	counts := map[int]int{}
	for status := range statuses {
		counts[status]++
	}
	if counts[200] != 1 || counts[409] != 1 {
		t.Fatalf("only one concurrent writer may win: %v", counts)
	}
}
