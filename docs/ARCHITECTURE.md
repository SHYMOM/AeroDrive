# AeroDrive Architecture

## Overview

AeroDrive uses a **client-centric, zero-knowledge architecture**: all encryption, indexing, and Telegram transport happen on-device. The optional Go backend provides WebDAV access and share-link relay only — it never handles plaintext data or cryptographic keys.

## System Layers

```
┌─────────────────────────────────────────────────────────────┐
│                     Flutter App (Client)                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │
│  │ Drift DB │  │ Riverpod │  │ GoRouter │  │   UI/Widget │  │
│  │ (SQLite) │  │  State   │  │  Routes  │  │   Tree      │  │
│  └────┬─────┘  └──────────┘  └──────────┘  └─────────────┘  │
│       │                                                      │
│  ┌────▼──────────────────────────────────────────────────┐   │
│  │              TDLib FFI Bridge (dart:ffi)               │   │
│  │  tdjson.dll (Win) / libtdjson.so (Android/Linux)      │   │
│  └──────────────────────────┬─────────────────────────────┘   │
└─────────────────────────────┼───────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────┐
│                    Telegram Servers                          │
│  (Channels used as dumb object storage, no processing)      │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                Go Backend (Optional)                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                   │
│  │  chi     │  │ WebDAV   │  │ Transfer │                   │
│  │ Router   │  │ Handler  │  │ Proxy    │                   │
│  └──────────┘  └──────────┘  └──────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

## Data Flow: Upload

1. User selects file → UI creates pending entry in `TransferQueue`
2. File is read in-chunk (1–10 MB each, configurable)
3. Each chunk is encrypted with AES-256-GCM (static files) or AES-256-CTR (streaming media)
4. Encrypted chunks are uploaded to Telegram channels via TDLib `sendMessage`
5. Message IDs are recorded in `Chunks` table; file metadata (nonce, algo, manifest) written to `Files` table
6. A manifest message is sent to a dedicated channel for Zero-DB recovery
7. Entry removed from `TransferQueue`; file marked as synced

## Data Flow: Download

1. User opens file/folder → DB query returns chunk locations
2. Chunks fetched from Telegram via TDLib `getMessage`
3. Decrypted client-side using stored nonce + encryptionAlgo
4. Decrypted stream served to UI preview or Go WebDAV backend
5. LRU thumbnail cache accelerates subsequent previews

## Key Design Decisions

- **Drift migrations numbered v1–v5**: schema evolves with `onUpgrade` handlers; never destructive to existing data
- **TDLib via FFI, not MTProto directly**: required for multi-account support, >50 MB file handling, and auto-flood-wait compliance
- **SQLite FTS5** for full-text file/folder search (future phase)
- **Manifest messages** in dedicated channel enable full recovery if local DB is lost
- **Side-by-side compat**: old `Shares` table dropped in migration v5; replaced by `ShareLinks` with `token`, `passwordHash`, `downloadCount`, `burnAfterReading`

## Directory Structure

```
app/
├── lib/
│   ├── core/           # AppError, extensions, constants, theme
│   ├── data/
│   │   ├── db/         # Drift database, tables, migrations
│   │   ├── models/     # Domain models (not generated)
│   │   ├── services/   # TDLib wrapper, encryption, storage
│   │   └── repositories/ # Data access layer
│   ├── features/
│   │   ├── auth/       # Login, account management
│   │   ├── drive/      # Main file browser UI
│   │   ├── preview/    # Decrypted media preview
│   │   ├── share/      # Share link management
│   │   └── settings/   # App settings
│   ├── router/         # GoRouter route definitions
│   ├── widgets/        # Shared widgets (AeroDriveLogo, etc.)
│   └── app.dart        # App entry point
├── android/
├── ios/
├── test/
└── pubspec.yaml

backend/
├── cmd/server/         # Main binary entrypoint
├── internal/
│   ├── handler/        # HTTP route handlers
│   ├── middleware/     # Auth, CORS, rate-limiting
│   ├── model/          # Data structures
│   └── webdav/         # WebDAV protocol handler
├── go.mod
└── go.sum

docs/                   # Architecture, security, compliance, API docs
scripts/                # Build scripts (TDLib cross-compile, codegen)
```
