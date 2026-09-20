# LIKE clean architecture example

This Flutter application demonstrates a production-style authenticated flow against the repository's Dart test server. Every HTTP call uses the local `like` package, with API services extending `LikeBaseApiService`.

## Architecture

The example follows a layered, feature-first structure:

```text
lib/
├── main.dart                 # Minimal application entry point
├── bootstrap.dart            # Flutter and LIKE initialization
├── app.dart                  # Root widgets, providers, and theme
├── di.dart                   # Service/repository/provider composition
├── core/
│   ├── constants/            # API URLs, app constants, and colors
│   ├── theme/                # Shared Material themes
│   └── utils/                # Validation and context utilities
├── data/
│   ├── models/               # Typed API entities and pagination models
│   ├── services/             # Low-level LIKE API calls
│   ├── repositories/         # Application-facing data operations
│   ├── providers/            # Reactive presentation state
│   └── storage/              # Secure token persistence
├── screens/                  # Feature and screen-specific UI
│   ├── auth/
│   ├── home/
│   ├── posts/
│   ├── profile/
│   └── tools/
└── widgets/                  # Globally reusable UI states
```

Dependencies flow from widgets and providers toward repositories, then services and storage. `di.dart` creates each dependency once and exposes presentation state with Provider.

## Authentication and token refresh

Access and refresh tokens are persisted with `flutter_secure_storage`. On startup the application restores the stored session and requests the current user.

The LIKE authentication interceptor is configured to:

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
dart pub get
dart run bin/server.dart
```

The API listens on `http://localhost:8080` and persists data in `server/like_test_server.db`.

## Run the Flutter app

In a second terminal:

```bash
cd example
flutter pub get
flutter run -d linux
```

Web is supported with:

```bash
flutter run -d chrome
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
