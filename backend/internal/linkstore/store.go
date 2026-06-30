package linkstore

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

type ShareLink struct {
	Token           string
	FileID          string
	DEK             string
	PasswordHash    string
	ExpiresAt       int64
	MaxDownloads    int
	DownloadCount   int
}

type Store struct {
	db *sql.DB
}

func NewStore(dbPath string) (*Store, error) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, err
	}

	store := &Store{db: db}
	if err := store.migrate(); err != nil {
		return nil, err
	}

	return store, nil
}

func (s *Store) migrate() error {
	if _, err := s.db.Exec("PRAGMA journal_mode=WAL"); err != nil {
		return fmt.Errorf("failed to enable WAL mode: %w", err)
	}

	query := `
	CREATE TABLE IF NOT EXISTS share_links (
		token TEXT PRIMARY KEY,
		file_id TEXT NOT NULL,
		dek TEXT NOT NULL,
		password_hash TEXT,
		expires_at INTEGER DEFAULT 0,
		max_downloads INTEGER DEFAULT 0,
		download_count INTEGER DEFAULT 0
	);`

	if _, err := s.db.Exec(query); err != nil {
		return fmt.Errorf("failed to migrate links db: %w", err)
	}
	log.Println("LinkStore database initialized.")
	return nil
}

func (s *Store) CreateLink(ctx context.Context, link ShareLink) error {
	query := `
	INSERT INTO share_links (token, file_id, dek, password_hash, expires_at, max_downloads, download_count)
	VALUES (?, ?, ?, ?, ?, ?, ?)`

	_, err := s.db.ExecContext(ctx, query, link.Token, link.FileID, link.DEK, link.PasswordHash, link.ExpiresAt, link.MaxDownloads, link.DownloadCount)
	if err != nil {
		if isConstraintError(err) {
			return fmt.Errorf("duplicate token: %s", link.Token)
		}
		return fmt.Errorf("failed to insert link: %w", err)
	}
	return nil
}

func (s *Store) GetLink(ctx context.Context, token string) (*ShareLink, error) {
	query := `SELECT token, file_id, dek, password_hash, expires_at, max_downloads, download_count FROM share_links WHERE token = ?`
	row := s.db.QueryRowContext(ctx, query, token)

	var l ShareLink
	var pwdHash sql.NullString
	err := row.Scan(&l.Token, &l.FileID, &l.DEK, &pwdHash, &l.ExpiresAt, &l.MaxDownloads, &l.DownloadCount)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	l.PasswordHash = pwdHash.String
	return &l, nil
}

func (s *Store) IncrementDownloadCount(ctx context.Context, token string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE share_links SET download_count = download_count + 1 WHERE token = ?`, token)
	return err
}

func (s *Store) IncrementAndCheckLimit(ctx context.Context, token string, maxDownloads int) (bool, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return false, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	var currentCount int
	err = tx.QueryRowContext(ctx, `SELECT download_count FROM share_links WHERE token = ?`, token).Scan(&currentCount)
	if err != nil {
		return false, err
	}

	if maxDownloads > 0 && currentCount >= maxDownloads {
		_, err = tx.ExecContext(ctx, `DELETE FROM share_links WHERE token = ?`, token)
		if err != nil {
			return false, err
		}
		if err := tx.Commit(); err != nil {
			return false, err
		}
		return false, nil
	}

	_, err = tx.ExecContext(ctx, `UPDATE share_links SET download_count = download_count + 1 WHERE token = ?`, token)
	if err != nil {
		return false, err
	}

	shouldDelete := maxDownloads > 0 && currentCount+1 >= maxDownloads
	if shouldDelete {
		_, err = tx.ExecContext(ctx, `DELETE FROM share_links WHERE token = ?`, token)
		if err != nil {
			return false, err
		}
	}

	if err := tx.Commit(); err != nil {
		return false, err
	}

	return true, nil
}

func (s *Store) DeleteLink(ctx context.Context, token string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM share_links WHERE token = ?`, token)
	return err
}

func (s *Store) Close() error {
	if err := s.db.Close(); err != nil {
		return fmt.Errorf("failed to close store: %w", err)
	}
	return nil
}

func isConstraintError(err error) bool {
	return err != nil && (strings.Contains(err.Error(), "UNIQUE") || strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "Duplicate"))
}
