#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "   AeroDrive - Go Backend Build Script"
echo "=========================================="

BACKEND_DIR="$(dirname "$0")/backend"
OUTPUT_EXE="$(dirname "$0")/AeroDrive_Backend"

echo "[1/3] Checking Go installation..."
command -v go >/dev/null 2>&1 || { echo "ERROR: Go is not installed or not in PATH"; exit 1; }

echo "[2/3] Fetching dependencies..."
cd "$BACKEND_DIR"
go mod tidy

echo "[3/3] Compiling Backend..."
go build -ldflags="-w -s" -o "$OUTPUT_EXE" ./cmd/server/main.go

echo ""
echo "=========================================="
echo "   Build Successful!"
echo "   Executable: $OUTPUT_EXE"
echo "=========================================="
