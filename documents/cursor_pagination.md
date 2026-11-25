# Cursor Pagination & Load-More with `PaginatedNotifierState`

This guide shows how to wire cursor-based pagination and load-more UI states using `PaginatedNotifierState<T>` and `PaginationTool<T>` when your API:

- **Accepts** `cursor` (optional on the first page) and `limit` as inputs.
- **Returns** `currentCursor`, `nextCursor`, a `loadMore` boolean, and the page `items`.

---

## 1. Model the API response with `PaginationTool<T>`

Extend `PaginationTool<T>` in your response model and map:

- `cursor` ← API's current cursor
- `nextCursor` ← API's next cursor
- `hasNextOverride` ← API's `loadMore` boolean
- `cursorBased: true`
- `listData` ← parsed items list

```dart
import 'package:like/like.dart';

class PostItem {
  final String id;
  final String title;

  const PostItem({required this.id, required this.title});

  factory PostItem.fromJson(Map<String, dynamic> json) => PostItem(
    id: json['id'].toString(),
    title: json['title'] as String? ?? '',
  );
}

class CursorPostsResponse extends PaginationTool<PostItem> {
  const CursorPostsResponse({
    required super.listData,
    super.cursor,
    super.nextCursor,
    super.hasNextOverride,
    super.contentLimit,
  }) : super(cursorBased: true);

  factory CursorPostsResponse.fromJson(dynamic raw) {
    final json = raw as Map<String, dynamic>;
    final rawItems = (json['items'] as List? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(PostItem.fromJson)
        .toList(growable: false);

    return CursorPostsResponse(
      listData: rawItems,
      cursor: json['currentCursor'] as String?,
      nextCursor: json['nextCursor'] as String?,
      hasNextOverride: json['loadMore'] as bool?,
      contentLimit: json['limit'] as int?,
    );
  }
}
```

> **Note:** Setting `hasNextOverride` to your API's `loadMore` boolean makes `hasMore` use that flag directly. If `nextCursor` repeats `cursor`, `PaginatedNotifierState` automatically stops pagination to prevent infinite loops.

---

## 2. Create the Service & State Holder

Pass `cursor` (when non-null) and `limit` to `LikeClient().get(...)`, and manage both the main list and load-more footer state in `PaginatedNotifierState<PostItem>`:

```dart
import 'package:flutter/foundation.dart';
import 'package:like/like.dart';

class PostFeedController extends ChangeNotifier {
  final LikeHttpClient _http;
  final PaginatedNotifierState<PostItem> feedState =
      PaginatedNotifierState<PostItem>(pageSize: 20);

  PostFeedController(this._http) {
    feedState.addListener(notifyListeners);
  }

  Future<ApiResult<CursorPostsResponse>> _fetchPage(
    String? cursor,
    int limit,
  ) {
    return _http
        .get(
          '/posts',
          query: <String, dynamic>{
            'limit': limit,
            if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
          },
        )
        .mapSync(CursorPostsResponse.fromJson);
  }

  /// Initial load or pull-to-refresh (resets cursor to null).
  Future<void> loadInitial({bool refresh = false}) {
    return feedState.loadCursor(
      refresh: refresh,
      action: (cursor, limit) => _fetchPage(cursor, limit),
    );
  }

  /// Appends the next slice using `feedState.nextCursor`.
  /// Automatically no-ops if `!feedState.hasMore` or `feedState.isLoadingMore`.
  Future<void> loadMore() {
    return feedState.loadNextCursor(
      action: (cursor, limit) => _fetchPage(cursor, limit),
    );
  }

  @override
  void dispose() {
    feedState.removeListener(notifyListeners);
    feedState.dispose();
    super.dispose();
  }
}
```

### Useful getters on `PaginatedNotifierState`

| Getter | Purpose |
| --- | --- |
| `feedState.items` | Unmodifiable merged list of all loaded pages |
| `feedState.currentCursor` | Cursor of the most recently loaded page |
| `feedState.nextCursor` | Cursor token for the next page |
| `feedState.hasMore` | `true` when `loadMore` / `nextCursor` indicates another page |
| `feedState.isLoadingMore` | `true` while `loadMoreState` is loading or refreshing |
| `feedState.loadMoreError` | `LikeError` from a failed load-more call (without clearing existing items) |
| `feedState.loadMoreState` | `NotifierState<List<T>>` dedicated to footer loading/error UI |

---

## 3. Render List + Load-More Footer in Flutter

`PaginatedNotifierState` keeps page 1 in `feedState` and page 2+ in `feedState.loadMoreState`, so a failed load-more never wipes out already-loaded items.

```dart
import 'package:flutter/material.dart';
import 'package:like/like.dart';

class PostFeedScreen extends StatefulWidget {
  final PostFeedController controller;

  const PostFeedScreen({super.key, required this.controller});

  @override
  State<PostFeedScreen> createState() => _PostFeedScreenState();
}

class _PostFeedScreenState extends State<PostFeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.loadInitial();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 250) {
      widget.controller.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feed = widget.controller.feedState;

    return RefreshIndicator(
      onRefresh: () => widget.controller.loadInitial(refresh: true),
      child: LikeBuilder<List<PostItem>>(
        observe: () => feed,
        onLoading: () => const Center(child: CircularProgressIndicator()),
        onError: (error) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error.message),
              ElevatedButton(
                onPressed: () => widget.controller.loadInitial(refresh: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        onSuccess: (items, isRefreshing, isSWR) {
          return ListView.builder(
            controller: _scrollController,
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index < items.length) {
                final item = items[index];
                return ListTile(title: Text(item.title));
              }

              // Footer driven by feed.loadMoreState
              return LikeBuilder<List<PostItem>>(
                observe: () => feed.loadMoreState,
                onIdle: () => feed.hasMore
                    ? TextButton(
                        onPressed: widget.controller.loadMore,
                        child: const Text('Load more'),
                      )
                    : const SizedBox.shrink(),
                onLoading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                onError: (error) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: widget.controller.loadMore,
                    child: Text('Load more failed (${error.message}). Tap to retry'),
                  ),
                ),
                onSuccess: (_, _, _) => feed.hasMore
                    ? TextButton(
                        onPressed: widget.controller.loadMore,
                        child: const Text('Load more'),
                      )
                    : const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: Text('End of feed')),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
```
