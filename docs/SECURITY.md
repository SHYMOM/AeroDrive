# Security

## Threat Model

### Assets Protected
- **File contents**: All user files stored on Telegram channels
- **File metadata**: File names, folder structure, sizes (encrypted in manifest messages)
- **Master Key (MK)**: The single secret that derives all content encryption keys
- **Session data**: Telegram authentication credentials

### Trust Assumptions
- **Telegram servers are untrusted**: Telegram is treated as a dumb storage backend that may read, modify, or delete raw data. Since all files are encrypted client-side before upload, Telegram cannot access plaintext.
- **Local device is trusted**: Assumes the user's device OS has not been compromised. On Android, file-based encryption (FBE) provides additional protection.
- **Network is untrusted**: All communication with Telegram uses TLS. The Go backend (if used) should be deployed behind TLS.
- **Go backend is semi-trusted**: The backend handles encrypted blobs only, but could refuse service or log access patterns. It never receives encryption keys.

### Attack Scenarios & Mitigations

| Scenario | Mitigation |
|---|---|
| Telegram data breach | Zero-knowledge: all files encrypted with user-derived keys before upload |
| Telegram modifies stored ciphertext | AES-256-GCM detects tampering (authentication tag verification) |
| Local device theft (locked) | Android FBE + app-level passphrase for MK derivation |
| Local device theft (unlocked) | Duress mode: hides sensitive channels/files behind alternate passphrase |
| MITM on Telegram connection | TLS 1.3 (handled by TDLib) |
| Backend compromise | Backend has no access to plaintext or keys; at worst can delete blobs |
| Brute-force passphrase | Argon2id (memory-hard, time-cost parameterized) |
| Database exfiltration | File encryption keys derived per-file from MK; DB stores only nonces + ciphertext |

## Encryption Architecture

### Master Key (MK) Derivation

```
Passphrase + Salt → Argon2id → MK (256-bit)
```

- **Convenience mode**: MK cached in `flutter_secure_storage` (biometric/device unlock required on Android)
- **Max security mode**: MK derived on every app launch; never cached; user must enter passphrase each session

### Per-File Encryption

```
MK ──HKDF──→ FileKey(nonce, context="file")

FileKey + Nonce + Plaintext ──AES-256-GCM──→ Ciphertext + AuthTag
```
- Each file gets a unique random 96-bit nonce
- Nonce stored in `encryptionNonce` column (base64)
- Algorithm stored in `encryptionAlgo` column (`AES-256-GCM` or `AES-256-CTR`)
- Streaming media (video/audio) uses AES-256-CTR with per-segment HMAC-SHA256 for integrity

### Key Hierarchy

```
Master Key (MK)
├── File Encryption Keys (HKDF-derived per file)
├── Channel Encryption Key (for manifest messages)
└── Tag Encryption Key (for encrypted tags, future phase)
```

## Zero-DB Recovery

Manifest messages are stored in a dedicated Telegram channel. Each manifest contains:
- File ID, name, size, mime type
- SHA-256 hash (for deduplication)
- Encryption nonce, algorithm
- Chunk → channel + message ID mappings

If the local SQLite database is lost, a recovery flow rescans the manifest channel and rebuilds the DB.

## Cryptographic Primitives

| Primitive | Algorithm | Rationale |
|---|---|---|
| Symmetric encryption | AES-256-GCM | Authenticated encryption; hardware-accelerated on ARM via `cryptography_flutter` |
| Streaming encryption | AES-256-CTR | Seekable; no padding overhead; integrity via segment HMAC |
| Key derivation | Argon2id | Memory-hard; resists GPU/ASIC brute-force |
| Key stretching (HKDF) | HMAC-SHA256 | NIST standard; derives sub-keys from MK |
| Hashing | SHA-256 | Deduplication; native hardware acceleration |
| Secure random | `cryptography` `SecureRandom` | CSPRNG for nonces and salts |

## Security Boundaries

1. **App sandbox**: SQLite DB, cached MK, thumbnails all within app-specific storage
2. **Secure element**: `flutter_secure_storage` uses Android Keystore (TEE/StrongBox when available)
3. **Network**: TLS 1.3 to Telegram; backend communication should use TLS
4. **Process isolation**: Go backend runs as separate process; IPC via stdin/stdout or HTTP loopback
