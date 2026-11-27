import 'package:flutter/foundation.dart';
import 'package:like/src/helpers/like_pagination.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_state_response.dart';

/// Immutable paginated state snapshot that can be managed by any state
/// management solution (Provider, Riverpod, BLoC/Cubit, GetX, MobX, or
/// [LikeChangeNotifier]).
///
/// Pairs a primary [response] (`LikeStateResponse<List<T>>`), a secondary
/// [loadMoreResponse] for incremental page/cursor loads, and [pagination]
/// metadata ([PaginationTool<T>]).
class LikePaginatedResponse<T> {
  /// Primary lifecycle state for the paginated list (first page / merged items).
  final LikeStateResponse<List<T>> response;

  /// Secondary lifecycle state for load-more (page > 1 or next-cursor) requests.
  final LikeStateResponse<List<T>> loadMoreResponse;

  /// Page and cursor metadata along with accumulated items.
  final PaginationTool<T> pagination;

  /// Default page size used for pagination calculations.
  final int pageSize;

  const LikePaginatedResponse({
    required this.response,
    this.loadMoreResponse = const LikeStateResponse<List<Never>>(
      state: LikeState.idle,
      message: 'Idle',
    ),
    this.pagination = const PaginationTool(),
    this.pageSize = 10,
  });

  /// Creates an initial `idle` paginated snapshot.
  factory LikePaginatedResponse.idle({
    int pageSize = 10,
    String message = 'Idle',
  }) {
    return LikePaginatedResponse<T>(
      response: LikeStateResponse<List<T>>.idle(message: message),
      loadMoreResponse: LikeStateResponse<List<T>>.idle(),
      pagination: PaginationTool<T>(),
      pageSize: pageSize,
    );
  }

  /// Creates an initial `loading` paginated snapshot.
  factory LikePaginatedResponse.loading({
    int pageSize = 10,
    String message = 'Loading...',
  }) {
    return LikePaginatedResponse<T>(
      response: LikeStateResponse<List<T>>.loading(message: message),
      loadMoreResponse: LikeStateResponse<List<T>>.idle(),
      pagination: PaginationTool<T>(),
      pageSize: pageSize,
    );
  }

  /// Current primary lifecycle state.
  LikeState get state => response.state;

  /// Merged list of loaded items across all fetched pages.
  List<T> get items => response.data ?? pagination.listData ?? const [];

  bool get isIdle => response.isIdle;
  bool get isLoading => response.isLoading;
  bool get isRefreshing => response.isRefreshing;
  bool get isSuccess => response.isSuccess;
  bool get isError => response.isError;
  bool get isException => response.isException;
  bool get hasData => items.isNotEmpty;
  LikeError? get error => response.error;

  /// Whether there are more pages or cursor items available.
  bool get hasMore => pagination.hasMore;

  /// Current resolved 1-based page index.
  int get currentPage => pagination.resolvedPage;

  /// Total pages reported by the API, if any.
  int? get totalPages => pagination.totalPages;

  /// Total items reported by the API, if any.
  int? get totalContent => pagination.totalContent;

  /// Current cursor used for the most recently loaded page, if any.
  String? get currentCursor => pagination.cursor;

  /// Cursor token to request the next page, if any.
  String? get nextCursor => pagination.nextCursor;

  /// Whether this paginated response is operating in cursor-based mode.
  bool get isCursorMode => pagination.isCursorMode;

  /// Whether a load-more operation is currently in progress.
  bool get isLoadingMore =>
      loadMoreResponse.isLoading || loadMoreResponse.isRefreshing;

  /// Error from the most recent load-more request, if any.
  LikeError? get loadMoreError => loadMoreResponse.error;

