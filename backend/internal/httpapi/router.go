package httpapi

import (
	"crypto/subtle"
	"encoding/json"
	"log"
	"net/http"
	"strings"
	"sync"
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
	r.Use(api.corsMiddleware)
	r.Use(api.rateLimitMiddleware)

	r.Get("/s/{token}", api.handleDownload)

	r.Group(func(r chi.Router) {
		r.Use(api.adminAuthMiddleware)
		r.Post("/api/shares/create", api.handleCreateShare)
	})
}

func (api *Router) corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, X-Download-Password, Content-Type")
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type rateLimiter struct {
	mu       sync.Mutex
	requests map[string]int
}

var limiter = &rateLimiter{
	requests: make(map[string]int),
}

func (api *Router) rateLimitMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := r.RemoteAddr
		limiter.mu.Lock()
		limiter.requests[ip]++
		count := limiter.requests[ip]
		limiter.mu.Unlock()

		if count > 60 {
			http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
			return
		}

		next.ServeHTTP(w, r)

		time.AfterFunc(time.Minute, func() {
			limiter.mu.Lock()
			limiter.requests[ip]--
			if limiter.requests[ip] <= 0 {
				delete(limiter.requests, ip)
			}
			limiter.mu.Unlock()
		})
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
		if subtle.ConstantTimeCompare([]byte(token), []byte(api.cfg.AdminAPIKey)) != 1 {
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
	if r.Header.Get("Content-Type") != "application/json" {
		http.Error(w, "Content-Type must be application/json", http.StatusUnsupportedMediaType)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)

	var req CreateShareRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		log.Printf("failed to decode create share request: %v", err)
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.Token == "" || req.FileID == "" || req.DEK == "" {
		http.Error(w, "missing required fields", http.StatusBadRequest)
		return
	}

	if len(req.Token) > 256 || len(req.FileID) > 256 || len(req.DEK) > 4096 {
		http.Error(w, "field too long", http.StatusBadRequest)
		return
	}

	if req.MaxDownloads < 0 {
		http.Error(w, "max_downloads must be non-negative", http.StatusBadRequest)
		return
	}

	if req.ExpiresAt < 0 {
		http.Error(w, "expires_at must be non-negative", http.StatusBadRequest)
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

	if err := api.store.CreateLink(r.Context(), link); err != nil {
		if strings.Contains(err.Error(), "duplicate token") {
			http.Error(w, "token already exists", http.StatusConflict)
			return
		}
		log.Printf("failed to create link: %v", err)
		http.Error(w, "server error", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	w.Write([]byte(`{"status":"success"}`))
}

func (api *Router) handleDownload(w http.ResponseWriter, r *http.Request) {
	token := chi.URLParam(r, "token")
	link, err := api.store.GetLink(r.Context(), token)
	if err != nil {
		log.Printf("failed to get link %s: %v", token, err)
		http.Error(w, "server error", http.StatusInternalServerError)
		return
	}

	if link == nil {
		http.Error(w, "link not found or deleted", http.StatusNotFound)
		return
	}

	if link.ExpiresAt > 0 && time.Now().Unix() > link.ExpiresAt {
		api.store.DeleteLink(r.Context(), token)
		http.Error(w, "link expired", http.StatusGone)
		return
	}

	if link.PasswordHash != "" {
		pwd := r.Header.Get("X-Download-Password")
		if pwd == "" {
			w.Header().Set("WWW-Authenticate", `X-Download-Password realm="AeroDrive Share"`)
			http.Error(w, "password required in X-Download-Password header", http.StatusUnauthorized)
			return
		}

		if err := bcrypt.CompareHashAndPassword([]byte(link.PasswordHash), []byte(pwd)); err != nil {
			http.Error(w, "invalid password", http.StatusUnauthorized)
			return
		}
	}

	allowed, err := api.store.IncrementAndCheckLimit(r.Context(), token, link.MaxDownloads)
	if err != nil {
		log.Printf("failed to increment download count: %v", err)
		http.Error(w, "server error", http.StatusInternalServerError)
		return
	}

	if !allowed {
		http.Error(w, "download limit reached", http.StatusGone)
		return
	}

	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("X-Share-File-Id", link.FileID)
	w.Header().Set("X-Share-DEK", link.DEK)
	w.Write([]byte("Streaming will be implemented when internal/telegram package is complete"))
}
