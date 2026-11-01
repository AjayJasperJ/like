# Queries, pages & optimistic UI

## Shared cancellable query

This uses the `CatalogRepository` contract from [Architecture](architecture/):

```dart
import 'package:like/like.dart';

final client = LikeClient();
final query = LikeQuery<Map<String, dynamic>>(
  action: (token) => repository.product(1, token),
  scope: () => client.sessionScope.key,
  origin: client.origin,
  tags: const ['products'],
  sessionChanges: client.sessionChanges,
);
final subscription = query.watch().listen((state) {
  // Publish through your existing state owner.
});
await query.refresh();
// When the owner closes:
await subscription.cancel();
await query.dispose();
```

`watch()` emits the current snapshot then changes. Refresh cancels superseded
transport; generation/scope checks suppress stale publication. Matching tag
invalidation and origin restoration coalesce refresh work.

## Pagination

`LikePagedQuery<T>` accepts an action `(page, cursor, token)` returning
`LikeApiResult<PaginationTool<T>>`, plus an `identity` function and page size.
Call `refresh()`, `loadNext()` and `retryFailedPage()`; render its value as a
`LikePageSnapshot`. It keeps individual pages separate, deduplicates by identity,
retains failed-page cursors and terminates correctly when no more data exists.
Dispose it with the owning state object.

## Optimistic writes

`LikeOptimisticStore<T>` stores ordered layers over a base value. `begin`, `commit`
and `rollback` expose manual control; `mutate` wraps an async action and
reconciliation. An older failure must not overwrite a newer successful mutation.
Reducers should merge entities by stable ID and preserve unrelated concurrent edits.

## UI primitives

Use `LikeNotifierState` with `LikeBuilder`/sliver/selectors/multi-builders for the
notifier route. `LikeWhen` renders a state snapshot. `updateNotifier` provides
configurable feedback; `likeWhenNotifier` gives explicit side-effect callbacks.
These helpers are alternatives, not mandatory layers on top of Riverpod or Cubit.

See [State management](state/) and the [three apps](examples/) for actual adapters.
