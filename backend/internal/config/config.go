package config

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"log"
	"math/big"
	"os"
	"path/filepath"
)

type Config struct {
	AdminAPIKey string `json:"admin_api_key"`
}

const configFileName = "config.json"

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
	apiKey, err := generateRandomString(64)
	if err != nil {
		return nil, fmt.Errorf("failed to generate API key: %w", err)
	}
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
	log.Printf("API Key (last 4 chars): ...%s", safeLastN(apiKey, 4))
	log.Println("Copy this key into the AeroDrive Flutter App Settings.")
	log.Println("================================================================")

	return cfg, nil
}

func safeLastN(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[len(s)-n:]
}

func generateRandomString(n int) (string, error) {
	const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	result := make([]byte, n)
	for i := range result {
		idx, err := rand.Int(rand.Reader, big.NewInt(int64(len(letters))))
		if err != nil {
			return "", fmt.Errorf("failed to generate random index: %w", err)
		}
		result[i] = letters[idx.Int64()]
	}
	return string(result), nil
}
