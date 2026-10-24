<div align="center">

# AeroDrive ☁️

**Zero-Knowledge Encrypted Cloud Storage Powered Entirely by Telegram**

[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Telegram TDLib](https://img.shields.io/badge/TDLib-1.8.x-24A1DE?logo=telegram&logoColor=white)](https://core.telegram.org/tdlib)
[![Go WebDAV](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go&logoColor=white)](https://golang.org)
[![Security: AES--256--GCM](https://img.shields.io/badge/Security-AES--256--GCM%20%2B%20Argon2id-critical.svg)](#-cryptography--security-model)
[![Platform](https://img.shields.io/badge/Platforms-Android%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)](#-getting-started)

*Turn unlimited Telegram channels into a private, high-performance, self-hosted cloud drive. Your files are client-side encrypted before leaving your device — only you hold the keys.*

[Features](#-key-features) • [Architecture](#-architecture) • [Security Model](#-cryptography--security-model) • [Installation](#-getting-started) • [Building](#-building-from-source) • [Docs](docs/ARCHITECTURE.md)

---

</div>

## 📖 Overview

**AeroDrive** transforms Telegram channels into an infinitely scalable, distributed object storage system wrapped in a native cross-platform application (Android, Windows, Linux). 

Unlike commercial cloud providers that scan user data, train AI on private photos, or enforce monthly storage fees, AeroDrive operates under a strict **Zero-Knowledge** architecture:
1. **Client-Side Chunking & Encryption**: Every file is sliced into configurable chunks and encrypted using hardware-accelerated **AES-256-GCM** (or seekable **AES-256-CTR** for streaming media).
2. **Channel Striping & Infinite Bandwidth**: Chunks are striped across multiple Telegram channels to bypass single-channel bottlenecks and rate limits.
3. **Decentralized Local Index**: Fast local search and folder hierarchies are driven by an on-device SQLite (Drift) database with FTS5.
4. **Zero-DB Disaster Recovery**: Even if you lose your phone or drop your database, an encrypted manifest stream in your recovery channel allows complete reconstruction of your file tree.

---

## ✨ Key Features

### 🛡️ Zero-Knowledge Security & Privacy
- **End-to-End Client Encryption**: Raw data never leaves your device unencrypted. Telegram only ever receives high-entropy ciphertext blobs.
- **Argon2id Key Derivation**: Master Key (MK) derived from your passphrase using memory-hard Argon2id to resist GPU/ASIC attacks.
- **Unique 96-Bit Nonce Per File**: Keys are derived per-file via HKDF-HMAC-SHA256, preventing cryptographic reuse.
- **Biometric & App Lock**: Protect the app with fingerprint, face unlock (`local_auth`), or numeric PIN. Includes configurable auto-lock timers and an OS-level Privacy Shield that blurs previews in multitasking switchers.
- **Zero Telemetry**: No third-party trackers, analytics, or crash reporters.

### ⚡ Infinite Storage & Resilient Transfers
- **Infinite $0 Storage**: Leverages Telegram’s unlimited cloud capacity.
- **Multi-Channel Striping**: Distribute chunks across 2 to 5+ channels concurrently to optimize upload/download throughput and prevent Telegram flood-wait pauses.
- **Persistent Transfer Queue**: Resilient upload queue with chunk-level progress, automatic retries with exponential backoff, and pause/resume capability.
- **Content-Addressable Deduplication (CAS)**: SHA-256 hash checking prevents redundant uploads across folders.
- **Offline Pinned Files**: Pin critical documents or media for guaranteed offline availability; pinned items are protected from cache cleanup algorithms.

### 🧠 On-Device AI & Media Intelligence
- **Local Face Clustering**: On-device face detection and agglomerative clustering with cosine distance metrics. Organize photos by person with custom names and avatars without sending facial vectors to external cloud APIs.
- **Interactive Places & Offline Geocoding**: High-speed reverse-geocoding using an embedded global city index (`cities.json`). Browse media grouped by cities, countries, and geographic hotspots.
- **Memories & Story Carousel**: Relive past memories with Google Photos-style story carousels ("On this day", "Recent Adventures", and milestone albums).

### 📑 Productivity & Power Tools
- **Built-in Document Scanner**: Multi-page document camera capture, perspective adjustment, and document filters (B&W High-Contrast, Grayscale, Color Enhanced). Export multi-page scans directly to searchable PDFs in your drive.
- **Storage Health & Duplicate Cleaner**: Instant analysis of disk space, identification of large files (>50MB, >100MB), content duplicate detection, and one-tap cache trimmer.
- **Google Takeout Importer**: Direct ZIP archive importer for Google Photos and Google Drive backups. Automatically parses embedded JSON metadata (timestamps, EXIF, geo-coordinates) and recreates original folder trees.

### 🎬 Universal In-App Previews
- **Instant Media Streaming**: Powered by MediaKit (libmpv) for instant seeking and hardware-decoded streaming of encrypted video and audio files.
- **Document & Code Viewer**: High-performance vector PDF rendering (`pdfx`), syntax-highlighted code viewer, Markdown reader, and ZIP/TAR archive inspection without full extraction.

### 🌐 WebDAV & Cross-Platform Ecosystem
- **Go Companion Server**: Lightweight backend allowing you to mount AeroDrive as a standard network drive (WebDAV) on Windows Explorer, macOS Finder, or Linux Nautilus.
- **Secure Share Links**: Generate password-protected, expiring share links with optional "burn-after-reading" (self-destruct after first download).

---

## 🏛️ Architecture

AeroDrive separates UI state, local persistence, encryption primitives, and Telegram network transport into clean, isolated layers:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        Flutter Client Application                      │
│                                                                        │
│   ┌─────────────────────┐   ┌──────────────────┐   ┌───────────────┐   │
│   │   Riverpod State    │   │  GoRouter Nav    │   │ Material 3 UI │   │
│   └──────────┬──────────┘   └────────┬─────────┘   └───────┬───────┘   │
│              │                       │                     │           │
│   ┌──────────▼───────────────────────▼─────────────────────▼───────┐   │
│   │                    Domain Services Layer                       │   │
│   │  • UploadQueueService    • FaceClusteringEngine   • Cleaner    │   │
│   │  • TakeoutImporter       • DocumentScannerService • OfflinePin │   │
│   └──────────┬─────────────────────────────────────────────────────┘   │
│              │                                                         │
│   ┌──────────▼──────────────┐                ┌─────────────────────┐   │
│   │  Drift SQLite Database  │                │ Cryptography Engine │   │
│   │  Schema v5 + FTS5 Search│                │ AES-256-GCM / CTR   │   │
│   └──────────┬──────────────┘                └──────────┬──────────┘   │
│              │                                          │              │
│   ┌──────────▼──────────────────────────────────────────▼──────────┐   │
│   │                   TDLib FFI Native Bridge                      │   │
│   │        tdjson.dll (Windows) / libtdjson.so (Android/Linux)     │   │
│   └──────────────────────────────────┬─────────────────────────────┘   │
└──────────────────────────────────────┼─────────────────────────────────┘
                                       │
                                       ▼ (TLS 1.3 / MTProto)
              ┌────────────────────────────────────────────────┐
              │           Telegram Cloud Infrastructure        │
              │  • Storage Channels (Encrypted Blobs)          │
              │  • Manifest Channel (Zero-DB Recovery Feed)    │
              └────────────────────────────────────────────────┘
                                       ▲
                                       │ (Localhost / Tunnel)
┌──────────────────────────────────────┴─────────────────────────────────┐
│                    Go WebDAV Companion Server (Optional)               │
│   • chi HTTP Engine      • WebDAV Filesystem Driver    • Share Proxy   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 Cryptography & Security Model

AeroDrive treats Telegram purely as an untrusted, high-capacity blob store. All cryptographic boundaries exist on the local device.

| Security Layer | Algorithm / Standard | Implementation & Purpose |
|---|---|---|
| **Master Key Derivation** | **Argon2id** | Passphrase + Salt → 256-bit Master Key. Resists GPU dictionary attacks. |
| **Static File Encryption** | **AES-256-GCM** | Authenticated encryption with 128-bit auth tags (tamper detection). |
| **Streaming Media** | **AES-256-CTR** | Seekable segment-based streaming with HMAC-SHA256 integrity verification. |
| **Subkey Derivation** | **HKDF-HMAC-SHA256** | Derives distinct ephemeral keys per file, channel, and manifest. |
| **Deduplication Hashing** | **SHA-256** | Generates content-addressable digests for duplicate prevention. |
| **Secrets Storage** | **Android Keystore / DPAPI** | Hardware-backed secure storage via `flutter_secure_storage`. |

### Zero-DB Disaster Recovery
In the event of device loss or database corruption, you do not lose your files:
- AeroDrive publishes an encrypted **manifest event** to a private Telegram channel whenever a file is uploaded, renamed, or moved.
- Entering your Master Passphrase on a new device triggers **Manifest Rescan**, which rebuilds your entire SQLite index and folder hierarchy directly from Telegram.

---

## 🚀 Getting Started

### 📱 Android
1. Download the latest `app-release.apk` from the [Releases](https://github.com/SHYMOM/AeroDrive/releases) page.
2. Install the APK on your Android device (Android 8.0+ recommended).
3. Log in with your Telegram account (using your phone number and 2FA password).
4. Configure your Master Passphrase to initialize your encrypted drive.

### 💻 Windows
1. Download `AeroDrive_Windows_Portable.zip` from [Releases](https://github.com/SHYMOM/AeroDrive/releases).
2. Extract the archive into a folder of your choice.
3. Ensure `tdjson.dll` is present in the same directory as `aerodrive.exe`.
4. Launch `aerodrive.exe`.

### 🌐 Optional Go WebDAV Companion Server
Mount AeroDrive directly in Windows Explorer or macOS Finder:
```bash
cd backend
go build -o aerodrive-server ./cmd/server
./aerodrive-server --port 8090 --db-path ./data
```
*Tip: Pair with a Cloudflare Tunnel or Tailscale to securely access your WebDAV mount remotely.*

---

## 🛠️ Building from Source

### Prerequisites
- **Flutter SDK**: `3.22.0` or later
- **Android SDK**: Build tools 34.0.0+, NDK 25+
- **Visual Studio 2022**: C++ desktop development workload (for Windows desktop builds)
- **Go**: `1.22+` (for WebDAV companion)
- **TDLib**: Native shared libraries (`tdjson.dll` for Windows, `libtdjson.so` for Android)

### 1. Clone the Repository
```bash
git clone https://github.com/SHYMOM/AeroDrive.git
cd AeroDrive
```

### 2. Configure Environment
Copy and populate `.env` in the `app/` directory:
```env
TELEGRAM_API_ID=your_telegram_api_id
TELEGRAM_API_HASH=your_telegram_api_hash
```
*(Obtain your API credentials at [my.telegram.org](https://my.telegram.org))*

### 3. Generate Dart Code
Run code generation for Drift and Riverpod:
```bash
cd app
dart run build_runner build --delete-conflicting-outputs
```

### 4. Build Applications

#### Android APK:
```bash
cd app
flutter build apk --release
# Output: app/build/app/outputs/flutter-apk/app-release.apk
```

#### Windows Desktop:
```bash
cd app
flutter build windows --release
# Output: app/build/windows/x64/runner/Release/aerodrive.exe
```

#### Run Automated Tests:
```bash
cd app
flutter test
```

---

## 📂 Project Structure

```
AeroDrive/
├── app/                        # Flutter client application
│   ├── android/                # Android native project & JNI libs
│   ├── windows/                # Windows native runner & CMake
│   ├── assets/                 # Embedded city database & assets
│   ├── lib/
│   │   ├── core/               # Routing, themes, crypto primitives, Drift DB
│   │   ├── domain/             # Background upload queue, AI clustering, scanner, importer
│   │   └── features/           # Drive browser, Media, Scanner, Cleaner, Security, Settings
│   └── test/                   # Unit and integration test suites
├── backend/                    # Go WebDAV companion & share proxy
│   ├── cmd/server/             # WebDAV binary entrypoint
│   └── internal/webdav/        # WebDAV protocol handlers
├── docs/                       # Architecture, Security, API specifications
└── scripts/                    # Native build helpers and codegen automation
```

---

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. See the [LICENSE](LICENSE) file for details.

---

<div align="center">
  <sub>Built with ❤️ by the AeroDrive community. Dedicated to zero-knowledge privacy and open access.</sub>
</div>
