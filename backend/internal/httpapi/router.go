package httpapi

import (
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/aerodrive/backend/internal/config"
	"github.com/aerodrive/backend/internal/linkstore"
	"github.com/go-chi/chi/v5"
	"golang.org/x/crypto/bcrypt"
)

type Router struct {
	cfg   *config.Config
	store *linkstore.Store
}

func NewRouter(cfg *config.Config, store *linkstore.Store) *Router {
	return &Router{
		cfg:   cfg,
		store: store,
	}
}

func (api *Router) Mount(r chi.Router) {
	// Public routes
	r.Get("/s/{token}", api.handleDownload)

	// Admin protected routes
	r.Group(func(r chi.Router) {
		r.Use(api.adminAuthMiddleware)
		r.Post("/api/shares/create", api.handleCreateShare)
	})
}

func (api *Router) adminAuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		token := strings.TrimPrefix(authHeader, "Bearer ")
		if token != api.cfg.AdminAPIKey {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		next.ServeHTTP(w, r)
	})
}

type CreateShareRequest struct {
	Token        string `json:"token"`
	FileID       string `json:"file_id"`
	DEK          string `json:"dek"`
	PasswordHash string `json:"password_hash"`
	ExpiresAt    int64  `json:"expires_at"`
	MaxDownloads int    `json:"max_downloads"`
}

func (api *Router) handleCreateShare(w http.ResponseWriter, r *http.Request) {
	var req CreateShareRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	if req.Token == "" || req.FileID == "" || req.DEK == "" {
		http.Error(w, "missing required fields", http.StatusBadRequest)
		return
	}

	link := linkstore.ShareLink{
		Token:        req.Token,
		FileID:       req.FileID,
		DEK:          req.DEK,
		PasswordHash: req.PasswordHash,
		ExpiresAt:    req.ExpiresAt,
		MaxDownloads: req.MaxDownloads,
	}

	if err := api.store.CreateLink(link); err != nil {
		http.Error(w, "failed to create link", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	w.Write([]byte(`{"status":"success"}`))
}

func (api *Router) handleDownload(w http.ResponseWriter, r *http.Request) {
	token := chi.URLParam(r, "token")
	link, err := api.store.GetLink(token)
	if err != nil {
		http.Error(w, "server error", http.StatusInternalServerError)
		return
	}

	if link == nil {
		http.Error(w, "link not found or deleted", http.StatusNotFound)
		return
	}

	// 1. Check Expiry
	if link.ExpiresAt > 0 && time.Now().Unix() > link.ExpiresAt {
		api.store.DeleteLink(token)
		http.Error(w, "link expired", http.StatusGone)
		return
	}

	// 2. Check Download Limits
	if link.MaxDownloads > 0 && link.DownloadCount >= link.MaxDownloads {
		api.store.DeleteLink(token)
		http.Error(w, "download limit reached", http.StatusGone)
		return
	}

	// 3. Check Password
	if link.PasswordHash != "" {
		pwd := r.URL.Query().Get("pwd")
		if pwd == "" {
			http.Error(w, "password required in ?pwd=", http.StatusUnauthorized)
			return
		}

		if err := bcrypt.CompareHashAndPassword([]byte(link.PasswordHash), []byte(pwd)); err != nil {
			http.Error(w, "invalid password", http.StatusForbidden)
			return
		}
	}

	// Increment download count
	api.store.IncrementDownloadCount(token)

	// If it reached its limit just now, delete it (burn-after-reading)
	if link.MaxDownloads > 0 && link.DownloadCount+1 >= link.MaxDownloads {
		api.store.DeleteLink(token)
	}

	// --- STREAMING LOGIC WILL GO HERE (Calling internal/telegram) ---
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Write([]byte("Pretend this is decrypted file streaming via gotd/td MTProto!"))
}
