# `LikeChangeNotifier` Guide: Custom Models & Custom Maps

`LikeChangeNotifier` is a lightweight `ChangeNotifier` mixin for individual `fetch` / `fetchResult` / `fetchResponse` / `fetchResponseResult` / `fetcher` calls with automatic `CancelToken` rotation, silent cancellation handling, `ars.skip`, keyed state maps (`keyedStates` / `paginatedStates` / `keyedResponses`), and `.toInitState()`.

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

  // 1. Custom model state by key
  LikeNotifierState<PostModel> postState(String postId) =>
      getByKey<PostModel>('post:$postId');

  // 2. Custom Map state by key (e.g. dashboard counters or grouped items)
  LikeNotifierState<Map<String, dynamic>> get statsMapState =>
      getByKey<Map<String, dynamic>>('dashboard_stats');

  LikeNotifierState<Map<String, List<PostModel>>> get groupedPostsState =>
      getByKey<Map<String, List<PostModel>>>('grouped_posts');

  // 3. Paginated custom model state by key
  PaginatedNotifierState<PostModel> feedState(String category) =>
      getPaginatedByKey<PostModel>('feed:$category', pageSize: 20);

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

```dart
// Observing a custom model by key
LikeBuilder<PostModel>(
  observe: () => provider.postState('42'),
  onLoading: () => const CircularProgressIndicator(),
  onSuccess: (post, isRefreshing, _) => Text(post.title),
  onError: (err) => Text(err.message),
)

// Observing a custom Map by key
LikeBuilder<Map<String, dynamic>>(
  observe: () => provider.statsMapState,
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

Render plain `LikeStateResponse<T>` snapshots with `LikeStateResponseBuilder<T>` (or `LikeBuilder<T>` with optional `buildWhen` / `selector` for selective rebuilds):

```dart
LikeStateResponseBuilder<PostModel>(
  response: context.select((ProfileProvider p) => p.featured),
  onLoading: () => const CircularProgressIndicator(),
  onSuccess: (post, isRefreshing, _) => Text(post.title),
  onError: (err) => Text(err.message),
)
```

`toInitState('post_snapshot:42')` resets a single entry in `keyedResponses` (and cancels any in-flight `CancelToken` for that key), while `toInitState()` resets all `keyedStates`, `paginatedStates`, and `keyedResponses`.
