import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_resync_state.dart';
import 'package:like/src/models/like_sync_task.dart';
import 'package:like/src/models/like_api_result.dart';
import 'package:like/src/helpers/like_pagination.dart';
import 'package:like/src/engine/like_engine.dart';
import 'package:like/src/core/like_ars.dart';

/// A class that encapsulates a [LikeStateResponse] and its associated [CancelToken].
///
/// This eliminates the boilerplate of declaring separate private backing fields,
/// getters, and cancel tokens in providers. Instead, you declare a single
/// final [LikeNotifierState] property and use the new `fetch` method.
class LikeNotifierState<T> extends ChangeNotifier {
  /// The current state response.
  LikeStateResponse<T> _value;

  LikeStateResponse<T> get value => _value;
  set value(LikeStateResponse<T> newValue) {
    if (_value == newValue) return;
    _value = newValue;
    notifyListeners();
  }

  /// The active cancel token for the request.
  CancelToken? ct;

  /// The captured query parameters from the last network request.
  Map<String, dynamic>? activeQuery;

  String? _endpointPath;
  String? _cleanEndpointPath;

  /// Canonical origin of the effective URI used by the last request.
  String? canonicalOrigin;

  LikeResyncState _resyncState = LikeResyncState.idle();

  /// Observable lifecycle of this state's owner-scoped UI resynchronization.
  LikeResyncState get resyncState => _resyncState;

  /// Updates the owner-scoped resynchronization lifecycle.
  ///
  /// This is public for custom lifecycle integrations. Most callers should use
  /// `LikeEngine.triggerResync` and `cancelResync` instead.
  set resyncState(LikeResyncState value) {
    if (identical(_resyncState, value)) return;
    _resyncState = value;
    notifyListeners();
  }

  /// The captured endpoint path from the last network request.
  String? get endpointPath => _endpointPath;
  set endpointPath(String? value) {
    if (_endpointPath == value) return;
    _endpointPath = value;
    if (value != null) {
      if (value.startsWith('http://') || value.startsWith('https://')) {
        final uri = Uri.tryParse(value);
        _cleanEndpointPath = uri != null ? uri.path : value.split('?').first;
      } else {
        _cleanEndpointPath = value.split('?').first;
      }
    } else {
      _cleanEndpointPath = null;
    }
  }

  /// The cached clean endpoint path (without query parameters) for O(1) matching.
  String? get cleanEndpointPath => _cleanEndpointPath;

  /// Whether the notifier state should automatically resync when relevant mutations occur.
  bool autoResync = false;

  /// Whether the notifier state should automatically refetch when its bound screen comes into focus.
  bool refetchOnFocus = false;

  /// The priority queue level to assign during automated background resync.
  LikeSyncPriority syncPriority = LikeSyncPriority.normal;

  /// The stored trigger action to re-run the `fetch` in the background.
  Future<void> Function()? refreshAction;

  /// Optional mapper for automatic pipeline synchronization.
  ///
  /// When provided, the [LikeEngine.fetch] method automatically
  /// registers this state as a pipeline listener. Any response from the same
  /// endpoint broadcast on the [LikePipeline] will be parsed using this mapper
  /// and applied to this state — with no extra configuration needed at the call site.
  final T Function(dynamic json)? mapper;

  LikeNotifierState({
    LikeStateResponse<T>? initialValue,
    this.mapper,
  }) : _value = initialValue ?? LikeStateResponse<T>.idle();

  // Convenience state getters
  bool get isSuccess => value.isSuccess;
  bool get isLoading => value.isLoading;
  bool get isError => value.isError;
  bool get isIdle => value.isIdle;
  bool get isException => value.isException;
  bool get isRefreshing => value.isRefreshing;
  bool get isStaleWhileRevalidate => value.isStaleWhileRevalidate;

  /// Retrieves the current data payload.
  T? get data => value.data;

  /// Retrieves the current descriptive message.
  String get message => value.message;

  /// Retrieves the error payload if in [LikeState.error].
  LikeError? get error => value.error;

  /// Resets the state to idle and cancels any active request.
  void clear({String? message}) {
    ct?.cancel('State cleared');
    ct = null;
    activeQuery = null;
    endpointPath = null;
    canonicalOrigin = null;
    refreshAction = null;
    _resyncState = LikeResyncState.idle();
    value = LikeStateResponse<T>.idle(message: message);
  }

  /// Cancels the active request if running.
  void cancel([String? message]) {
    if (ct != null && !ct!.isCancelled) {
      ct!.cancel(message ?? 'Request cancelled');
    }
    ct = null;
  }
}

/// A convenience alias for [LikeNotifierState].
typedef NotifierState<T> = LikeNotifierState<T>;

