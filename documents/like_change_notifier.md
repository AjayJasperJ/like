# `LikeChangeNotifier` Guide: Custom Models & Custom Maps

`LikeChangeNotifier` is a lightweight `ChangeNotifier` mixin for `fetch` / `fetchResult` / `fetchResponse` / `fetchResponseResult` / `fetchPaginatedResponse` / `fetcher` / `fetcherResult` / `paginatedFetcher` calls with automatic `CancelToken` rotation, silent cancellation handling, `ars.skip`, keyed state maps (`keyedStates` / `paginatedStates` / `keyedResponses` / `keyedPaginatedResponses`), and `.toInitState()`.

---

## 1. Custom Model Example

```dart
class PostModel {
  final String id;
  final String title;

  const PostModel({required this.id, required this.title});

  factory PostModel.fromJson(dynamic raw) {
    final json = raw as Map<String, dynamic>;
    return PostModel(
      id: json['id'].toString(),
      title: json['title'] as String? ?? '',
    );
  }
}
```

---

## 2. Storing Custom Models & Custom Maps in `LikeChangeNotifier`

Use `getByKey<T>(key)` for any custom model or custom `Map<K, V>`, and `getPaginatedByKey<T>(key)` for paginated lists of custom models or maps:

```dart
import 'package:flutter/foundation.dart';
import 'package:like/like.dart';

class FeedProvider extends ChangeNotifier with LikeChangeNotifier {
  final LikeHttpClient _http;
  FeedProvider(this._http);

  // 1. Custom model state by key (ValueNotifier-backed vs immutable snapshot Map)
  LikeNotifierState<PostModel> postState(String postId) =>
      getByKey<PostModel>('post:$postId');
  LikeStateResponse<PostModel> postResponse(String postId) =>
      getResponseByKey<PostModel>('post:$postId');

  // 2. Custom Map state by key (e.g. dashboard counters or grouped items)
  LikeNotifierState<Map<String, dynamic>> get statsMapState =>
      getByKey<Map<String, dynamic>>('dashboard_stats');
  LikeStateResponse<Map<String, dynamic>> get statsMapResponse =>
      getResponseByKey<Map<String, dynamic>>('dashboard_stats');

  LikeNotifierState<Map<String, List<PostModel>>> get groupedPostsState =>
      getByKey<Map<String, List<PostModel>>>('grouped_posts');

  // 3. Paginated custom model state by key
  PaginatedNotifierState<PostModel> feedState(String category) =>
      getPaginatedByKey<PostModel>('feed:$category', pageSize: 20);
  LikePaginatedResponse<PostModel> feedResponse(String category) =>
      getPaginatedResponseByKey<PostModel>('feed:$category', pageSize: 20);

  // 4. Optional local custom map alongside keyed states
  final Map<String, PostModel> _pinnedById = {};
  Map<String, PostModel> get pinnedById => Map.unmodifiable(_pinnedById);

  Future<void> loadPost(String postId, {bool forceRefresh = false}) {
    return fetchResult<PostModel>(
      state: postState(postId),
      ars: LikeARS(skip: !forceRefresh, checkAvailability: true),
      action: (ct, _) => _http
          .get('/posts/$postId', cancelToken: ct)
          .mapSync(PostModel.fromJson),
    );
  }

  Future<void> loadStatsMap() {
    return fetchResult<Map<String, dynamic>>(
      state: statsMapState,
      action: (ct, _) => _http
          .get('/stats', cancelToken: ct)
          .mapSync((data) => Map<String, dynamic>.from(data as Map)),
    );
  }

  Future<void> loadGroupedPosts() {
    return fetchResult<Map<String, List<PostModel>>>(
      state: groupedPostsState,
      action: (ct, _) => _http.get('/posts/grouped', cancelToken: ct).mapSync(
        (raw) {
          final map = raw as Map<String, dynamic>;
          return map.map(
            (group, items) => MapEntry(
              group,
              (items as List).map(PostModel.fromJson).toList(growable: false),
            ),
          );
        },
      ),
    );
  }

  Future<void> loadCategoryFeed(String category, {bool refresh = false}) {
    return feedState(category).loadCursor(
      refresh: refresh,
      action: (cursor, limit) => _http
          .get(
            '/posts',
            query: {
              'category': category,
              'limit': limit,
              if (cursor != null) 'cursor': cursor,
            },
          )
          .mapSync((raw) {
            final json = raw as Map<String, dynamic>;
            return PaginationTool<PostModel>(
              cursorBased: true,
              cursor: json['currentCursor'] as String?,
              nextCursor: json['nextCursor'] as String?,
              hasNextOverride: json['loadMore'] as bool?,
              listData: (json['items'] as List? ?? const [])
                  .map(PostModel.fromJson)
                  .toList(growable: false),
            );
          }),
    );
  }

  /// Offset-based pagination (PaginatedNotifierState)
  Future<void> loadCategoryFeedByOffset(
    String category, {
    int page = 1,
    bool refresh = false,
  }) {
    return feedState(category).load(
      page: refresh ? 1 : page,
      refresh: refresh,
      action: (p, limit) {
        final offset = (p - 1) * limit;
        return _http
            .get(
              '/posts',
              query: {
                'category': category,
                'offset': offset,
                'limit': limit,
              },
            )
            .mapSync((raw) {
              final json = raw as Map<String, dynamic>;
              return PaginationTool<PostModel>(
                page: p,
                contentLimit: limit,
                totalContent: json['total'] as int?,
                hasNextOverride: json['hasMore'] as bool?,
                listData: (json['items'] as List? ?? const [])
                    .map(PostModel.fromJson)
                    .toList(growable: false),
              );
            });
      },
    );
  }

  void pinPost(PostModel post) {
    _pinnedById[post.id] = post;
    notifyListeners();
  }

  /// Reset one key or all keyed & paginated states back to idle
  void resetKey(Object key) => toInitState(key);

  void resetAll() {
    _pinnedById.clear();
    toInitState();
  }
}
```

