# Configuration

Use the narrowest policy boundary that fits the change.

| Scope | API | Use it for |
| --- | --- | --- |
| Application | `LikeConfig` | Storage namespace, defaults, auth and logging |
| Feature/API | `LikeClientConfig` with `LikeClient.scoped` | Independent origin/auth/interceptors |
| One call | `LikeRequestConfig` | Timeout/origin/tag/idempotency overrides |
| Fetch/state | `ARS` | Refresh, SWR, cache and dedup behavior carried through state flows |

## Start with safe explicit choices

```dart
import 'package:like/like.dart';

final config = LikeConfig(
  projectName: 'catalog',
  baseUrl: 'https://dummyjson.com',
  verifySSL: true,
  cacheOnOffline: true,
  sensitiveHeaders: const ['Authorization', 'Cookie', 'Set-Cookie', 'X-Api-Key'],
);
```

Do not assume configuration enables every request policy. The engine may support
offline replay while each mutation still requires explicit `offlineSync: true`.
Protected calls should pass `withAuth: true` explicitly. Read method defaults as
well as global defaults.

## Common defaults

| Option | Default in source | Meaning |
| --- | --- | --- |
| `projectName` | Required | Stable storage namespace |
| `connectTimeout`, `receiveTimeout`, `sendTimeout` | 30 seconds | Transport time bounds |
| `cacheEnabled`, `staleWhileRevalidateEnabled` | true | Engine capability switches |
| `cacheOnOffline`, `cacheOnError`, `cacheOnException` | false | Fallback is not automatic |
| `offlineSyncEnabled` | true | Queue capability enabled |
| `offlineSyncByDefault` | false | Mutation replay is opt-in |
| `maxAutoRetries` | 3 | Retry ceiling subject to policy |
| `cacheTTL` | 7 days | Default persistent cache lifetime |
| `maxL1CacheItems` | 200 | Memory cache bound |
| `maxInFlightRequests` | 100 | Registry bound |
| `verifySSL` | `!kDebugMode` when omitted | Explicitly set true for secure development too |

For **all fields and constructor defaults**, use the generated [configuration source index](api/#likeconfig).
Do not treat this summary as a replacement for the exact version's constructor.

## Response envelopes

`DefaultLikeUnpacker()` reads a common `data` wrapper or the flat JSON value.
For a different contract, extend `LikeDataUnpacker` and return a
`LikeUnpackedResponse`. Its current constructor does not accept custom `dataKey`
or `messageKey` arguments.

## Multiple APIs

```dart
final partner = LikeClient.scoped(
  LikeClientConfig(
    baseUrl: 'https://partner.example',
    connectTimeout: const Duration(seconds: 15),
  ),
);
// ... inject into your service, then partner.dispose() when its owner closes.
```

Per-call settings go through `requestConfig`. See [Scoped clients](multi-client/)
and the [interceptor order](pipeline/) before adding custom interceptors.
