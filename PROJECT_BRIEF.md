# PROMPT

You are an **Expert Cross-Platform Software Architect and Lead Flutter/Go Engineer** operating inside Google Antigravity with full agentic permissions (editor, terminal, browser subagent). Your job is to design and build **AeroDrive**: a 100% free, open-source, zero-knowledge-encrypted cloud storage application that uses Telegram as a "dumb" storage backend.

This is a large, multi-phase project. **Do not attempt to write all the code in one pass.** Work the way a senior engineer would: produce an Implementation Plan artifact first, get my sign-off, then execute one phase at a time, verifying each phase (build, lint, test, screenshot/emulator run) before moving to the next. If you are ever uncertain about an architectural tradeoff (e.g., TDLib binding strategy, key-derivation parameters), stop and present the options with tradeoffs in an artifact rather than guessing silently.

## 0. Ground rules & constraints

- **Budget: $0.** Every dependency, library, and service must be free and open-source (MIT/Apache-2.0/BSD/AGPL acceptable). No paid SaaS, no proprietary cloud functions, no API keys that cost money. Telegram's own API/Bot API/MTProto is free to use within their ToS.
- **License the repo as AGPL-3.0** at the root (since this touches user data/storage, copyleft protects derivative SaaS forks) — generate `LICENSE`, and note this choice in `README.md` with rationale; ask me to confirm before finalizing if you think MIT is more appropriate for adoption.
- **Compliance note:** Document in `docs/COMPLIANCE.md` that users are responsible for complying with Telegram's Terms of Service, that this tool is for personal backup/storage of content the user has rights to, and that aggressive multi-account/multi-channel pooling must respect Telegram's flood-wait signals rather than evade them (back off, don't bypass).
- **Target first:** Android (minSdk 24+), built so the same Dart/Flutter codebase scales to Windows/Linux/macOS/Web later. Use `LayoutBuilder` / responsive breakpoints from day one — don't hardcode phone-only layouts.
- **Never auto-push to a remote git repository, never commit secrets/.env files, and never run destructive shell commands** (`rm -rf`, `git reset --hard`, force pushes) without explicit confirmation from me first.
- All code must be production-quality: typed, documented with doc comments, null-safe, with error handling on every I/O boundary (network, disk, FFI, crypto) — no bare `catch (e) {}`.

## 1. Tech stack (use exactly this; flag any blocker immediately rather than silently substituting)

| Layer | Choice | Notes |
|---|---|---|
| Frontend | Flutter (stable channel), Dart 3.x, null-safety | Material 3 / Material You |
| State management | Riverpod (`flutter_riverpod` + code-gen) | Prefer over Bloc for less boilerplate; ask me if you have a strong reason to deviate |
| Routing | `go_router` | Needed for responsive nav rail/sidebar swap at desktop breakpoints |
| Local DB | `drift` (SQLite) with `drift_dev` code-gen | Source of truth for all folder/file metadata |
| Telegram transport | TDLib via its **tdjson C interface**, bound through `dart:ffi` (see §3.1 for exact strategy) | Required because Bot API caps files at ~50MB/2GB and can't support true multi-account MTProto sessions |
| Encryption | `cryptography` package (AES-256-GCM for files, AES-256-CTR for streaming) + `cryptography` Argon2id (or `pointycastle` if Argon2id isn't available) for key derivation | Zero-knowledge: plaintext never leaves the device |
| Local AI | `google_mlkit_face_detection`, `google_mlkit_image_labeling` | On-device only, no cloud calls |
| Hashing/dedup | BLAKE3 (`blake3` Dart package) with SHA-256 fallback if no maintained BLAKE3 binding exists for the target platform — verify and report which one you used |
| Secure key storage | `flutter_secure_storage` (Keystore/Keychain) for "Convenience" mode | |
| Background work | Dart `Isolate`/`compute()` worker pool for chunking, hashing, encryption — never block the UI thread | |
| Companion backend | Go 1.22+, standard `net/http` + `chi` or `gorilla/mux` router (your call, justify in plan) | Streaming share-link server |
| Testing | `flutter_test`, `mocktail`, golden tests for key screens; Go `testing` + `httptest` | |

## 2. Repository structure

Generate this top-level layout (adjust only with justification in the plan artifact):

```
aerodrive/
├── app/                          # Flutter application
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/                 # theme, constants, error types, extensions
│   │   ├── data/
│   │   │   ├── db/               # Drift schema, daos, migrations
│   │   │   ├── telegram/         # FFI bindings, TdClient wrapper, session manager
│   │   │   ├── crypto/           # encryption engine, key management, duress logic
│   │   │   └── repositories/     # FileRepository, FolderRepository, ChannelRepository...
│   │   ├── domain/                # entities, use-cases, chunking/queue algorithms
│   │   ├── features/
│   │   │   ├── auth/              # phone+OTP login, account linking
│   │   │   ├── drive/             # file browser, grid/list, drag-drop
│   │   │   ├── upload_queue/
│   │   │   ├── preview/           # PDF/audio/video/code/archive viewers
│   │   │   ├── search/
│   │   │   ├── trash/
│   │   │   ├── sharing/
│   │   │   └── settings/          # channels, accounts, security modes
│   │   └── widgets/                # shared design-system components
│   ├── test/
│   ├── android/                    # native FFI .so loading config, permissions
│   └── pubspec.yaml
├── backend/                        # Go companion server
│   ├── cmd/server/main.go
│   ├── internal/
│   │   ├── telegram/               # MTProto client for streaming
│   │   ├── linkstore/              # share-link metadata (passwords, expiry, limits)
│   │   ├── streaming/              # HLS/DASH + chunk decrypt-on-the-fly
│   │   └── httpapi/
│   ├── go.mod
│   └── Dockerfile
├── scripts/                        # TDLib cross-compile scripts, codegen runners
├── docs/                            # ARCHITECTURE.md, COMPLIANCE.md, API.md
├── LICENSE
├── PROJECT_BRIEF.md
└── README.md
```

## 3. Core architecture deep-dive

### 3.1 Telegram integration strategy (decide and document before coding)

TDLib does not ship an official Dart package. Before writing any upload/download code, research and present (as a Decision Record artifact) the tradeoffs between:

- **Option A — tdjson FFI bridge:** Build/obtain `libtdjson.so` per Android ABI (arm64-v8a, armeabi-v7a, x86_64), bundle as native libs, and bind the four exported C functions (`td_json_client_create`, `td_json_client_send`, `td_json_client_receive`, `td_json_client_execute`) via `dart:ffi`. All TDLib requests/responses are JSON strings — model them as typed Dart classes with a serialization layer. This is the most "real" approach and supports full user-account MTProto sessions (needed for multi-account pooling and >50MB files).
- **Option B — existing community Dart/Flutter TDLib wrapper** if one is actively maintained and supports Android — evaluate freshness/license before adopting.
- **Option C — pure-Dart MTProto client** (no TDLib dependency) if a viable open-source implementation exists — lower native-build complexity, more protocol code to maintain yourself.

Pick Option A unless you find a clearly superior, actively-maintained alternative, since multi-account/multi-channel pooling and large-file support require real user sessions, not bot tokens. Document the chosen ABI build pipeline in `scripts/build_tdlib.sh` (cross-compile via Docker/NDK) so the build is reproducible.

Authentication flow required: phone number → Telegram-sent OTP → (2FA password if enabled) → persist encrypted session. Support linking N accounts, each with its own session, switchable per upload job.

### 3.2 Data model (Drift schema)

Generate Drift tables at minimum:

- **`folders`**: `id (uuid pk)`, `parentId (nullable fk→folders.id)`, `name`, `createdAt`, `updatedAt`, `isTrashed`, `trashedAt`.
- **`files`**: `id (uuid pk)`, `folderId (fk→folders.id)`, `name`, `mimeType`, `sizeBytes`, `blake3Hash` (indexed, for dedup), `encryptionNonce`, `encryptionAlgo`, `manifestVersion`, `createdAt`, `updatedAt`, `isTrashed`, `trashedAt`, `isFavorite`.
- **`chunks`**: `id (uuid pk)`, `fileId (fk→files.id)`, `chunkIndex`, `channelId (fk→channels.id)`, `accountId (fk→accounts.id)`, `telegramMessageId`, `telegramFileId`, `sizeBytes`, `chunkHash`, `uploadStatus (enum: pending|uploading|done|failed)`.
- **`channels`**: `id (uuid pk)`, `telegramChatId`, `displayName`, `isActive`, `isHidden` (for duress mode), `quotaUsedBytes`.
- **`accounts`**: `id (uuid pk)`, `telegramUserId`, `phoneNumberMasked`, `sessionEncrypted (blob)`, `isActive`.
- **`manifest_messages`**: `id`, `channelId`, `telegramMessageId`, `manifestVersion`, `payloadJson` — the hidden version-tracking messages from §spec item 6.
- **`thumbnails`**: `fileId (fk)`, `encryptedBlob`, `width`, `height`.
- **`share_links`**: `id`, `fileId/folderId`, `token`, `passwordHash (nullable)`, `expiresAt (nullable)`, `maxDownloads (nullable)`, `downloadCount`, `burnAfterReading (bool)`.
- **`upload_queue`**: persisted queue entries so in-flight uploads survive app restarts — `id`, `filePath`, `status`, `priority`, `retryCount`, `lastError`.

Write proper Drift migration files from v1 onward (don't assume schema is final — version it).

### 3.3 Chunking, multi-channel & multi-account pooling algorithm

Implement a `UploadOrchestrator` class with this responsibility split:

1. **Pre-flight**: hash the file (BLAKE3) on a background isolate; check `files.blake3Hash` for an existing match → if found, create a new logical `files` row pointing at the *existing* chunk set (zero re-upload) and finish immediately.
2. **Chunk planning**: if `sizeBytes <= 1.5GB`, plan = 1 chunk. Else split into chunks ≤1.5GB (configurable), respecting TDLib's per-message size limit for the active account type.
3. **Channel/account assignment**: round-robin or least-loaded selection across `channels` marked active, and across `accounts` marked active, so parallel chunk uploads spread across both axes — this is what bypasses per-channel and per-account rate limits simultaneously. Make the selection strategy pluggable (interface `IPoolingStrategy`) so round-robin can later be swapped for weighted/least-quota-used.
4. **Concurrency control**: bounded worker pool (configurable max concurrent chunk uploads, default e.g. 4) using isolates so encryption + network don't block UI.
5. **Flood-wait handling**: catch TDLib `420 FLOOD_WAIT_X` (or equivalent), pause *only that account/channel lane*, exponential backoff with jitter, resume automatically; surface a non-blocking status chip in the UI queue view.
6. **Caption embedding (Zero-DB Recovery)**: on each chunk's Telegram message, set the caption to a compact serialized JSON (or protobuf-lite) blob containing: file UUID, file name, folder path (or folder UUID + a periodically-uploaded folder-tree manifest), chunk index/total, BLAKE3 hash, manifest version. Implement a `RecoveryScanner` that, given a list of channels, paginates through message history, parses captions, and rebuilds the entire `files`/`chunks`/`folders` tables from scratch — write this as a standalone, testable use-case since it's the disaster-recovery path.
7. **Manifest versioning**: when a file is replaced/edited, don't delete old chunks immediately — write a new hidden manifest message bumping `manifestVersion` and pointing to the new chunk set; old chunks become reclaimable by the Trash/30-day-purge logic instead of being orphaned silently.

### 3.4 Client-side encryption module

Implement `EncryptionEngine` with two independent concerns:

- **At-rest file encryption**: AES-256-GCM, one random 96-bit nonce per file (stored in the `files` row, never reused), authenticated encryption so tampering is detectable. Encrypt in chunked streaming fashion (don't load entire file into memory) — read→encrypt→write chunk loop, feeding chunks straight into the upload pipeline.
- **Streaming/seekable decryption**: AES-256-CTR for media that needs random-access scrubbing (so HLS/DASH segment N can be decrypted independently without decrypting 1..N-1 first). Document clearly in code comments *why* GCM is used for static files (integrity) but CTR for streaming media (seekability), and that CTR segments should still carry a separate integrity tag (e.g., per-segment HMAC) since CTR alone has no authentication.
- **Key hierarchy**: a random per-file Data Encryption Key (DEK), wrapped by a Master Key (MK). MK derivation has two modes:
  - **Convenience mode**: MK generated randomly, stored in OS Keychain/Keystore via `flutter_secure_storage`.
  - **Max Security mode**: MK derived via Argon2id from the user's password; a BIP39-style 24-word recovery phrase is generated at setup and is the *only* way to recover the MK if the password is forgotten — make this explicit in the UI copy you generate ("if you lose both, your data is permanently unrecoverable").
- **Duress PIN**: a secondary PIN unlocks a separate MK that only decrypts a hidden, separate set of channels (`channels.isHidden = true`). Entering the normal PIN must never reveal that hidden channels exist (no UI affordance hints at their existence under any code path). Document the threat model and limitations (e.g., this protects against casual coercion glance-checks, not forensic device imaging) honestly in `docs/SECURITY.md` rather than over-promising.

## 4. Feature checklist (implement in the phases below, not all at once)

- File CRUD: upload (single + batch + drag-and-drop on desktop), rename, move, copy, delete (soft), restore.
- Virtual scrolling for folders with thousands of items (e.g. `flutter`'s sliver-based lazy lists, not naive `ListView`).
- Upload queue UI: pause/resume/cancel per item, retry-on-failure, visible per-lane flood-wait status.
- Search: FTS-backed (Drift supports SQLite FTS5) full-text search over filenames at minimum; stretch goal — tags/labels from ML Kit image labeling.
- Trash/Bin: soft delete flag + `trashedAt`; background job purges anything older than 30 days (and reclaims the underlying Telegram chunks per §3.3 manifest logic).
- Previews: PDF render, audio waveform (e.g. via `just_audio` + waveform extraction), syntax-highlighted code viewer, archive (zip/rar) listing+extraction.
- Sharing: generate share link → Go backend issues a token tied to `share_links` row; support password gate, expiry, max-download-count, and Telegram-native TTL "burn after reading" for self-destructing shares.

## 5. Go companion backend

Build `backend/` as a standalone Go module:

- `GET /s/:token` — resolves a share link, prompts for password if set, streams the (decrypted, re-encrypted-over-TLS) file or HLS/DASH manifest to the browser using a Telegram session associated with the link's owner.
- `GET /s/:token/segment/:n` — for media, fetches/decrypts the specific chunk(s) needed for that HLS/DASH segment without pulling the whole file.
- Enforce `expiresAt`, `maxDownloads`/`downloadCount`, and burn-after-reading deletion server-side, not just client-side.
- No persistent plaintext storage on the server — stream-through only, decrypt-in-memory per request.
- Provide a `Dockerfile` and a `docker-compose.yml` (Go backend + nothing else, since DB/state should ideally stay file-based/SQLite for a $0 self-host) for one-command deployment.
- Write `docs/API.md` documenting every endpoint, request/response shape, and error codes.

## 6. UI/UX design system

- Material 3 (Material You), dark-mode-first: deep space blue/purple background (`#0B0C24`-ish range — pick exact tokens and define them in a `lib/core/theme/aerodrive_theme.dart` with a full `ColorScheme`), neon accent for primary actions (electric violet/cyan — your call, present 2–3 palette options as a quick visual artifact before committing).
- Desktop breakpoints (`>= 1024px` sidebar + content, `600–1023px` collapsible nav rail, `< 600px` mobile bottom nav or drawer) using `LayoutBuilder`/`MediaQuery`.
- Subtle glassmorphism (`BackdropFilter` + translucent surfaces) on desktop sidebars/modals only — keep mobile flat/performant (blur filters are expensive on lower-end Android GPUs; gate it behind a platform check).
- Color-coded custom file-type icons (folder, image, video, audio, doc, archive, code, encrypted-unknown).
- Respect accessibility basics: sufficient contrast ratios even with the dark neon theme, scalable text, semantic labels for screen readers on icon-only buttons.

## 7. Phased delivery plan (execute in this order; produce an artifact + verification at the end of each)

> Present this as your Implementation Plan artifact, refine timing/ordering if you see a better sequence, but keep the dependency order intact (you can't test uploads before the Telegram client and encryption engine exist).

- **Phase 0 — Scaffolding**: repo structure, `pubspec.yaml`/`go.mod` with all dependencies pinned, theme skeleton, empty Drift schema + generated code, CI-able `flutter analyze`/`flutter test` baseline, README stub. *Verify*: `flutter run` boots to an empty themed home screen on an emulator; screenshot it.
- **Phase 1 — Telegram client foundation**: implement the chosen FFI/TDLib strategy from §3.1, phone+OTP auth flow, multi-account linking UI, session persistence. *Verify*: log in with a real test account, list chats, screenshot the auth flow.
- **Phase 2 — Encryption engine**: implement `EncryptionEngine`, key management modes, recovery phrase generation/verification screen. *Verify*: unit tests proving encrypt→decrypt round-trips byte-for-byte for files spanning >1 chunk boundary, and that tampering breaks GCM auth as expected.
- **Phase 3 — Drift schema + repositories**: all tables/migrations/DAOs, `FileRepository`/`FolderRepository`/etc. *Verify*: DAO unit tests, including the dedup-by-hash query path.
- **Phase 4 — Upload/download core**: `UploadOrchestrator` (chunking, pooling, flood-wait handling, caption embedding), download/reassembly path, persisted queue surviving app restart. *Verify*: upload a multi-GB test file across ≥2 mock/test channels, confirm chunk rows + Telegram messages match, kill and restart the app mid-upload, confirm resume.
- **Phase 5 — Drive UI**: file browser (grid/list), virtual scrolling, drag-and-drop (desktop), search, trash/bin with 30-day purge job. *Verify*: emulator screenshots of folder navigation, search results, trash restore.
- **Phase 6 — Previews & media**: thumbnail pipeline (native + encrypted-local), PDF/audio/code/archive viewers, HLS/DASH + AES-CTR streaming scrubber for video. *Verify*: open one file of each supported type, screenshot each viewer; scrub a video and confirm no full-file decrypt happens (check timing/memory, not just "it played").
- **Phase 7 — Zero-DB recovery & manifest versioning**: `RecoveryScanner`, manifest message read/write, "Rebuild from Telegram" settings action. *Verify*: wipe local DB, run recovery, confirm folder tree and files reappear correctly.
- **Phase 8 — Sharing & Go backend**: share-link generation in-app, Go server endpoints, password/expiry/max-download enforcement, burn-after-reading via Telegram TTL. *Verify*: generate a link, open it in a real browser (use the Browser Subagent) from a different session, confirm password gate and expiry both function; confirm the link stops working after burn.
- **Phase 9 — Duress PIN & hidden channels**: implement and verify it's truly invisible from the normal PIN path (code-review checklist, not just a happy-path test).
- **Phase 10 — Polish pass**: responsive desktop layout validation, glassmorphism on desktop, accessibility audit, final `docs/ARCHITECTURE.md` + `docs/SECURITY.md` + `README.md` with setup instructions, and a step-by-step "how to run this project" guide (TDLib build, Go backend run, Flutter run) as the final deliverable.

## 8. Definition of done (apply at every phase boundary)

- [ ] `flutter analyze` and `go vet` report zero new warnings.
- [ ] Relevant unit/widget/Go tests pass (`flutter test`, `go test ./...`).
- [ ] App launches and the new feature is demonstrably reachable in the UI (screenshot or Browser Subagent walkthrough attached as an artifact).
- [ ] Any new public function/class has a doc comment explaining intent, not just signature.
- [ ] No secrets, API tokens, or `.env` values committed.
- [ ] Implementation Plan artifact for the *next* phase is ready for my review before you start writing code for it.

---

Begin now: read this brief, then produce your **Phase 0 Implementation Plan artifact** and wait for my approval before touching the filesystem.
