// [INPUT]: database/sql、纯 Go SQLite 驱动与修订号写入请求。
// [OUTPUT]: 提供 OpenStore、Store 与原子 CRUD 操作。
// [POS]: 持久化边界；以条件 SQL 防止不同客户端覆盖同一修订。
// [PROTOCOL]: Update this header on change, then check AGENTS.md
package tasknotes

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

type Store struct{ db *sql.DB }

func OpenStore(path string) (*Store, error) {
	if path != ":memory:" {
		if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
			return nil, err
		}
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	// 单连接固定 PRAGMA 的作用域；条件 SQL 仍对其他服务进程生效。
	db.SetMaxOpenConns(1)
	for _, statement := range []string{
		"PRAGMA busy_timeout=5000", "PRAGMA journal_mode=WAL",
		`CREATE TABLE IF NOT EXISTS records (
   id TEXT PRIMARY KEY, kind TEXT NOT NULL CHECK(kind IN ('tasks','notes')),
   title TEXT NOT NULL, body TEXT NOT NULL DEFAULT '', completed INTEGER NOT NULL DEFAULT 0,
   revision INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
  )`,
		"CREATE INDEX IF NOT EXISTS records_listing ON records(kind,updated_at DESC,id)",
	} {
		if _, err = db.Exec(statement); err != nil {
			_ = db.Close()
			return nil, err
		}
	}
	return &Store{db: db}, nil
}

func (s *Store) Close() error { return s.db.Close() }

const columns = "id,title,body,completed,revision,created_at,updated_at"

type scanner interface{ Scan(...any) error }

func scanRecord(row scanner) (Record, error) {
	var r Record
	err := row.Scan(&r.ID, &r.Title, &r.Body, &r.Completed, &r.Revision, &r.CreatedAt, &r.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return r, ErrNotFound
	}
	return r, err
}

func (s *Store) List(ctx context.Context, kind string) ([]Record, error) {
	rows, err := s.db.QueryContext(ctx, "SELECT "+columns+" FROM records WHERE kind=? ORDER BY updated_at DESC,id ASC", kind)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := make([]Record, 0)
	for rows.Next() {
		item, err := scanRecord(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) Get(ctx context.Context, kind, id string) (Record, error) {
	return scanRecord(s.db.QueryRowContext(ctx, "SELECT "+columns+" FROM records WHERE kind=? AND id=?", kind, id))
}

func (s *Store) Create(ctx context.Context, kind string, input writeRequest) (Record, error) {
	id, err := newID()
	if err != nil {
		return Record{}, err
	}
	stamp := timestamp()
	item := Record{ID: id, Title: *input.Title, Revision: 1, CreatedAt: stamp, UpdatedAt: stamp}
	if input.Body != nil {
		item.Body = *input.Body
	}
	if input.Completed != nil {
		item.Completed = *input.Completed
	}
	_, err = s.db.ExecContext(ctx, "INSERT INTO records (id,kind,title,body,completed,revision,created_at,updated_at) VALUES (?,?,?,?,?,1,?,?)", item.ID, kind, item.Title, item.Body, item.Completed, stamp, stamp)
	return item, err
}

func (s *Store) Update(ctx context.Context, kind, id string, input writeRequest) (Record, error) {
	body := ""
	completed := false
	if input.Body != nil {
		body = *input.Body
	}
	if input.Completed != nil {
		completed = *input.Completed
	}
	// RETURNING 在同一条语句中读取实际写入版本，避免第二次写入抢先改变响应。
	row := s.db.QueryRowContext(ctx, "UPDATE records SET title=?,body=?,completed=?,revision=revision+1,updated_at=? WHERE kind=? AND id=? AND revision=? RETURNING "+columns, *input.Title, body, completed, timestamp(), kind, id, *input.Revision)
	item, err := scanRecord(row)
	if errors.Is(err, ErrNotFound) {
		err = s.missingWrite(ctx, kind, id)
	}
	return item, err
}

func (s *Store) Delete(ctx context.Context, kind, id string, revision int64) error {
	result, err := s.db.ExecContext(ctx, "DELETE FROM records WHERE kind=? AND id=? AND revision=?", kind, id, revision)
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return s.missingWrite(ctx, kind, id)
	}
	return nil
}

func (s *Store) missingWrite(ctx context.Context, kind, id string) error {
	_, err := s.Get(ctx, kind, id)
	if err != nil {
		return err
	}
	return ErrConflict
}

func timestamp() string { return time.Now().UTC().Format("2006-01-02T15:04:05.000000000Z") }
func newID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	raw := hex.EncodeToString(b[:])
	return fmt.Sprintf("%s-%s-%s-%s-%s", raw[:8], raw[8:12], raw[12:16], raw[16:20], raw[20:]), nil
}
