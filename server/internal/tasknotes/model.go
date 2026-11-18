// [INPUT]: HTTP JSON 字段与 SQLite 持久化记录。
// [OUTPUT]: 提供请求、记录与统一业务错误。
// [POS]: HTTP 与存储的内部边界；公开字段遵循 contracts/API.md。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
package tasknotes

import "errors"

var (
	ErrNotFound = errors.New("record not found")
	ErrConflict = errors.New("revision conflict")
)

type Record struct {
	ID        string
	Title     string
	Body      string
	Completed bool
	Revision  int64
	CreatedAt string
	UpdatedAt string
}

type writeRequest struct {
	Title     *string `json:"title"`
	Body      *string `json:"body,omitempty"`
	Completed *bool   `json:"completed,omitempty"`
	Revision  *int64  `json:"revision,omitempty"`
}

func (r Record) public(kind string) map[string]any {
	result := map[string]any{"id": r.ID, "title": r.Title, "revision": r.Revision, "created_at": r.CreatedAt, "updated_at": r.UpdatedAt}
	if kind == "tasks" {
		result["completed"] = r.Completed
	} else {
		result["body"] = r.Body
	}
	return result
}
