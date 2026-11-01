# Authentication & sessions

The application owns credential storage and login/logout decisions. LIKE resolves
tokens, coordinates refresh and isolates request/cache/queue ownership.

## Configure token providers

The `tokenStore` below is an application-owned secure store, not a LIKE class:

```dart
import 'package:like/like.dart';

final auth = LikeAuthConfig(
  getToken: () => tokenStore.readAccessToken(),
  refreshToken: () => tokenStore.refreshAndSaveAccessToken(),
  onLogout: ({int? statusCode, bool force = false}) async {
    await tokenStore.clear();
    LikeClient().setSessionScope(const LikeSessionScope());
  },
);
```

Supply this object through `LikeConfig.authConfig`, `LikeClientConfig.authConfig`
or the root's `authConfig`. Do not pass removed `getToken`/`refreshToken` named
arguments directly to the `Like` widget. Use `withAuth: true` on protected calls.

## Set a stable owner after login

```dart
final client = LikeClient();
client.setSessionScope(
  const LikeSessionScope(environment: 'production', accountId: 'customer-42'),
);
final profile = await client.get('/auth/me', withAuth: true);
```

Use a stable account ID, never an access token, as identity. Tokens rotate;
account ownership should not. On logout clear credentials and reset the scope.
Use a consistent named environment across login/logout within each API module.

## What scope changes do

They cancel stale work, clear memory ownership and block another account's queue
from replaying. Protected anonymous operations do not persist cache/queue data.
Legacy ownerless queued entries stay blocked for explicit review.

Concurrent eligible 401 failures share refresh work. Multipart retries reconstruct
the body; throwing auth hooks must settle requests. Your refresh function must
save updated credentials and return the new token; returning null indicates failure.

The examples use native secure storage and account-separated Hive carts. This
does not encrypt every cache in the package or secure a compromised device.