/// A specialized [NotifierState] that manages paginated data, cleanly
/// separating the 1st page / initial state from the load-more (pagination) state.
class PaginatedNotifierState<T> extends NotifierState<List<T>> {
  /// Internal pagination state tracker.
  Pagination<T> _pagination;
  Pagination<T> get pagination => _pagination;

  /// A secondary state used exclusively for load-more (2nd page onwards) requests.
  final loadMoreState =
      NotifierState<List<T>>(initialValue: LikeStateResponse.idle());

  /// Deprecated backward-compatibility getter for loadMoreState.
  NotifierState<List<T>> get paginationState => loadMoreState;

  final int pageSize;
  final Future<ApiResult<List<T>>> Function(int page, int limit)? fetcher;

  PaginatedNotifierState({
    this.pageSize = 10,
    this.fetcher,
    super.initialValue,
  }) : _pagination = Pagination<T>() {
    loadMoreState.addListener(notifyListeners);
  }

  @override
  void dispose() {
    loadMoreState.removeListener(notifyListeners);
    loadMoreState.dispose();
    super.dispose();
  }

  /// Whether there are more items available according to pagination metadata or data count.
  bool get hasMore => _pagination.hasMore;

  /// Whether a load-more operation is currently in progress.
  bool get isLoadingMore =>
      loadMoreState.isLoading || loadMoreState.isRefreshing;

  /// Retrieves any load-more error payload if the load-more request failed.
  LikeError? get loadMoreError => loadMoreState.error;

  /// Deprecated alias for loadMoreError.
  LikeError? get paginationError => loadMoreError;

  /// Returns the merged paginated list of items.
  List<T> get items => value.data ?? _pagination.listData ?? const [];

  /// Resets pagination state and data list back to initial state.
  @override
  void clear({String? message}) {
    _pagination = Pagination<T>();
    loadMoreState.clear(message: message);
    super.clear(message: message);
  }

