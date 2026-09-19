# Like Test API Server

A standalone Dart REST API for developing and testing the Like client. It includes a complete JWT authentication flow, CRUD test APIs, and SQLite persistence for users, refresh sessions, and posts.

## Run

```bash
cd server
dart pub get
JWT_SECRET='replace-this-in-real-usage' dart run bin/server.dart
```

The default URL is `http://localhost:8080`. Configure it with `HOST`, `PORT`, `JWT_SECRET`, and `DATABASE_PATH` environment variables. The default database is `like_test_server.db` in the server working directory; its schema and seed posts are created automatically. Runtime `.db`, `.db-shm`, and `.db-wal` files are ignored by Git.

## Architecture

The server uses a small layered architecture so transport, business logic, and in-memory state can evolve independently:

```text
bin/server.dart                    Process startup and environment configuration
lib/server.dart                    Public package API
lib/src/test_api_server.dart       Route and dependency composition root
lib/src/controllers/               HTTP endpoint handlers
lib/src/services/                  Authentication and token business logic
lib/src/repositories/              SQLite-backed users, posts, and sessions
lib/src/database/                  SQLite connection and schema migration
lib/src/models/                    Domain models
lib/src/middleware/                Authentication, CORS, and error handling
lib/src/http/                      Shared request parsing and JSON responses
lib/src/core/                      Shared API exceptions
```

Tests import `package:like_test_server/server.dart`, while the executable remains a minimal deployment entry point.

## Authentication flow

Only `/`, `/health`, registration, login, and token refresh are public. Every other route requires:

```text
Authorization: Bearer <accessToken>
```

Access tokens are signed JWTs that expire after 15 minutes. Refresh tokens are opaque, stored only as SHA-256 hashes in SQLite, expire after 7 days, and rotate on every refresh. Logout revokes the submitted refresh token. Users, posts, and refresh sessions persist across server restarts.

### 1. Register

```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"name":"Test User","email":"test@example.com","password":"password123"}'
```

Registration returns the user, an `accessToken`, and a `refreshToken`. Passwords require at least 8 characters and are stored as iteratively salted SHA-256 hashes for this local test server.

### 2. Login

```bash
curl -X POST http://localhost:8080/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"password123"}'
```

### 3. Call protected APIs

```bash
ACCESS_TOKEN='value-from-register-or-login'
curl http://localhost:8080/api/auth/me \
  -H "Authorization: Bearer $ACCESS_TOKEN"
curl 'http://localhost:8080/api/posts?page=1&limit=5' \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

### 4. Refresh with rotation

```bash
REFRESH_TOKEN='value-from-register-or-login'
curl -X POST http://localhost:8080/api/auth/refresh \
  -H 'Content-Type: application/json' \
  -d "{\"refreshToken\":\"$REFRESH_TOKEN\"}"
```

The old refresh token is immediately invalidated. Save both tokens returned by this endpoint.

### 5. Logout

```bash
curl -X POST http://localhost:8080/api/auth/logout \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d "{\"refreshToken\":\"$REFRESH_TOKEN\"}"
```

Logout revokes the refresh token. The stateless access JWT remains valid until its short expiration time.

## API endpoints

| Access | Method | Route                      | Description                       |
| ------ | ------ | -------------------------- | --------------------------------- |
| Public | GET    | `/`                        | API metadata and route list       |
| Public | GET    | `/health`                  | Health check                      |
| Public | POST   | `/api/auth/register`       | Register and create a session     |
| Public | POST   | `/api/auth/login`          | Authenticate and create a session |
| Public | POST   | `/api/auth/refresh`        | Rotate a valid refresh token      |
| JWT    | POST   | `/api/auth/logout`         | Revoke the supplied refresh token |
| JWT    | GET    | `/api/auth/me`             | Return the authenticated user     |
| JWT    | GET    | `/api/posts`               | Paginated post collection         |
| JWT    | GET    | `/api/posts/:id`           | Fetch one post                    |
| JWT    | POST   | `/api/posts`               | Create a post                     |
| JWT    | PUT    | `/api/posts/:id`           | Fully replace a post              |
| JWT    | PATCH  | `/api/posts/:id`           | Partially update a post           |
| JWT    | DELETE | `/api/posts/:id`           | Delete a post; returns 204        |
| JWT    | POST   | `/api/reset`               | Restore the 35 seed posts         |
| JWT    | GET    | `/api/status/:code`        | Return an intentional HTTP status |
| JWT    | GET    | `/api/delay/:milliseconds` | Delay by up to 30 seconds         |

## Post schema

```json
{
  "id": 1,
  "title": "Test post 1",
  "body": "This is the body of test post 1.",
  "published": false,
  "userId": 1,
  "createdAt": "2026-01-01T00:00:00.000Z"
}
```

For POST and PUT, `title`, `body`, and `userId` are required. `published` is optional and defaults to `false`. PATCH accepts one or more editable fields.

## Pagination and filtering

`GET /api/posts` supports:

- `page`: positive integer, default `1`
- `limit`: 1–100, default `10`
- `search`: case-insensitive title/body search
- `published`: `true` or `false`
- `userId`: positive integer
- `sort`: `id`, `title`, `createdAt`, or `userId`
- `order`: `asc` or `desc`

```bash
curl 'http://localhost:8080/api/posts?page=2&limit=5&published=true&sort=id&order=desc' \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

## CRUD examples

```bash
# Create
curl -X POST http://localhost:8080/api/posts \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"title":"Created post","body":"Created body","published":true,"userId":7}'

# Replace
curl -X PUT http://localhost:8080/api/posts/1 \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"title":"Replacement","body":"Replacement body","published":false,"userId":2}'

# Patch
curl -X PATCH http://localhost:8080/api/posts/1 \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"published":true}'

# Delete
curl -i -X DELETE http://localhost:8080/api/posts/1 \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

## Error and resilience testing

```bash
curl -i http://localhost:8080/api/status/503 \
  -H "Authorization: Bearer $ACCESS_TOKEN"
curl http://localhost:8080/api/delay/2000 \
  -H "Authorization: Bearer $ACCESS_TOKEN"
curl -X POST http://localhost:8080/api/reset \
  -H "Authorization: Bearer $ACCESS_TOKEN"
```

CORS, request logging, JSON validation, structured errors, compression, refresh-token rotation, and end-to-end authentication tests are included.
