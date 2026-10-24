# AeroDrive Flutter Client

Native cross-platform front-end for **AeroDrive** — zero-knowledge encrypted cloud storage powered by Telegram.

[![Flutter](https://img.shields.io/badge/Flutter-3.22+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](../LICENSE)

---

## 📱 Supported Targets
- **Android**: Phones and tablets (Android 8.0+ / API 26+)
- **Windows**: x64 desktop executable with native `tdjson.dll` FFI integration
- **Linux**: Desktop runner with `libtdjson.so`

---

## 🏗️ Architecture & Modules

The application is structured into domain-driven features:

```
lib/
├── core/
│   ├── crypto/            # AES-256-GCM / CTR, Argon2id, HKDF, secure nonce generators
│   ├── database/          # Drift SQLite database, schema migrations, FTS5 full-text search
│   ├── di/                # Dependency injection & Riverpod service providers
│   ├── routing/           # GoRouter declarations & responsive desktop/mobile scaffolds
│   └── theme/             # Material 3 design tokens, adaptive light/dark mode
├── domain/
│   ├── ai/                # On-device face detection & agglomerative clustering
│   ├── cleaner/           # Storage duplicate detection (SHA-256) & cache management
│   ├── importer/          # Google Takeout ZIP extraction & metadata parser
│   ├── offline/           # Offline pinned files management & cache protection
│   ├── scanner/           # Document scanning, perspective filter, & multi-page PDF generation
│   ├── recovery/          # Caption-based zero-DB manifest recovery
│   └── upload_queue_service.dart # Multi-channel striping, pause/resume background uploads
└── features/
    ├── auth/              # Telegram TDLib phone & 2FA login flows
    ├── drive/             # File & folder browser, quick access, drag-and-drop
    ├── media/             # Media timeline gallery & Google Photos-style memory stories
    ├── places/            # Offline geo-reverse geocoding & photo location clustering
    ├── faces/             # Face clusters gallery & person tagging
    ├── scanner/           # Document scanner camera & PDF generator screen
    ├── cleaner/           # Storage health dashboard & duplicate cleaner UI
    ├── importer/          # Google Takeout import dialog with live progress
    ├── preview/           # MediaKit streaming player, PDF viewer, code/archive viewer
    ├── security/          # Biometric/PIN app lock & privacy switcher shield
    └── settings/          # Storage channels, backup rules, and WebDAV configuration
```

---

## 🚀 Running Locally

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run Code Generation
If you make changes to Drift tables or Riverpod annotations:
```bash
dart run build_runner build --delete-conflicting-outputs
```

### 3. Run the App

#### Windows:
```bash
flutter run -d windows
```
*(Make sure `tdjson.dll` is present in `windows/` or in the build output folder).*

#### Android:
```bash
flutter run -d android
```

---

## 🧪 Testing

Run all unit and widget tests:
```bash
flutter test
```

---

## 📖 Main Documentation
For the complete project overview, security specifications, and Go WebDAV companion documentation, please refer to the root [README.md](../README.md).