  /// Returns a copy with overridden fields.
  LikePaginatedResponse<T> copyWith({
    LikeStateResponse<List<T>>? response,
    LikeStateResponse<List<T>>? loadMoreResponse,
    PaginationTool<T>? pagination,
    int? pageSize,
  }) {
    return LikePaginatedResponse<T>(
      response: response ?? this.response,
      loadMoreResponse: loadMoreResponse ?? this.loadMoreResponse,
      pagination: pagination ?? this.pagination,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  /// Resets this paginated snapshot back to `idle`.
  LikePaginatedResponse<T> toInitState({String? message}) {
    return LikePaginatedResponse<T>.idle(
      pageSize: pageSize,
      message: message ?? 'Idle',
    );
  }

  /// Transitions either the primary [response] (`page == 1` and not `overwrite`)
  /// or [loadMoreResponse] into a loading/refreshing state.
  LikePaginatedResponse<T> startLoad({
    int page = 1,
    bool refresh = false,
    bool overwrite = false,
  }) {
    final isFirstPage = page == 1 && !overwrite;
    if (isFirstPage) {
      if ((refresh || response.data != null) && items.isNotEmpty) {
        return copyWith(
          response: LikeStateResponse<List<T>>.refreshing(items),
          loadMoreResponse: LikeStateResponse<List<T>>.idle(),
        );
      }
      return copyWith(
        response: LikeStateResponse<List<T>>.loading(),
        loadMoreResponse: LikeStateResponse<List<T>>.idle(),
      );
    }
    return copyWith(
      loadMoreResponse: LikeStateResponse<List<T>>.loading(),
    );
  }

  /// Applies a page-based [payload] (`PaginationTool<T>`, `List<T>`, `List`, or
  /// `Map` with [itemExtractor]) and returns the updated immutable snapshot.
  LikePaginatedResponse<T> applyPayload({
    required dynamic payload,
    int page = 1,
    bool overwrite = false,
    List<T> Function(dynamic data)? itemExtractor,
  }) {
    final isFirstPage = page == 1;
    final extracted = _extractPagination(
      payload: payload,
      page: page,
      itemExtractor: itemExtractor,
    );

    final PaginationTool<T> nextPagination;
    if (overwrite) {
      nextPagination = pagination.overwritePage(
        pageNumber: page,
        limit: extracted.contentLimit ?? pageSize,
        pageData: extracted.items,
        totalPages: extracted.totalPages,
        totalContent: extracted.totalContent,
        cursor: extracted.cursor,
        nextCursor: extracted.nextCursor,
        hasNext: extracted.hasNext,
        hasPrevious: extracted.hasPrevious,
      );
    } else {
      nextPagination = pagination.updatePage(
        page: page,
        limit: extracted.contentLimit ?? pageSize,
        pageData: extracted.items,
        append: !isFirstPage,
        totalPages: extracted.totalPages,
        totalContent: extracted.totalContent,
        cursor: extracted.cursor,
        nextCursor: extracted.nextCursor,
        hasNext: extracted.hasNext,
        hasPrevious: extracted.hasPrevious,
      );
    }

    final merged = List<T>.unmodifiable(nextPagination.listData ?? const []);
    return copyWith(
      response: LikeStateResponse<List<T>>.success(merged),
      loadMoreResponse: (isFirstPage && !overwrite)
          ? LikeStateResponse<List<T>>.idle()
          : LikeStateResponse<List<T>>.success(merged),
      pagination: nextPagination,
    );
  }

  /// Applies a cursor-based [payload] (`PaginationTool<T>`, `List<T>`, `List`,
  /// or `Map` with [itemExtractor]) and returns the updated immutable snapshot.
  LikePaginatedResponse<T> applyCursorPayload({
    required dynamic payload,
    bool refresh = false,
    List<T> Function(dynamic data)? itemExtractor,
  }) {
    final extracted = _extractPagination(
      payload: payload,
      page: refresh ? 1 : pagination.resolvedPage + 1,
      itemExtractor: itemExtractor,
    );

    final nextPagination = pagination.updateCursor(
      pageData: extracted.items,
      append: !refresh,
      cursor: extracted.cursor,
      nextCursor: extracted.nextCursor,
      limit: extracted.contentLimit ?? pageSize,
      totalContent: extracted.totalContent,
      hasNext: extracted.hasNext,
      hasPrevious: extracted.hasPrevious,
    );

    final merged = List<T>.unmodifiable(nextPagination.listData ?? const []);
    return copyWith(
      response: LikeStateResponse<List<T>>.success(merged),
      loadMoreResponse: refresh
          ? LikeStateResponse<List<T>>.idle()
          : LikeStateResponse<List<T>>.success(merged),
      pagination: nextPagination,
    );
  }

  /// Transitions either [response] or [loadMoreResponse] into an error state,
  /// preserving previously loaded [items] for load-more failures.
  LikePaginatedResponse<T> applyError(LikeError error, {int page = 1}) {
    if (page == 1) {
      return copyWith(response: LikeStateResponse<List<T>>.error(error));
    }
    return copyWith(
      loadMoreResponse: LikeStateResponse<List<T>>.error(error),
    );
  }

  /// Transitions either [response] or [loadMoreResponse] into an exception state.
  LikePaginatedResponse<T> applyException(
    String message, {
    Object? error,
    int page = 1,
  }) {
    final exceptionResponse = LikeStateResponse<List<T>>.exception(
      message,
      error: error,
    );
    if (page == 1) {
      return copyWith(response: exceptionResponse);
    }
    return copyWith(loadMoreResponse: exceptionResponse);
  }

  _ExtractedPage<T> _extractPagination({
    required dynamic payload,
    required int page,
    List<T> Function(dynamic data)? itemExtractor,
  }) {
    if (payload is PaginationTool<T>) {
      return _ExtractedPage<T>(
        items: payload.listData ?? const [],
        totalPages: payload.totalPages,
        totalContent: payload.totalContent,
        contentLimit: payload.contentLimit,
        cursor: payload.cursor,
        nextCursor: payload.nextCursor,
        hasNext: payload.hasNextOverride,
        hasPrevious: payload.hasPreviousOverride,
      );
    }

    if (payload is List<T>) {
      return _ExtractedPage<T>(items: payload);
    }

    if (payload is List) {
      return _ExtractedPage<T>(
        items: itemExtractor != null
            ? itemExtractor(payload)
            : payload.cast<T>(),
      );
    }

    if (payload is Map<String, dynamic>) {
      final rawItems = payload['items'] ?? payload['data'] ?? payload['results'];
      final extractedItems = itemExtractor != null
          ? itemExtractor(rawItems ?? payload)
          : (rawItems is List ? rawItems.cast<T>() : <T>[]);
      return _ExtractedPage<T>(
        items: extractedItems,
        totalPages: (payload['totalPages'] ?? payload['total_pages']) as int?,
        totalContent:
            (payload['totalContent'] ??
                    payload['total_content'] ??
                    payload['total'])
                as int?,
        contentLimit:
            (payload['contentLimit'] ?? payload['limit'] ?? payload['per_page'])
                as int?,
        cursor: (payload['currentCursor'] ?? payload['cursor']) as String?,
        nextCursor: (payload['nextCursor'] ?? payload['next_cursor']) as String?,
        hasNext: (payload['hasNext'] ?? payload['has_next']) as bool?,
        hasPrevious:
            (payload['hasPrevious'] ?? payload['has_previous']) as bool?,
      );
    }

    if (itemExtractor != null) {
      return _ExtractedPage<T>(items: itemExtractor(payload));
    }

    return _ExtractedPage<T>(items: const []);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LikePaginatedResponse<T> &&
        other.response == response &&
        other.loadMoreResponse == loadMoreResponse &&
        other.pageSize == pageSize &&
        other.pagination.resolvedPage == pagination.resolvedPage &&
        other.pagination.nextCursor == pagination.nextCursor &&
        other.pagination.hasMore == pagination.hasMore &&
        listEquals(other.items, items);
  }

  @override
  int get hashCode => Object.hash(
    response,
    loadMoreResponse,
    pageSize,
    pagination.resolvedPage,
    pagination.nextCursor,
    pagination.hasMore,
    Object.hashAll(items),
  );
}

class _ExtractedPage<T> {
  final List<T> items;
  final int? totalPages;
  final int? totalContent;
  final int? contentLimit;
  final String? cursor;
  final String? nextCursor;
  final bool? hasNext;
  final bool? hasPrevious;

  const _ExtractedPage({
    required this.items,
    this.totalPages,
    this.totalContent,
    this.contentLimit,
    this.cursor,
    this.nextCursor,
    this.hasNext,
    this.hasPrevious,
  });
}
