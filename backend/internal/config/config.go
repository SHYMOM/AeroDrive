package config

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"path/filepath"
)

type Config struct {
	AdminAPIKey string `json:"admin_api_key"`
}

const configFileName = "config.json"

// LoadOrGenerate loads the configuration. If it doesn't exist, it generates a new API key.
func LoadOrGenerate() (*Config, error) {
	file, err := os.Open(configFileName)
	if err != nil {
		if os.IsNotExist(err) {
			return generateNewConfig()
		}
		return nil, err
	}
	defer file.Close()

	var cfg Config
	if err := json.NewDecoder(file).Decode(&cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config.json: %w", err)
	}

	return &cfg, nil
}

func generateNewConfig() (*Config, error) {
	apiKey := generateRandomString(64)
	cfg := &Config{
		AdminAPIKey: apiKey,
	}

	data, err := json.MarshalIndent(cfg, "", "  ")
	if err != nil {
		return nil, err
	}

	if err := os.WriteFile(configFileName, data, 0600); err != nil {
		return nil, err
	}

	absPath, _ := filepath.Abs(configFileName)
	log.Println("================================================================")
	log.Println("INITIAL SETUP DETECTED")
	log.Println("A new Admin API Key has been generated and saved to:")
	log.Println(absPath)
	log.Println("API KEY:", apiKey)
	log.Println("Copy this key into the AeroDrive Flutter App Settings.")
	log.Println("================================================================")

	return cfg, nil
}

func generateRandomString(n int) string {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	bytes := make([]byte, n)
	if _, err := rand.Read(bytes); err != nil {
		panic(err)
	}
	for i, b := range bytes {
		bytes[i] = letters[b%byte(len(letters))]
	}
	return string(bytes)
}
