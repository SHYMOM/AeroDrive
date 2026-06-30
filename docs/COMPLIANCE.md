# Compliance

## Telegram Terms of Service

AeroDrive is an **independent client** that uses Telegram's API for file storage. Users are solely responsible for ensuring their usage complies with Telegram's ToS. Key considerations:

- **Prohibited content**: Users must not store illegal or abusive material. AeroDrive applies zero-knowledge encryption — operators cannot inspect content, but this does not exempt users from legal responsibility.
- **Flood-wait compliance**: AeroDrive respects all `FLOOD_WAIT` signals from Telegram. The TDLib FFI bridge automatically backs off; no bypass mechanisms are implemented.
- **Channel usage**: Users must own the channels used for file storage. Using third-party channels without authorization may violate Telegram ToS.
- **Rate limits**: AeroDrive obeys Telegram's per-account rate limits. Bulk-upload operations are throttled client-side to avoid triggering anti-abuse measures.

## Data Protection Regulations (GDPR, CCPA, etc.)

Since AeroDrive is **zero-knowledge**:

- The app and optional backend never store plaintext file contents.
- Encryption keys (Master Key) are derived client-side from the user's passphrase and never transmitted.
- Telemetry: AeroDrive collects **no analytics, no crash reports, no usage data**. The only network traffic is to Telegram's servers (file storage) and optionally to the user's self-hosted Go backend.
- A user who loses their passphrase **cannot recover their files** — this is by design. No backdoor or key escrow exists.

Users in regulated environments should perform their own Data Protection Impact Assessment (DPIA).

## Open Source License (AGPL-3.0)

AeroDrive is licensed under AGPL-3.0. Any modified version of the software that is made available to users over a network must also provide its source code. This protects against closed-source SaaS forks while allowing personal and internal use freely.

## Third-Party Dependencies

All dependencies are FOSS-compatible:

| Dependency | License | Purpose |
|---|---|---|
| Flutter + Dart SDK | BSD-3-Clause | UI framework |
| Drift | MIT | SQLite ORM |
| Riverpod | MIT | State management |
| go_router | BSD-3-Clause | Routing |
| TDLib | Boost 1.0 | Telegram transport |
| cryptography | Apache-2.0 | AES-256-GCM/CTR, Argon2id |
| flutter_secure_storage | BSD-3-Clause | Secure MK cache |
| chi (Go) | MIT | HTTP router |
| modernc.org/sqlite | BSD-3-Clause | Pure-Go SQLite |

## Export Controls

AeroDrive uses AES-256 encryption, which may be subject to export control regulations in certain jurisdictions. Users are responsible for compliance with local laws regarding the import, export, and use of cryptographic software.
