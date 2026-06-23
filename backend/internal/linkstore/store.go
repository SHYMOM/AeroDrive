package linkstore

import (
	"database/sql"
	"fmt"
	"log"

	_ "github.com/mattn/go-sqlite3"
)

type ShareLink struct {
	Token           string
	FileID          string
	DEK             string // Base64 encoded
	PasswordHash    string // bcrypt hash, empty if no password
	ExpiresAt       int64  // Unix timestamp, 0 if no expiry
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
	
	_, err := s.db.Exec(query)
	if err != nil {
		return fmt.Errorf("failed to migrate links db: %w", err)
	}
	log.Println("LinkStore database initialized.")
	return nil
}

func (s *Store) CreateLink(link ShareLink) error {
	query := `
	INSERT INTO share_links (token, file_id, dek, password_hash, expires_at, max_downloads, download_count)
	VALUES (?, ?, ?, ?, ?, ?, ?)`
	
	_, err := s.db.Exec(query, link.Token, link.FileID, link.DEK, link.PasswordHash, link.ExpiresAt, link.MaxDownloads, link.DownloadCount)
	return err
}

func (s *Store) GetLink(token string) (*ShareLink, error) {
	query := `SELECT token, file_id, dek, password_hash, expires_at, max_downloads, download_count FROM share_links WHERE token = ?`
	row := s.db.QueryRow(query, token)

	var l ShareLink
	var pwdHash sql.NullString
	err := row.Scan(&l.Token, &l.FileID, &l.DEK, &pwdHash, &l.ExpiresAt, &l.MaxDownloads, &l.DownloadCount)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, nil // Not found
		}
		return nil, err
	}
	l.PasswordHash = pwdHash.String
	return &l, nil
}

func (s *Store) IncrementDownloadCount(token string) error {
	_, err := s.db.Exec(`UPDATE share_links SET download_count = download_count + 1 WHERE token = ?`, token)
	return err
}

func (s *Store) DeleteLink(token string) error {
	_, err := s.db.Exec(`DELETE FROM share_links WHERE token = ?`, token)
	return err
}

func (s *Store) Close() error {
	return s.db.Close()
}
