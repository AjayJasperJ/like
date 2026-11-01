# HTTP & typed results

## Public boundary

Import `package:like/like.dart`. `LikeHttpClient` is the injectable contract;
`LikeClient` is the real implementation. `LikeBaseApiService` is an optional
base service with injected transport. See [architecture](architecture/) for a
complete contract/service/repository example.

## Read, map and cancel

```dart
import 'package:like/like.dart';

Future<LikeApiResult<Map<String, dynamic>>> fetchProduct(CancelToken token) =>
    LikeClient().get(
      '/products/1',
      cancelToken: token,
      requestConfig: LikeRequestConfig(cacheTags: const ['products']),
    ).mapSync((json) => Map<String, dynamic>.from(json as Map));
```

`mapSync` maps on the current isolate; `mapAsync` uses supported background
mapping. Mappers must match the real response shape and satisfy isolate constraints
where applicable. Pass the cancellation token through repositories and services.
`LikeClient` also supports POST, PUT, PATCH, DELETE and multipart requests.

## Result semantics

| Outcome | How to handle it |
| --- | --- |
| `result.isSuccess` | Render/use `result.data`; successful void results may have null data |
| Expected API failure | Inspect `result.error`, not only thrown exceptions |
| Queued offline action | Show pending/sync state; it is not a completed server write |
| Cancellation | Stop stale updates; avoid presenting it as an outage |
| Mapping/programming exception | Diagnose the parser/contract; preserve error boundaries |

Metadata preserves cache/SWR/304 provenance. `LikeError` standardizes HTTP and
transport failures without forcing presentation decisions into your service.

## Writes

```dart
final result = await LikeClient().post(
  '/products/add',
  body: {'title': 'Demo product'},
  requestConfig: LikeRequestConfig(invalidates: const ['products']),
);
```

This DummyJSON endpoint simulates persistence. A fixture or public demo response
is not proof of durable production writes. For protected requests add
`withAuth: true`; for safe application-owned replay also opt into `offlineSync`.