  /// Manually updates pagination state with a new page payload.
  void applyPageData({
    required int page,
    required List<T> data,
    required bool isFirstPage,
    int? totalPages,
    int? totalContent,
    String? cursor,
    String? nextCursor,
    bool? hasNext,
    bool? hasPrevious,
  }) {
    _pagination = _pagination.updatePage(
      page: page,
      limit: pageSize,
      pageData: data,
      append: !isFirstPage,
      totalPages: totalPages,
      totalContent: totalContent,
      cursor: cursor,
      nextCursor: nextCursor,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
    final mergedList = List<T>.unmodifiable(_pagination.listData ?? []);
    value = LikeStateResponse.success(mergedList);
  }

  /// Overwrites/replaces the items belonging to a specific page index [page] with fresh [data],
  /// preserving items from all other previously loaded pages.
  void overwritePageData({
    required int page,
    required List<T> data,
    int? totalPages,
    int? totalContent,
    String? cursor,
    String? nextCursor,
    bool? hasNext,
    bool? hasPrevious,
  }) {
    _pagination = _pagination.overwritePage(
      pageNumber: page,
      limit: pageSize,
      pageData: data,
      totalPages: totalPages,
      totalContent: totalContent,
      cursor: cursor,
      nextCursor: nextCursor,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
    );
    final mergedList = List<T>.unmodifiable(_pagination.listData ?? []);
    value = LikeStateResponse.success(mergedList);
  }

  /// Applies a [Pagination] instance directly to update state.
  void applyPagination(Pagination<T> newPagination, {bool append = false}) {
    final list = newPagination.listData ?? const [];
    if (append && _pagination.listData != null) {
      final combined = [..._pagination.listData!, ...list];
      _pagination = newPagination.copyWith(
        listData: combined,
        currentContent: combined.length,
      );
    } else {
      _pagination = newPagination;
    }
    final mergedList = List<T>.unmodifiable(_pagination.listData ?? []);
    value = LikeStateResponse.success(mergedList);
  }

  /// All-in-one paginated data loader.
  ///
  /// Handles initial loading (page 1), load-more (page > 1), refreshing (clearing data),
  /// overwriting specific pages in-place, state management across primary and secondary states,
  /// and automatic extraction from [PaginationTool] or list payloads.
  Future<void> load({
    required Future<dynamic> Function(int page, int limit) action,
    int page = 1,
    bool refresh = false,
    bool overwrite = false,
    LikeEngine? engine,
    LikeARS? ars,
    List<T> Function(dynamic data)? itemExtractor,
  }) async {
    final isFirstPage = page == 1;

    if (!isFirstPage && !overwrite) {
      if (!hasMore || isLoadingMore) return;
    }

    NotifierState<List<T>> targetStateForPage(int page) =>
        page == 1 ? this : loadMoreState;
    final targetState = targetStateForPage(page);
    final activeEngine = engine ?? LikeEngine();

    final effectiveARS = ars ??
        LikeARS(
          refresh: isFirstPage && (refresh || value.data != null),
          checkAvailability: !isFirstPage,
          visibility: true,
        );

    await activeEngine.fetchResult<List<T>>(
      state: targetState,
      autoResync: isFirstPage,
      ars: effectiveARS,
      action: () async {
        final result = await action(page, pageSize);

        if (result is ApiResult) {
          if (result.isSuccess) {
            final payload = result.data;
            _applyResultPayload(
              payload: payload,
              page: page,
              isFirstPage: isFirstPage,
              overwrite: overwrite,
              itemExtractor: itemExtractor,
            );
            return ApiResult.success(items);
          } else {
            return ApiResult.error(
              result.error ??
                  LikeError(
                    message: 'Could not load page $page',
                    type: LikeApiErrorType.unknown,
                  ),
            );
          }
        }

        _applyResultPayload(
          payload: result,
          page: page,
          isFirstPage: isFirstPage,
          overwrite: overwrite,
          itemExtractor: itemExtractor,
        );
        return ApiResult.success(items);
      },
    );
  }

  /// All-in-one trigger to load the next page.
  Future<void> loadNext({
    required Future<dynamic> Function(int page, int limit) action,
    LikeEngine? engine,
    LikeARS? ars,
    List<T> Function(dynamic data)? itemExtractor,
  }) async {
    if (!hasMore || isLoadingMore) return;
    await load(
      action: action,
      page: _pagination.nextPage,
      engine: engine,
      ars: ars,
      itemExtractor: itemExtractor,
    );
  }

  void _applyResultPayload({
    required dynamic payload,
    required int page,
    required bool isFirstPage,
    required bool overwrite,
    List<T> Function(dynamic data)? itemExtractor,
  }) {
    if (payload is PaginationTool<T>) {
      if (overwrite) {
        overwritePageData(
          page: page,
          data: payload.items ?? const [],
          totalPages: payload.totalPages,
          totalContent: payload.totalContent,
          cursor: payload.cursor,
          nextCursor: payload.nextCursor,
          hasNext: payload.hasNextOverride,
          hasPrevious: payload.hasPreviousOverride,
        );
      } else {
        applyPageData(
          page: page,
          data: payload.items ?? const [],
          isFirstPage: isFirstPage,
          totalPages: payload.totalPages,
          totalContent: payload.totalContent,
          cursor: payload.cursor,
          nextCursor: payload.nextCursor,
          hasNext: payload.hasNextOverride,
          hasPrevious: payload.hasPreviousOverride,
        );
      }
    } else if (payload is List<T>) {
      if (overwrite) {
        overwritePageData(page: page, data: payload);
      } else {
        applyPageData(page: page, data: payload, isFirstPage: isFirstPage);
      }
    } else if (itemExtractor != null) {
      final extracted = itemExtractor(payload);
      if (overwrite) {
        overwritePageData(page: page, data: extracted);
      } else {
        applyPageData(page: page, data: extracted, isFirstPage: isFirstPage);
      }
    }
  }

  /// Fetches the first page using the primary [value] state.
  Future<void> fetchInitial({
    required LikeEngine engine,
    LikeARS? ars,
    bool autoResync = false,
    LikeSyncPriority priority = LikeSyncPriority.normal,
    bool disableRequestCancellation = false,
  }) async {
    assert(
        fetcher != null, 'Fetcher must be provided to fetchInitial directly');
    if (fetcher == null) return;

    await engine.fetchResult<List<T>>(
      state: this,
      ars: ars ?? const LikeARS(refresh: true),
      autoResync: autoResync,
      priority: priority,
      disableRequestCancellation: disableRequestCancellation,
      action: () async {
        final result = await fetcher!(1, pageSize);
        return result.mapSuccess((data) {
          applyPageData(
            page: 1,
            data: data,
            isFirstPage: true,
          );
          return value.data ?? [];
        });
      },
    );
  }

  /// Fetches the next page using the secondary [loadMoreState].
  Future<void> fetchNextPage({
    required LikeEngine engine,
    LikeARS? ars,
  }) async {
    assert(
        fetcher != null, 'Fetcher must be provided to fetchNextPage directly');
    if (fetcher == null ||
        !hasMore ||
        isLoadingMore ||
        isLoading ||
        isRefreshing) {
      return;
    }

    final nextPage = _pagination.nextPage;

    await engine.fetchResult<List<T>>(
      state: loadMoreState,
      ars: ars ?? const LikeARS(checkAvailability: true, visibility: true),
      action: () async {
        final result = await fetcher!(nextPage, pageSize);
        return result.mapSuccess((data) {
          applyPageData(
            page: nextPage,
            data: data,
            isFirstPage: false,
          );
          return data;
        });
      },
    );
  }
}
