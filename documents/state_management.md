# State management with LIKE

This guide documents the implemented Provider, Riverpod and BLoC/Cubit integrations,
plus ways to use Flutter's built-in state primitives and other state libraries.
Only the first three have dedicated examples and integration tests in this repository.

## Shared architecture

UI → state owner → repository contract → endpoint service → LikeHttpClient → API.

Provider, Riverpod, BLoC, Redux and GetX are alternative presentation choices.
Services and repositories must not import a presentation library. Inject dependencies
at application startup, and replace the same contracts in tests.

| Layer | Responsibility | Example |
| --- | --- | --- |
| Client | HTTP, authentication, caching, retries | LikeHttpClient / LikeClient |
| Service | Endpoint parameters and response mapping | PostApiService |
| Repository | Application operations and data-source coordination | PostsRepository / PostRepository |
| State owner | Loading, results, refresh, lifecycle | PostProvider / Riverpod provider / PostsCubit |
| UI | Render state and dispatch user intent | LikeBuilder / Consumer / BlocBuilder |

Initialize LIKE once before using the default real client. See the
[root README](../README.md#1-initialization). Injected client mocks do not need
network, connectivity or Hive initialization.

## 1. Provider and ChangeNotifier

Use Provider when a feature already uses ChangeNotifier and needs LIKE's
LikeStateMixin and notifier-based builders.

The implemented example injects PostsRepository into PostProvider:

```dart
final repository = PostRepository(PostApiService());
final provider = PostProvider(repository);
await provider.load();
```

In a widget tree, construct the notifier with ChangeNotifierProvider and read
the repository from Provider<PostsRepository>. The
[composition root](../example/lib/di.dart) shows the actual registration.

Render the notifier's postsState with LikeBuilder. PostProvider uses
PaginatedNotifierState for loading pages, refreshing and loading more. Invoke
loadMore(), filter(), save(), toggle() and remove() through the provider.
Those mutation methods refresh the list after successful writes.

Ownership: ChangeNotifierProvider disposes an object it creates. For a notifier
created elsewhere and supplied through a value constructor, its creator owns
disposal. Do not create a notifier or run load() on every build.

Sources:
[provider](../example/lib/data/providers/post_provider.dart),
[repository](../example/lib/data/repositories/post_repository.dart).

## 2. Riverpod

Use Riverpod when the application uses provider families, overrides and explicit
dependency graphs. The example depends on flutter_riverpod 3.x.

```dart
final result = await container.read(postsPageProvider(1).future);
```

In ConsumerWidget/ConsumerState, watch postsPageProvider(page). It produces
AsyncValue<ApiResult<PaginatedPosts>>. Handle both layers:

- AsyncValue loading: the operation is pending.
- AsyncValue error: an unexpected thrown exception occurred.
- AsyncValue data + result.isSuccess: render result.data.
- AsyncValue data + result.isError: render result.error.

LIKE represents expected API failures as ApiResult values; they do not
automatically become Riverpod AsyncError.

Refresh a page or invalidate it after a successful mutation:

```dart
ref.invalidate(postsPageProvider(page));
```

Override postsRepositoryProvider in ProviderScope or ProviderContainer tests:

```dart
final container = ProviderContainer(overrides: [
  postsRepositoryProvider.overrideWithValue(fakeRepository),
]);
try {
  final result = await container.read(postsPageProvider(1).future);
  // Assert the result.
} finally {
  container.dispose();
}
```

The page family is autoDispose. That releases Riverpod's observer state; it does
not cancel the repository's underlying HTTP operation in this example.
Propagate a CancelToken through service/repository methods when actual transport
cancellation is required, then cancel it through ref.onDispose.

Source: [Riverpod integration](../example/lib/data/riverpod/posts_providers.dart).

## 3. BLoC and Cubit

Use BLoC when the application organizes presentation around streams, events or
explicit transitions. The implemented example uses Cubit from flutter_bloc 9.x.

```dart
final cubit = PostsCubit(repository);
await cubit.load(page: 1);
final snapshot = cubit.state;
await cubit.close();
```

PostsCubit emits LikeStateResponse<PaginatedPosts>. Render it with BlocBuilder;
inspect snapshot.state, snapshot.data and snapshot.error. Trigger load() from
initialization or user actions rather than the builder.

The Cubit assigns a generation to each load. A newer load wins if completions
arrive out of order, and closed Cubits ignore late results. These guards suppress
stale emissions; they do not abort the network request.

For event-based Bloc, inject the same PostsRepository and call it from a load
event handler. Choose sequential, concurrent or restartable event processing
explicitly. A Bloc event transformer is not supplied by LIKE.

Source: [Cubit implementation](../example/lib/data/bloc/posts_cubit.dart).

## 4. ValueNotifier and ValueListenableBuilder

For a small screen, store LikeStateResponse<T> in ValueNotifier and use
ValueListenableBuilder. Set loading before awaiting the repository, then assign
result.toStateResponse(). Handle unexpected exceptions as an error state.

The state owner must track whether it is disposed and reject stale completions.
Dispose the ValueNotifier when the owner is destroyed. Use LikeNotifierState and
LikeBuilder when the additional LIKE notifier behavior is useful.

This is an integration pattern, not a separate adapter package.

## 5. StatefulWidget, FutureBuilder and StreamBuilder

For one-off reads, store a repository Future in initState (or when its input
changes) and render it with FutureBuilder<ApiResult<T>>. Do not create that Future
inside build, which can repeat requests.

For manual setState, check mounted after await and use a request generation when
inputs can change while a request is pending.

StreamBuilder can consume a repository's Stream<ApiResult<T>> if the application
provides one. LIKE does not automatically turn every repository Future into a
realtime stream. Own subscriptions and close application-created controllers.

## 6. GetX, MobX and Redux

These libraries can consume the same repository contract. Dedicated integrations
and tests for them are not included in this repository.

| Library | State owner | Repository integration | Cleanup |
| --- | --- | --- | --- |
| GetX | GetxController | Assign results to observable fields in controller methods | Cancel owned work in onClose |
| MobX | Store / actions | Call the repository inside an asynchronous action | Dispose reactions and owned subscriptions |
| Redux | Middleware / effects | Dispatch loading, call repository, dispatch success/failure | Cancel owned effects and ignore obsolete results |

Keep network calls out of Redux reducers and MobX computed getters. Reducers must
remain pure. Reuse ApiResult/LikeError rather than creating competing HTTP error
translation in each presentation adapter.

## Errors, cache metadata and mutations

ApiResult carries success/error and cache provenance. Preserve those flags when
adding application transformations. toStateResponse() is the bridge used by the
Cubit; inspect the original ApiResult when additional provenance is required.

Caching, retry and offline behavior remain client/request policies. Selecting a
state library does not automatically enable offline mutation replay, rollback,
idempotency or transport cancellation.

Decide which queries a mutation affects. The Provider example explicitly refreshes
its list; Riverpod callers invalidate the affected page family; BLoC callers can
dispatch or invoke a refresh after success. Do not assume the minimal Riverpod
or Cubit example has the complete LikeStateMixin reconnection/pipeline behavior.

Redis is a server-side data/cache concern behind the HTTP API, not a mobile state
manager. No Redis implementation or client credentials are included here.

## Testing and inspection

Use `package:like/testing.dart` for the public client, adapter, registry,
interceptor, connectivity, pipeline and sync test surface.

| Test level | Replace | Verify |
| --- | --- | --- |
| Service | LikeHttpClient | Endpoint options, mapping and API errors |
| Repository | Endpoint service/client | Application operations and result propagation |
| Provider | PostsRepository | Actions, pagination and refresh behavior |
| Riverpod | postsRepositoryProvider override | Family inputs and result/error handling |
| Cubit | PostsRepository | Transitions, stale completions and close behavior |
| HTTP engine | Dio HttpClientAdapter | Retry, caching, auth and cancellation |
| Widget | Injected state owner | Loading, data, empty and failure rendering |

The [architecture tests](../example/test/architecture_test.dart) currently cover
service/repository injection, Provider error forwarding, a Riverpod repository
override, Cubit API errors, overlapping loads and completion after close.
The table above also lists recommended coverage beyond those existing tests.

Run the suites:

```sh
flutter pub get
flutter test --coverage

cd example
flutter test --coverage

cd ../server
dart pub get
dart test
```

GitHub Actions also runs strict analysis, a web example build and publication
validation. Download the test-coverage artifact from the workflow run to inspect
core and example LCOV reports. Artifacts expire after one day. The temporary SDK
is not cached and is removed at completion; the job timeout is one hour.

See [ARCHITECTURE.md](../ARCHITECTURE.md) for the source map and
[the interceptor pipeline](interceptor_pipeline.md) for request processing details.