---

## 3. Observing Custom Models & Maps in Flutter UI

Use `LikeNotifierBuilder<T>` / `LikeNotifierSliver<T>` for `LikeNotifierState<T>` (direct `ListenableBuilder` fast-path), or `LikeBuilder<T>` / `LikeSliverBuilder<T>`:

```dart
// Observing a custom model by key with LikeNotifierBuilder
LikeNotifierBuilder<PostModel>(
  state: provider.postState('42'),
  onLoading: () => const CircularProgressIndicator(),
  onSuccess: (post, isRefreshing, _) => Text(post.title),
  onError: (err) => Text(err.message),
)

// Observing a custom Map by key
LikeNotifierBuilder<Map<String, dynamic>>(
  state: provider.statsMapState,
  onSuccess: (stats, _, _) => Text('Total: ${stats['total'] ?? 0}'),
)

// Resetting a single state back to idle
provider.postState('42').toInitState();
// or
provider.toInitState('feed:news');
```

---

## 4. Direct `LikeStateResponse<T>` & `keyedResponses` Support

If you prefer plain immutable `LikeStateResponse<T>` fields or a `Map<Object, LikeStateResponse<dynamic>>` instead of `LikeNotifierState<T>` (for example, when using `Provider` / `context.select` / `LikeStateResponseBuilder`), use `fetchResponse`, `fetchResponseResult`, or the keyed helpers `getResponseByKey`, `setResponseByKey`, `fetchResponseByKey`, and `fetchResponseResultByKey`:

