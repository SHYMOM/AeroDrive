package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aerodrive/backend/internal/config"
	"github.com/aerodrive/backend/internal/httpapi"
	"github.com/aerodrive/backend/internal/linkstore"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func main() {
	log.Println("AeroDrive Backend Starting...")

	cfg, err := config.LoadOrGenerate()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	store, err := linkstore.NewStore("links.db")
	if err != nil {
		log.Fatalf("Failed to init db: %v", err)
	}
	defer func() {
		if err := store.Close(); err != nil {
			log.Printf("Error closing store: %v", err)
		}
	}()

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if _, err := store.GetLink(r.Context(), "__health_check__"); err != nil {
			w.WriteHeader(http.StatusServiceUnavailable)
			w.Write([]byte(`{"status":"unhealthy","error":"database unreachable"}`))
			return
		}
		w.Write([]byte(`{"status":"ok"}`))
	})

	apiRouter := httpapi.NewRouter(cfg, store)
	apiRouter.Mount(r)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	srv := &http.Server{
		Addr:    ":" + port,
		Handler: r,
	}

	go func() {
		log.Printf("Server starting on port %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited gracefully")
}
