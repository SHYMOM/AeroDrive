package main

import (
	"log"
	"net/http"
	"os"

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
	defer store.Close()

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	apiRouter := httpapi.NewRouter(cfg, store)
	apiRouter.Mount(r)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Server starting on port %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatal(err)
	}
}
