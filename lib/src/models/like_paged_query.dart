import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/helpers/like_pagination.dart';
import 'like_api_result.dart';
import 'like_error.dart';

class LikePageSnapshot<T> {
  final List<T> items;
  final bool loading;
  final bool hasMore;
  final int page;
  final int? failedPage;
  final LikeError? error;
  LikePageSnapshot(
      {Iterable<T> items = const [],
      this.loading = false,
      this.hasMore = true,
      this.page = 0,
      this.failedPage,
      this.error})
      : items = List.unmodifiable(items);
}

/// Page storage remains separate from the de-duplicated view, so replacing a page
/// cannot shift another page's offsets. Failed pages retain their cursor for retry.
class LikePagedQuery<T> extends ValueNotifier<LikePageSnapshot<T>> {
  final Future<LikeApiResult<PaginationTool<T>>> Function(
      int page, String? cursor, CancelToken token) action;
  final Object Function(T) identity;
  final int pageSize;
  final Map<int, List<T>> _pages = {};
  final Map<int, String?> _cursors = {};
  CancelToken? _token;
  int _epoch = 0;
  bool _disposed = false;
  String? _nextCursor;
  LikePagedQuery(
      {required this.action, required this.identity, this.pageSize = 20})
      : super(LikePageSnapshot<T>());

  Future<void> refresh() {
    _epoch++;
    _token?.cancel('Pagination refreshed');
    return _load(1, null, refresh: true);
  }

  Future<void> loadNext() {
    if (_disposed || value.loading || !value.hasMore)
      { return Future<void>.value(); }
    return _load(value.page + 1, _nextCursor);
  }

  Future<void> retryFailedPage() {
    final page = value.failedPage;
    if (page == null || value.loading || _disposed) return Future<void>.value();
    return _load(page, _cursors[page], refresh: page == 1);
  }

  List<T> _items() {
    final unique = <Object, T>{};
    final pages = _pages.keys.toList()..sort();
    for (final page in pages) {
      for (final item in _pages[page]!) {
        unique[identity(item)] = item;
      }
    }
    return unique.values.toList(growable: false);
  }

  Future<void> _load(int page, String? cursor, {bool refresh = false}) async {
    if (_disposed) return;
    final epoch = _epoch;
    final token = CancelToken();
    _token = token;
    _cursors[page] = cursor;
    value = LikePageSnapshot(
        items: value.items,
        page: value.page,
        hasMore: value.hasMore,
        loading: true);
    try {
      final result = await action(page, cursor, token);
      if (_disposed || epoch != _epoch || token.isCancelled) return;
      if (!result.isSuccess || result.data == null) {
        value = LikePageSnapshot(
            items: value.items,
            page: value.page,
            hasMore: value.hasMore,
            failedPage: page,
            error: result.error);
        return;
      }
      final data = result.data!;
      if (refresh) _pages.clear();
      _pages[page] = data.items ?? const [];
      _nextCursor = data.nextCursor;
      final cursorMode = data.cursorBased ||
          cursor != null ||
          data.cursor != null ||
          data.nextCursor != null;
      var more = data.hasNextOverride ??
          (cursorMode
              ? data.hasMoreByCursor
              : data.totalPages != null
                  ? page < data.totalPages!
                  : data.totalContent != null
                      ? page * pageSize < data.totalContent!
                      : (data.items?.length ?? 0) >= pageSize);
      if (cursorMode && _nextCursor == cursor) more = false;
      value = LikePageSnapshot(items: _items(), page: page, hasMore: more);
    } catch (_) {
      if (!_disposed && epoch == _epoch && !token.isCancelled) {
        value = LikePageSnapshot(
            items: value.items,
            page: value.page,
            hasMore: value.hasMore,
            failedPage: page,
            error: LikeError(
                message: 'Page request failed',
                type: LikeApiErrorType.unknown));
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _token?.cancel('Pagination disposed');
    super.dispose();
  }
}
