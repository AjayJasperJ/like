# Like real application example

This Flutter application demonstrates a production-style authenticated flow against the repository's Dart test server. HTTP calls are implemented through the local `like` package and services extending `LikeBaseApiService`.

## Architecture

The example is organized into focused application layers:

- `lib/urls`: base URL selection and endpoint constants.
- `lib/services`: secure token persistence and low-level Like API services.
- `lib/repositories`: domain-facing authentication, post, and system operations.
- `lib/providers`: application state, loading, errors, and session lifecycle.
- `lib/screens`: login, registration, posts, profile, and API tools pages.
- `lib/widgets`: reusable forms, post cards, loading, error, and empty states.

## Authentication and token refresh

Access and refresh tokens are persisted with `flutter_secure_storage`. On startup the application restores the stored session and requests the current user.

`LikeAuthInterceptor` is configured to:

1. Read the access token from secure storage for authenticated requests.
2. Read the refresh token and call `/api/auth/refresh` after a 401.
3. Persist both newly rotated tokens returned by the refresh endpoint.
4. Retry the original request with the new access token.
5. Clear secure storage and return to login when refresh fails or a retried request is unauthorized.

Logout revokes the current refresh token on the server and clears local secure storage.

## Start the API server

From the repository root:

```bash
cd server
/home/ja5p3r/flutter/bin/dart pub get
/home/ja5p3r/flutter/bin/dart run bin/server.dart
```

The API listens on `http://localhost:8080` and persists data in `server/like_test_server.db`.

## Run the Flutter app

In a second terminal:

```bash
cd example
/home/ja5p3r/flutter/bin/flutter pub get
/home/ja5p3r/flutter/bin/flutter run -d linux
```

Web is supported with:

```bash
/home/ja5p3r/flutter/bin/flutter run -d chrome
```

`ApiUrls.baseUrl` automatically uses `http://10.0.2.2:8080` on an Android emulator and `http://localhost:8080` on web, Linux, and other local platforms.

## Application flow

- Register a new account or sign in.
- Restore the authenticated session after restarting the app.
- Browse paginated posts, search, and filter by publication status.
- Open post details.
- Create, fully replace, publish/unpublish with PATCH, and delete posts.
- View the authenticated profile and log out.
- Use the tools page for metadata, health, database reset, intentional status responses, and delayed requests.
