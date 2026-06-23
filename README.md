# AeroDrive ☁️🚀

**Zero-knowledge encrypted cloud storage powered entirely by Telegram.**

AeroDrive is a cross-platform client that transforms your Telegram saved messages and channels into a high-performance, infinitely scalable, and completely free cloud drive. It offers bank-grade encryption, seamless folder hierarchies, intelligent local AI face clustering, and native Windows Explorer integration via a custom WebDAV server.

---

## ✨ Features

- **Zero-Knowledge Encryption:** All files are chunked and encrypted client-side using `ChaCha20-Poly1305` before they ever leave your device. Only you hold the keys.
- **Infinite Storage for $0:** Leverages Telegram's unlimited file storage by chunking files into 2GB segments and uploading them across multiple channels.
- **Lightning Fast Navigation:** Uses a local SQLite database (powered by Drift) with Recursive CTEs to instantly render folders, breadcrumbs, and search results without waiting on network calls.
- **Native WebDAV Server:** Mount AeroDrive directly into Windows File Explorer as a network drive. The bundled Go companion backend automatically streams, decrypts, and reassembles chunks on the fly.
- **Local AI Face Clustering:** Privacy-first photo organization. AeroDrive runs localized face detection and clustering algorithms on your device, allowing you to search photos by people without sending your images to a third-party AI.
- **Share Links:** Safely share files using temporary, password-protected links. If you skip setting up your own backend, AeroDrive seamlessly falls back to a public relay method.
- **Cross-Platform:** Available as a lightweight Android APK and a Portable Windows Executable.

---

## 🏗️ Architecture

AeroDrive is built using state-of-the-art technologies across multiple layers:
1. **Frontend:** Flutter (Riverpod, Flutter Animate, GoRouter)
2. **Local State:** SQLite (Drift Database with FTS5 search capability)
3. **Telegram Core:** TDLib via FFI (`tdjson.dll` / `libtdjson.so`)
4. **Backend (Optional/Self-Hosted):** Standalone Go binary utilizing custom `net/http` WebDAV middleware.

---

## 🚀 Getting Started

### 1. Android Installation
Simply download the `app-release.apk` from the releases page and install it on your Android device. 
*Note: Background uploads and auto-sync are handled gracefully via WorkManager, ensuring your uploads finish even if you close the app.*

### 2. Windows Installation
1. Download the `AeroDrive_Windows_Portable.zip`.
2. Extract the folder anywhere on your PC.
3. Run `AeroDrive.exe`. 
*(Note: Ensure `tdjson.dll` is located in the exact same directory as the executable).*

### 3. Setting up the Zero-Cost WebDAV Backend
To mount AeroDrive as a native network drive in Windows File Explorer, you need to run the Go backend.
1. Run the `aerodrive-server` binary. It requires **zero external dependencies**.
2. **For remote access:** Expose the server for $0 using a **Cloudflare Tunnel** running on your home PC, or deploy the binary to an **Oracle Cloud Always Free Tier** ARM instance.
3. Open Windows Explorer -> Map Network Drive -> Enter your Cloudflare Tunnel URL.

---

## 🛠️ Building from Source

AeroDrive includes streamlined, one-click build scripts for all platforms.

**Prerequisites:**
- Flutter SDK (3.22+)
- Android Studio / Android SDK
- Go 1.22+ (for the backend)
- Developer Mode enabled (Windows only, for symlink support)

**Build Commands:**
- **Android:** `build_android.bat` or `./build_android.sh`
- **Windows:** `build_windows.bat`
- **Linux:** `./build_linux.sh`
- **Go Backend:** `build_backend_windows.bat` or `./build_backend_linux.sh`

---

## 📜 License

This project is licensed under the **AGPL-3.0 License**. See the [LICENSE](LICENSE) file for details.