```dart
class ProfileProvider extends ChangeNotifier with LikeChangeNotifier {
  final LikeHttpClient _http;
  ProfileProvider(this._http);

  // Option A: Direct LikeStateResponse field
  LikeStateResponse<PostModel> featured = LikeStateResponse.idle();

  Future<void> loadFeatured({bool refresh = false}) {
    return fetchResponseResult<PostModel>(
      key: 'featured',
      state: featured,
      ars: LikeARS(refresh: refresh, skip: !refresh),
      onUpdate: (next) => featured = next, // fetchResponse calls notifyListeners()
      action: (ct, _) => _http
          .get('/posts/featured', cancelToken: ct)
          .mapSync(PostModel.fromJson),
    );
  }

  // Option B: Keyed Map<Object, LikeStateResponse<dynamic>> (keyedResponses)
  LikeStateResponse<PostModel> postSnapshot(String id) =>
      getResponseByKey<PostModel>('post_snapshot:$id');

  Future<void> loadPostSnapshot(String id) {
    return fetchResponseResultByKey<PostModel>(
      key: 'post_snapshot:$id',
      action: (ct, _) => _http
          .get('/posts/$id', cancelToken: ct)
          .mapSync(PostModel.fromJson),
    );
  }
}
```

Render plain `LikeStateResponse<T>` snapshots with `LikeResponseBuilder<T>` or `LikeResponseSliver<T>` (pure `StatelessWidget`s with zero `State` or `ValueNotifier` overhead; `LikeStateResponseBuilder` and `LikeStateResponseBuilderSliver` remain as aliases):

```dart
LikeResponseBuilder<PostModel>(
  response: context.select((ProfileProvider p) => p.featured),
  onLoading: () => const CircularProgressIndicator(),
  onSuccess: (post, isRefreshing, _) => Text(post.title),
  onError: (err) => Text(err.message),
)
```

`toInitState('post_snapshot:42')` resets a single entry in `keyedResponses` (and cancels any in-flight `CancelToken` for that key), while `toInitState()` resets all `keyedStates`, `paginatedStates`, `keyedResponses`, and `keyedPaginatedResponses`.

---

## 5. `LikePaginatedResponse<T>` & `keyedPaginatedResponses` (Any State Management)

`LikePaginatedResponse<T>` is an immutable paginated snapshot (`response`, `loadMoreResponse`, `pagination`, `pageSize`) that works standalone in **Riverpod**, **BLoC/Cubit**, **GetX**, or with `LikeChangeNotifier` + `Provider` / `Selector`:

```dart
class FeedSnapshotProvider extends ChangeNotifier with LikeChangeNotifier {
  final LikeHttpClient _http;
  FeedSnapshotProvider(this._http);

  LikePaginatedResponse<PostModel> get feed =>
      getPaginatedResponseByKey<PostModel>('feed', pageSize: 20);

  Future<void> loadFeed({int page = 1, bool refresh = false}) {
    return fetchPaginatedResponseByKey<PostModel>(
      key: 'feed',
      page: page,
      pageSize: 20,
      refresh: refresh,
      action: (p, limit, ct) => _http
          .get('/posts', query: {'page': p, 'limit': limit}, cancelToken: ct)
          .mapSync((raw) => ...), // returns PaginationTool<PostModel> or List<PostModel>
    );
  }
}
```

Render it with `Selector` + `LikeResponseBuilder`:

```dart
Selector<FeedSnapshotProvider, LikePaginatedResponse<PostModel>>(
  selector: (_, p) => p.feed,
  builder: (context, feedState, _) => LikeResponseBuilder<List<PostModel>>(
    response: feedState.response,
    onLoading: () => const CircularProgressIndicator(),
    onSuccess: (items, isRefreshing, _) => Column(
      children: [
        for (final post in items) Text(post.title),
        if (feedState.isLoadingMore) const CircularProgressIndicator(),
      ],
    ),
  ),
)
```

For cursor pagination, use `fetchPaginatedCursorResponse` / `fetchPaginatedCursorResponseByKey`. For low-level custom orchestration, use `fetcher`, `fetcherResult`, or `paginatedFetcher` (pass `key:` to let `LikeChangeNotifier` manage `CancelToken` rotation automatically, or pass `ct:` and `onRotate:` manually).

---

## 6. Complete `LikeChangeNotifier` API Reference

### Keyed Maps & Accessors

