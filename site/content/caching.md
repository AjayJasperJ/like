# Caching & invalidation

## Read flow

A request can use memory, persistent Hive data, stale revalidation or conditional
HTTP freshness checks. Actual behavior depends on request options and cache policy.

| Layer | Purpose |
| --- | --- |
| L1 registry | Bounded memory responses/in-flight deduplication |
| L2 Hive | Persist supported payload types across process restarts |
| SWR | Return eligible stale data while a background fetch revalidates |
| ETag / 304 | Ask the server whether content is still fresh |

Identity includes the effective origin, typed query values and session scope.
The same path on two APIs or accounts must not share ownership.

## Tag a read and invalidate a write

```dart
import 'package:like/like.dart';

final client = LikeClient();
await client.get('/products',
  staleWhileRevalidate: true,
  requestConfig: LikeRequestConfig(cacheTags: const ['products']),
);
await client.post('/products/add',
  body: {'title': 'Demo'},
  requestConfig: LikeRequestConfig(invalidates: const ['products']),
);
```

Successful mutations invalidate matching resource data, freshness metadata and
query observers within scope/origin. Acknowledge server success even if local disk
cleanup fails; the invalidation mechanism guards stale reuse during cleanup.

## Choose fallback deliberately

Set `cacheOnOffline`, `cacheOnError` or `cacheOnException` only when appropriate.
Their default is false. Use `disableCache: true` for reads that must bypass cache;
review `ARS` when a state flow supplies overriding fetch policy.

Old JSON cache reads remain supported. New formats preserve maps, strings and
bytes. Image caches have their own namespace and lifecycle. See [media](media/).
