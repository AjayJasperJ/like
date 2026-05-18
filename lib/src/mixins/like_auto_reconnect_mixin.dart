import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_ars.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_sync_event.dart';
import 'package:like/src/client/like_client.dart';
import 'package:like/src/services/like_sync_manager.dart';
import 'package:like/src/models/like_sync_task.dart';

/// A mixin that provides automatic reconnection and synchronization logic for Notifiers.
/// Features a declarative [syncWith] API for intelligent data refreshes.
/// Matches the exact logic and contract of enterprise's AutoReconnectMixin.
mixin LikeAutoReconnectMixin on ChangeNotifier {
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<LikeSyncEvent>? _syncSubscription;
  final Set<_LikeGranularSyncTask> _granularTasks = {};
  final Set<LikeNotifierState<dynamic>> _registeredStates = {};
  bool _isDisposed = false;

  /// Hook for legacy reconnection logic.
  Future<void> onReconnect() async {}

  /// Hook for manual refresh signals.
  void onAutoRefresh(String path) {}

  /// Whether the provider is in a state that requires a retry/sync.
  bool get shouldRetry => false;

  /// Default priority for sync tasks from this provider.
  LikeSyncPriority get syncPriority => LikeSyncPriority.critical;

  /// Initializes the auto-reconnect and synchronization logic.
  ///
  /// If [registerInitialTask] is true, a critical sync task is registered immediately
  /// to ensure data is fetched upon initialization if needed.
  void initAutoReconnect({bool registerInitialTask = false}) {
    if (registerInitialTask) {
      LikeSyncManager().registerTask(
        _LikeProviderSyncTask(this, isInitial: true),
      );
    }

    _refreshSubscription = LikeClient().refreshStream.listen((path) {
      // Handle global reconnection signals
      if (path == 'reconnected') {
        LikeSyncManager().registerTask(_LikeProviderSyncTask(this));
        return;
      }

      // 1. Legacy support
      onAutoRefresh(path);

      // 2. Automated syncWith support
      for (final task in _granularTasks) {
        if (task.endpoint != null) {
          // Extract path for matching
          final incomingPath = path.contains(':') ? path.split(':').last : path;
          final cleanPath = incomingPath.split('?').first;

          if (cleanPath == task.endpoint! ||
              (cleanPath.startsWith(task.endpoint!) &&
                  cleanPath[task.endpoint!.length] == '/')) {
            if (task.condition()) {
              LikeSyncManager().registerTask(task);
            }
          }
        }
      }
    });

    _syncSubscription = LikeClient().syncStream.listen((event) {
      for (final state in _registeredStates) {
        if (state.autoResync &&
            state.endpointPath != null &&
            state.refreshAction != null) {
          final cleanPath = event.path.split('?').first;
          final statePath = state.endpointPath!.split('?').first;

          if (cleanPath == statePath ||
              (cleanPath.startsWith(statePath) &&
                  cleanPath[statePath.length] == '/')) {
            final overlap = checkQueryOverlap(
              state.activeQuery ?? const {},
              event.payload,
            );
            if (overlap) {
              final isSuccess =
                  state.value.isSuccess ||
                  state.value.isRefreshing ||
                  state.value.isStaleWhileRevalidate;
              if (isSuccess) {
                LikeSyncManager().registerTask(_LikeStateSyncTask(state));
              }
            }
          }
        }
      }
    });
  }

  /// Registers a specific API call to be automatically refreshed when its data source updates.
  ///
  /// This is the preferred declarative way to handle cross-notifier synchronization.
  /// When any provider notifies a refresh for the given [endpoint], this [action]
  /// will be triggered if the [condition] (defaults to success or retryable error) is met.
  void syncWith<T>({
    required String endpoint,
    required Future<void> Function() action,
    required ValueGetter<LikeStateResponse<T>> state,
    required ValueGetter<CancelToken?> cancelToken,
    LikeSyncPriority priority = LikeSyncPriority.normal,
  }) {
    if (_refreshSubscription == null && _syncSubscription == null) {
      initAutoReconnect();
    }

    final task = _LikeGranularSyncTask(
      providerId: runtimeType.toString(),
      endpoint: endpoint,
      priority: priority,
      action: action,
      condition: () =>
          state().isSuccess || regularRetry(state(), cancelToken()),
      recoveryCondition: () => regularRetry(state(), cancelToken()),
    );
    _granularTasks.add(task);

    if (task.condition()) {
      LikeSyncManager().registerTask(task);
    }
  }

  /// Declarative synchronization using [LikeNotifierState].
  ///
  /// Automatically extracts the state response and cancel token from [state].
  void syncWithState<T>({
    required String endpoint,
    required Future<void> Function() action,
    required LikeNotifierState<T> state,
    LikeSyncPriority priority = LikeSyncPriority.normal,
  }) {
    syncWith<T>(
      endpoint: endpoint,
      action: action,
      state: () => state.value,
      cancelToken: () => state.ct,
      priority: priority,
    );
  }

  /// Helper to determine if a state requires a refresh (error, exception, or resiliency fallback).
  ///
  /// Returns true if the state indicates a failure or that cached data is being
  /// shown as a temporary fallback, and the [cancelToken] has not been cancelled.
  bool regularRetry(LikeStateResponse? state, CancelToken? cancelToken) {
    if (state == null || state.isIdle) return false;

    // A state needs refresh if it's an explicit error/exception,
    // OR if it's a success but served as a resiliency fallback (failed but showing cache).
    bool needsRefresh =
        state.isError || state.isException || state.isResiliencyFallback;

    if (cancelToken == null) return needsRefresh;
    return needsRefresh && !cancelToken.isCancelled;
  }

  /// Cancels the provided [cancelToken] if it is currently active.
  void cancelTokenNow(CancelToken? cancelToken, String? message) {
    if (cancelToken?.isCancelled == false && cancelToken != null) {
      cancelToken.cancel(message ?? 'Request cancelled');
    }
  }

  /// Rotates the [cancelToken] by cancelling the old one and returning a new instance.
  CancelToken newCT(CancelToken? cancelToken) {
    cancelTokenNow(cancelToken, 'Old Request cancelled');
    return CancelToken();
  }

  /// An optimized state execution wrapper that manages the lifecycle of a [LikeNotifierState].
  ///
  /// This eliminates the need to manually pass:
  /// * `ct`
  /// * `onRotate` callback
  /// * `onUpdate` callback
  ///
  /// It automatically registers the state for auto-cancellation when this mixin is disposed.
  Future<LikeStateResponse<T>> fetch<T>({
    required LikeNotifierState<T> state,
    LikeARS? ars,
    bool autoResync = false,
    LikeSyncPriority priority = LikeSyncPriority.normal,
    required Future<LikeStateResponse<T>> Function(CancelToken ct, LikeARS ars)
    action,
  }) async {
    if (_refreshSubscription == null && _syncSubscription == null) {
      initAutoReconnect();
    }

    _registeredStates.add(state);

    state.autoResync = autoResync;
    state.syncPriority = priority;
    state.refreshAction = () => fetch<T>(
      state: state,
      ars: const LikeARS(refresh: true),
      autoResync: autoResync,
      priority: priority,
      action: action,
    );

    return runZoned(() async {
      return await fetcher<T>(
        ars: ars,
        ct: state.ct,
        onRotate: (next) => state.ct = next,
        onUpdate: (newState) => state.value = newState,
        action: action,
      );
    }, zoneValues: {#likeActiveState: state});
  }

  /// A powerful orchestration method that handles the standard fetch lifecycle.
  ///
  /// This method automates:
  /// 1. **CancelToken Rotation**: Automatically cancels old requests via [onRotate].
  /// 2. **State Management**: Handles transition between loading/refresh and result states.
  /// 3. **Error Handling**: Silently handles Dio cancellations and catches unexpected exceptions.
  /// 4. **UI Notification**: Automatically calls [notifyListeners] in the appropriate phases.
  ///
  /// Use this for primary data fetching logic in your providers.
  Future<LikeStateResponse<T>> fetcher<T>({
    LikeARS? ars,
    required CancelToken? ct,
    required void Function(CancelToken next) onRotate,
    required Future<LikeStateResponse<T>> Function(CancelToken ct, LikeARS ars)
    action,
    required void Function(LikeStateResponse<T> state) onUpdate,
  }) async {
    ars ??= const ARS();

    // 1. Rotate immediately: Get old to cancel it, then set new via callback
    final next = newCT(ct);
    onRotate(next);

    try {
      // 2. Initial State Handling: Only show loading if NOT a refresh
      if (!ars.refresh) {
        onUpdate(LikeStateResponse<T>.loading());
        if (!_isDisposed) {
          notifyListeners();
        }
      }

      // 3. Execution
      final result = await action(next, ars);
      onUpdate(result);
      return result;
    } catch (e) {
      // Handle Dio Cancellation silently
      if (e is DioException && CancelToken.isCancel(e)) {
        return LikeStateResponse<T>.idle();
      }

      final exception = LikeStateResponse<T>.exception(e.toString());
      onUpdate(exception);
      return exception;
    } finally {
      if (!_isDisposed) {
        notifyListeners();
      }
    }
  }

  /// A convenience method to either return existing successful data or fetch it.
  ///
  /// Returns [response.data] immediately if the state is successful and data is present.
  /// Otherwise, it triggers the [fetcher] and awaits the result.
  FutureOr<T> loadOrFetch<T>(
    LikeStateResponse<T> response,
    Future<LikeStateResponse<T>> Function() fetcher,
  ) {
    if (response.isSuccess && response.data != null) {
      return response.data!;
    }
    return fetcher().then((result) {
      if (result.data != null) return result.data!;
      throw result.message;
    });
  }

  /// Checks if the query parameters of a state overlap with a sync event payload.
  bool checkQueryOverlap(
    Map<String, dynamic> stateQuery,
    Map<String, dynamic> eventPayload,
  ) {
    if (stateQuery.isEmpty || eventPayload.isEmpty) return true;

    for (final entry in eventPayload.entries) {
      final key = entry.key;
      final eventVal = entry.value;

      if (stateQuery.containsKey(key)) {
        final stateVal = stateQuery[key];
        if (stateVal?.toString() != eventVal?.toString()) {
          return false;
        }
      }

      if (key == 'date') {
        final eventDate = _parseDateTime(eventVal);
        final stateStart = _parseDateTime(stateQuery['startDate']);
        final stateEnd = _parseDateTime(stateQuery['endDate']);

        if (eventDate != null && stateStart != null && stateEnd != null) {
          if (eventDate.isBefore(stateStart) || eventDate.isAfter(stateEnd)) {
            return false;
          }
        }
      }
    }

    return true;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshSubscription?.cancel();
    _syncSubscription?.cancel();
    _granularTasks.clear();
    for (final state in _registeredStates) {
      state.cancel('Provider disposed');
    }
    _registeredStates.clear();
    super.dispose();
  }
}

class _LikeProviderSyncTask extends LikeSyncTask {
  final LikeAutoReconnectMixin _mixin;
  final bool isInitial;

  _LikeProviderSyncTask(this._mixin, {this.isInitial = false});

  @override
  String get id => 'provider_legacy_sync_${_mixin.runtimeType.toString()}';

  @override
  LikeSyncPriority get priority => _mixin.syncPriority;

  @override
  bool get isRecovery => !isInitial && _mixin.shouldRetry;

  @override
  Future<void> run() async {
    if (_mixin.shouldRetry) {
      await _mixin.onReconnect();
    }

    for (final task in _mixin._granularTasks) {
      if (task.condition()) {
        LikeSyncManager().registerTask(task);
      }
    }
  }
}

class _LikeGranularSyncTask extends LikeSyncTask {
  final String providerId;
  @override
  final String? endpoint;
  @override
  final LikeSyncPriority priority;
  final Future<void> Function() action;
  final bool Function() condition;
  final bool Function()? recoveryCondition;

  _LikeGranularSyncTask({
    required this.providerId,
    this.endpoint,
    required this.priority,
    required this.action,
    required this.condition,
    this.recoveryCondition,
  });

  @override
  String get id => endpoint != null
      ? 'sync_$endpoint'
      : 'granular_sync_${providerId}_${action.hashCode}';

  @override
  bool get isRecovery => recoveryCondition?.call() ?? condition();

  @override
  Future<void> run() async {
    if (condition()) {
      await action();
    }
  }
}

class _LikeStateSyncTask extends LikeSyncTask {
  final LikeNotifierState<dynamic> state;

  _LikeStateSyncTask(this.state);

  @override
  String get id => 'state_sync_${state.hashCode}';

  @override
  LikeSyncPriority get priority => state.syncPriority;

  @override
  bool get isRecovery => false;

  @override
  Future<void> run() async {
    if (state.refreshAction != null) {
      await state.refreshAction!();
    }
  }
}