| Member                                          | Purpose                                                          |
| ----------------------------------------------- | ---------------------------------------------------------------- |
| `keyedStates`                                 | Unmodifiable `Map<Object, LikeNotifierState<dynamic>>`         |
| `paginatedStates`                             | Unmodifiable `Map<Object, PaginatedNotifierState<dynamic>>`    |
| `keyedResponses`                              | Unmodifiable `Map<Object, LikeStateResponse<dynamic>>`         |
| `keyedPaginatedResponses`                     | Unmodifiable `Map<Object, LikePaginatedResponse<dynamic>>`     |
| `getByKey<T>(key)`                            | Get or create a `LikeNotifierState<T>` by key                  |
| `getPaginatedByKey<T>(key)`                   | Get or create a `PaginatedNotifierState<T>` by key             |
| `getResponseByKey<T>(key)`                    | Get or initialize a `LikeStateResponse<T>` by key              |
| `setResponseByKey<T>(key, response)`          | Store a `LikeStateResponse<T>` by key and notify listeners     |
| `getPaginatedResponseByKey<T>(key)`           | Get or initialize a `LikePaginatedResponse<T>` by key          |
| `setPaginatedResponseByKey<T>(key, response)` | Store a `LikePaginatedResponse<T>` by key and notify listeners |

### Fetching & Orchestration

| Method                                   | Target Type                                                           |
| ---------------------------------------- | --------------------------------------------------------------------- |
| `fetch<T>`                             | `LikeNotifierState<T>` (returns `LikeStateResponse<T>`)           |
| `fetchResult<T>`                       | `LikeNotifierState<T>` (unwraps `LikeApiResult<T>`)               |
| `fetchResponse<T>`                     | Direct `LikeStateResponse<T>` field via `onUpdate`                |
| `fetchResponseResult<T>`               | Direct `LikeStateResponse<T>` field (unwraps `LikeApiResult<T>`)  |
| `fetchResponseByKey<T>`                | Keyed entry in `keyedResponses`                                     |
| `fetchResponseResultByKey<T>`          | Keyed entry in `keyedResponses` (unwraps `LikeApiResult<T>`)      |
| `fetchPaginatedResponse<T>`            | Direct `LikePaginatedResponse<T>` field (page-based)                |
| `fetchPaginatedResponseByKey<T>`       | Keyed entry in `keyedPaginatedResponses` (page-based)               |
| `fetchPaginatedCursorResponse<T>`      | Direct `LikePaginatedResponse<T>` field (cursor-based)              |
| `fetchPaginatedCursorResponseByKey<T>` | Keyed entry in `keyedPaginatedResponses` (cursor-based)             |
| `fetcher<T>`                           | Low-level orchestrator (`key:` or explicit `ct:` / `onRotate:`) |
| `fetcherResult<T>`                     | Low-level orchestrator unwrapping `LikeApiResult<T>`                |
| `paginatedFetcher<T>`                  | Low-level paginated orchestrator for `LikePaginatedResponse<T>`     |

### Lifecycle & Cancellation

| Method                                     | Purpose                                                                      |
| ------------------------------------------ | ---------------------------------------------------------------------------- |
| `toInitState([key, message])`            | Reset one key (or all keyed/registered states) to `idle` and cancel tokens |
| `cancelTokenNow(cancelToken, [message])` | Cancel a `CancelToken` if active                                           |
| `newCT(cancelToken, [message])`          | Cancel previous `CancelToken` and return a fresh `CancelToken`           |
| `dispose()`                              | Cancel all active tokens and dispose registered states                       |

### Matching UI Builders

| Widget                                                 | Input                                                                 |
| ------------------------------------------------------ | --------------------------------------------------------------------- |
| `LikeNotifierBuilder<T>` / `LikeNotifierSliver<T>` | `LikeNotifierState<T>` (`state:`)                                 |
| `LikeResponseBuilder<T>` / `LikeResponseSliver<T>` | `LikeStateResponse<T>` (`response:`)                              |
| `LikeBuilder<T>` / `LikeSliverBuilder<T>`          | Closure `observe:` (`LikeNotifierState` or `LikeStateResponse`) |
