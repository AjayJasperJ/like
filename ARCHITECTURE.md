# Testable application flow

LIKE's client handles transport, caching and network recovery. Applications own
endpoint services, business repositories and presentation state.

UI → Provider / Riverpod / BLoC → repository contract → service → LikeHttpClient
→ HTTP API → optional backend Redis cache → database.

Provider, Riverpod and BLoC are alternatives, not sequential layers. Redis belongs
behind the API. No Redis credentials or Redis socket client belongs in this mobile
example. The bundled test server still uses SQLite; Redis is not implemented here.

## Boundaries and source map

| Boundary | Source | Test replacement |
| --- | --- | --- |
| HTTP contract | `lib/src/client/like_http_client.dart` | Implement/mock LikeHttpClient |
| HTTP engine | `lib/src/client/like_client.dart` | Scoped client with a Dio adapter |
| Service | `example/lib/data/services/post_api_service.dart` | Inject client in constructor |
| Repository contract | `example/lib/data/repositories/post_repository.dart` | Implement/mock PostsRepository |
| Provider | `example/lib/data/providers/post_provider.dart` | Inject repository |
| Riverpod | `example/lib/data/riverpod/posts_providers.dart` | Override postsRepositoryProvider |
| BLoC/Cubit | `example/lib/data/bloc/posts_cubit.dart` | Inject repository |
| Integration tests | `example/test/architecture_test.dart` | No server or Hive bootstrap |

LikeBaseApiService accepts LikeHttpClient while retaining the default LikeClient
for existing callers. Injected clients are caller-owned: a service never disposes
a shared client. Endpoint parsing stays in services; repositories expose business
operations; presentation adapters own loading and lifecycle state. Provider query,
Riverpod stream and Cubit adapters share LikeQuery cancellation, generation guards,
resource invalidation and reconnect subscriptions. Replacing/disposing an owner
cancels its HTTP token and releases subscriptions. The Riverpod page FutureProvider
also forwards and cancels its repository token.

## Public testing surface

Import `package:like/testing.dart` for the client factory, request registry, cache,
ETag, retry, connectivity, offline queue, pipeline and sync components. Authentication,
mocking and WebSocket APIs remain available through the normal package export.
This entrypoint exposes existing mechanisms for direct tests; it does not enable
runtime developer tooling or bypass authentication.

- Unit tests: inject LikeHttpClient; no default singleton initialization is needed.
- Repository/state tests: inject PostsRepository or use a Riverpod override.
- Interceptor tests: replace the scoped client's `dio.httpClientAdapter` with a
  deterministic adapter. Use Hive temporary storage for persistence tests.
- Widget tests: use the existing builder tests under `test/widgets/`.
- Server tests: run the independent server package's auth/session tests.

Run locally:

```sh
flutter pub get
flutter test --coverage
cd example
flutter test --coverage
cd ../server
dart pub get
dart test
```

CI runs these checks, strict analysis, the web build and publication validation.
Coverage artifacts remain downloadable for one day. SDK/dependency downloads are
not uploaded and are deleted at job completion, with a one-hour job timeout.
Coverage describes exercised lines, not a promise that every behavior is tested.
The original offline/session/retry roadmap remains separate from this integration.

## Implementation status

See [pending tasks and flow updates](documents/pending_tasks.md) for completed
increments, remaining work, acceptance criteria and current versus target flows.


## Complete public API projects

The independent `examples/provider_app`, `examples/riverpod_app` and
`examples/bloc_app` projects each own immutable ShopState through their state
library. `examples/shop_shared/lib/src/domain` defines repository contracts and
values; `data` implements HTTP/storage; `application` implements user operations;
`presentation` renders state and dispatches actions. Repository and SessionStore
interfaces allow deterministic replacements without initializing a backend.

Each app includes host/Chrome UI tests and an integration_test flow entry point.
The native device script also runs the production repository against the public
API with actual secure storage and Hive. See the
[implementation report](documents/implementation_report.md) for the source/test
mapping, public API behavior, supported scope and release setup.
