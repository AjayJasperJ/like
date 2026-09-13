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

/// A specialized [NotifierState] that manages paginated data, completely
/// hiding pagination math, list merging, and pagination state from the Provider.
class PaginatedNotifierState<T> extends NotifierState<List<T>> {
  /// Internal pagination state tracker
  Pagination<T> _pagination;
  Pagination<T> get pagination => _pagination;
  
  /// A secondary state used exclusively for the bottom loader (loading more).
  final paginationState = NotifierState<List<T>>(initialValue: LikeStateResponse.idle());

  final int pageSize;
  final Future<ApiResult<List<T>>> Function(int page, int limit) fetcher;

  PaginatedNotifierState({
    this.pageSize = 10,
    required this.fetcher,
    super.initialValue,
  })  : _pagination = Pagination<T>() {
    paginationState.addListener(notifyListeners);
  }
  
  @override
  void dispose() {
    paginationState.removeListener(notifyListeners);
    paginationState.dispose();
    super.dispose();
  }

  /// Exposes whether we have more data to fetch.
  bool get hasMore => _pagination.hasMore;
  
  /// Check if pagination is currently loading
  bool get isLoadingMore => paginationState.isLoading || paginationState.isRefreshing;
  
  /// Check if pagination failed
  LikeError? get paginationError => paginationState.error;

  /// Fetch the first page. Uses the primary [value] state.
  Future<void> fetchInitial({
    required LikeEngine engine,
    LikeARS? ars,
    bool autoResync = false,
    LikeSyncPriority priority = LikeSyncPriority.normal,
    bool disableRequestCancellation = false,
  }) async {
    await engine.fetchResult<List<T>>(
      state: this,
      ars: ars ?? const LikeARS(refresh: true),
      autoResync: autoResync,
      priority: priority,
      disableRequestCancellation: disableRequestCancellation,
      action: () async {
        final result = await fetcher(1, pageSize);
        
        return result.mapSuccess((data) {
          _pagination = _pagination.updatePage(
            page: 1,
            limit: pageSize,
            pageData: data,
            append: false,
          );
          return _pagination.listData ?? [];
        });
      },
    );
  }

  /// Fetch the next page. Uses the secondary [paginationState].
  Future<void> fetchNextPage({
    required LikeEngine engine,
    LikeARS? ars,
  }) async {
    if (!hasMore || isLoadingMore || isLoading || isRefreshing) {
      return;
    }
    
    final nextPage = _pagination.nextPage;
    
    await engine.fetchResult<List<T>>(
      state: paginationState,
      ars: ars ?? const LikeARS(checkAvailability: true, visibility: true),
      action: () async {
        final result = await fetcher(nextPage, pageSize);
        
        return result.mapSuccess((data) {
          _pagination = _pagination.updatePage(
            page: nextPage,
            limit: pageSize,
            pageData: data,
            append: true,
          );
          
          // Note: we update the primary state's value silently here so UI updates
          value = LikeStateResponse.success(_pagination.listData ?? []);
          
          return _pagination.listData ?? [];
        });
      },
    );
  }
}
