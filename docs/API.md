# AeroDrive Backend API

The Go backend (`backend/cmd/server`) provides a REST API and WebDAV interface for share links and remote file access.

## Base URL

```
http://localhost:8090/api/v1
```

All endpoints return JSON. Authenticated requests use an API token via the `Authorization: Bearer <token>` header.

## Authentication

### POST /auth/token
Exchange a one-time setup code for a bearer token.

**Request:**
```json
{
  "setup_code": "string"
}
```

**Response:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_at": "2026-12-31T23:59:59Z"
}
```

## Share Links

### POST /share-links
Create a share link.

**Request:**
```json
{
  "file_id": "uuid",
  "password": "optional-password",
  "expires_in_hours": 24,
  "max_downloads": 5,
  "burn_after_reading": false
}
```

**Response:**
```json
{
  "id": "uuid",
  "token": "abc123def456",
  "url": "https://share.aerodrive.app/s/abc123def456",
  "expires_at": "2026-06-27T12:00:00Z",
  "max_downloads": 5,
  "burn_after_reading": false
}
```

### GET /share-links
List active share links.

### DELETE /share-links/:id
Revoke a share link.

### GET /s/:token
Public download endpoint. Requires password if set.

**Query params:** `?password=xxx`

**Response:** Binary stream with `Content-Disposition: attachment`.

## Health

### GET /health
```json
{
  "status": "ok",
  "version": "0.1.0",
  "uptime_seconds": 3600
}
```

## WebDAV

The WebDAV endpoint is at `/dav/`. Standard WebDAV methods are supported:

- `PROPFIND` — list directory contents
- `GET` — stream decrypted file
- `PUT` — upload encrypted file
- `MKCOL` — create folder
- `MOVE` — rename/move
- `DELETE` — soft-delete

WebDAV decryption/encryption happens on-the-fly via the Go backend using streamed cipher operations. The backend must be configured with the user's MK to perform WebDAV decryption.

## Error Responses

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Share link not found or expired"
  }
}
```

Common codes: `UNAUTHORIZED`, `NOT_FOUND`, `RATE_LIMITED`, `VALIDATION_ERROR`, `FORBIDDEN`, `INTERNAL_ERROR`.

## Rate Limiting

- 100 requests/minute per IP for public endpoints
- 1000 requests/minute per token for authenticated endpoints
- WebDAV operations: 50 concurrent streams per client

## CORS

The server is configured for CORS by default. Allowed origins can be restricted via the `--allowed-origins` flag.
