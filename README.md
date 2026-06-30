# AeroDrive ☁️

**Zero-knowledge encrypted cloud storage powered entirely by Telegram.**

AeroDrive transforms Telegram channels into an encrypted, infinitely scalable cloud drive. Files are chunked, encrypted with AES-256-GCM client-side, and stored across your Telegram channels. Only you hold the keys.

---

## Features

- **Zero-Knowledge Encryption**: Files are chunked and encrypted with AES-256-GCM (static files) or AES-256-CTR (streaming media) before leaving your device.
- **Infinite Storage for $0**: Leverages Telegram's unlimited file storage. Files are chunked transparently across multiple channels.
- **Fast Local Indexing**: Drift (SQLite) database with full-text search indexes all files and folders locally.
- **Optional WebDAV Backend**: Mount AeroDrive as a network drive using the bundled Go companion backend.
- **Share Links**: Password-protected, expiring share links with burn-after-reading support.
- **Local AI Face Clustering**: On-device face detection and clustering for privacy-first photo organization.
- **Android + Windows**: Cross-platform Flutter app with responsive layout.
- **Zero-DB Recovery**: Manifest messages in a dedicated channel allow full recovery if the local database is lost.

---

## Architecture

1. **Frontend**: Flutter (Riverpod, go_router, Drift)
2. **Telegram Transport**: TDLib via FFI (`tdjson.dll` / `libtdjson.so`)
3. **Local DB**: SQLite (Drift, schema v5 with FTS5 support)
4. **Backend (optional)**: Go/chi server for WebDAV and share-link relay

---

## Getting Started

### Android

Download `app-release.apk` from [Releases](https://github.com/anomalyco/AeroDrive/releases). Background uploads use WorkManager.

### Windows

Download `AeroDrive_Windows_Portable.zip`. Extract and run `AeroDrive.exe`. Requires `tdjson.dll` in the same directory.

### WebDAV Backend

```bash
cd backend
go build -o aerodrive-server ./cmd/server
./aerodrive-server --port 8090 --db-path ./data
```

Expose via Cloudflare Tunnel for remote access.

---

## Building from Source

**Prerequisites:**
- Flutter SDK 3.22+
- Android Studio / Android SDK
- Go 1.22+
- TDLib native libraries (see `scripts/build_tdlib.sh`)

**Commands:**
- Android: `cd app && flutter build apk`
- Windows: `cd app && flutter build windows`
- Backend: `cd backend && go build -o aerodrive-server ./cmd/server`
- Codegen: `scripts/run_codegen.ps1`

---

## Security

See [docs/SECURITY.md](docs/SECURITY.md) for the full threat model.

- AES-256-GCM (files) / AES-256-CTR (streaming)
- Argon2id key derivation
- Unique 96-bit nonce per file
- Key hierarchy via HKDF from Master Key
- Zero-knowledge: Telegram sees only ciphertext
- No telemetry, no analytics, no crash reporting

---

## License

AGPL-3.0. See [LICENSE](LICENSE).
