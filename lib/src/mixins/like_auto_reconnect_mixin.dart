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
import 'package:like/src/models/like_event.dart';
import 'package:like/src/services/like_pipeline.dart';

class _LikePipelineStateBinding {
  final LikeNotifierState<dynamic> state;
  final String? Function() getEndpointPath;
  final String? Function() getCleanEndpointPath;
  final Map<String, dynamic> Function() getActiveQuery;
  final bool exactQueryMatch;
  final void Function(dynamic rawData) processAndAssign;

  _LikePipelineStateBinding({
    required this.state,
    required this.getEndpointPath,
    required this.getCleanEndpointPath,
    required this.getActiveQuery,
    required this.exactQueryMatch,
    required this.processAndAssign,
  });

  @override
  bool operator ==(Object other) =>
      other is _LikePipelineStateBinding && other.state == state;

  @override
  int get hashCode => state.hashCode;
}

/// A mixin that provides automatic reconnection, data pipeline binding, and sync logic for Notifiers.
mixin LikeAutoReconnectMixin on ChangeNotifier {
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<LikeSyncEvent>? _syncSubscription;
  StreamSubscription<LikeEvent>? _pipelineSubscription;
  final Set<_LikeGranularSyncTask> _granularTasks = {};
  final Set<LikeNotifierState<dynamic>> _registeredStates = {};
  final Set<_LikePipelineStateBinding> _pipelineBindings = {};
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
  void initAutoReconnect({bool registerInitialTask = false}) {
    if (registerInitialTask) {
      LikeSyncManager().registerTask(
        _LikeProviderSyncTask(this, isInitial: true),
      );
    }

    _refreshSubscription = LikeClient().refreshStream.listen((path) {
      if (path == 'reconnected') {
        LikeSyncManager().registerTask(_LikeProviderSyncTask(this));
        return;
      }

      onAutoRefresh(path);

      for (final task in _granularTasks) {
        if (task.endpoint != null) {
          String cleanPath;
          if (path.startsWith('http://') || path.startsWith('https://')) {
            final uri = Uri.tryParse(path);
            cleanPath = uri != null ? uri.path : path.split('?').first;
          } else {
            final incomingPath =
                path.contains(':') ? path.split(':').last : path;
            cleanPath = incomingPath.split('?').first;
          }

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
          String cleanPath;
          if (event.path.startsWith('http://') ||
              event.path.startsWith('https://')) {
            final uri = Uri.tryParse(event.path);
            cleanPath = uri != null ? uri.path : event.path.split('?').first;
          } else {
            cleanPath = event.path.split('?').first;
          }

          String statePath;
          if (state.endpointPath!.startsWith('http://') ||
              state.endpointPath!.startsWith('https://')) {
            final uri = Uri.tryParse(state.endpointPath!);
            statePath =
                uri != null ? uri.path : state.endpointPath!.split('?').first;
          } else {
            statePath = state.endpointPath!.split('?').first;
          }

          if (cleanPath == statePath ||
              (cleanPath.startsWith(statePath) &&
                  cleanPath[statePath.length] == '/')) {
            final overlap = checkQueryOverlap(
              state.activeQuery ?? const {},
              event.payload,
            );
            if (overlap) {
              final isSuccess = state.value.isSuccess ||
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

    _pipelineSubscription = LikePipeline().stream.listen((event) {
      final incomingKey = event.key;
      String cleanIncomingPath;
      if (incomingKey.startsWith('http://') ||
          incomingKey.startsWith('https://')) {
        final uri = Uri.tryParse(incomingKey);
        cleanIncomingPath =
            uri != null ? uri.path : incomingKey.split('?').first;
      } else {
        final incomingPath = incomingKey.contains(':')
            ? incomingKey.split(':').last
            : incomingKey;
        cleanIncomingPath = incomingPath.split('?').first;
      }
      final eventQuery = event.response.requestOptions.queryParameters;
      bool handled = false;

      for (final binding in _pipelineBindings) {
        final statePath = binding.getCleanEndpointPath() ??
            binding.getEndpointPath()?.split('?').first;
        if (statePath == null) continue;

        if (cleanIncomingPath == statePath) {
          final overlap = checkQueryOverlap(
            binding.getActiveQuery(),
            eventQuery,
            exact: binding.exactQueryMatch,
          );

          if (overlap) {
            try {
              binding.processAndAssign(event.data);
              handled = true;
            } catch (e) {
              debugPrint('AutoReconnect Pipeline Mapping Error: $e');
            }
          }
        }
      }

      if (handled && !_isDisposed) {
        notifyListeners();
      }
    });
  }

  /// Registers a specific API call to be automatically refreshed when its data source updates.
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
  bool regularRetry(LikeStateResponse? state, CancelToken? cancelToken) {
    if (state == null || state.isIdle) return false;

    bool needsRefresh =
        state.isError || state.isException || state.isResiliencyFallback;

    if (cancelToken == null) return needsRefresh;
    return needsRefresh && !cancelToken.isCancelled;
  }

  /// Cancels the provided [cancelToken] if active.
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

  /// State execution wrapper managing the lifecycle of a [LikeNotifierState].
  Future<LikeStateResponse<T>> fetch<T>({
    required LikeNotifierState<T> state,
    LikeARS? ars,
    bool autoResync = false,
    LikeSyncPriority priority = LikeSyncPriority.normal,
    bool disableRequestCancellation = false,
    required Future<LikeStateResponse<T>> Function(CancelToken ct, LikeARS ars)
        action,
  }) async {
    if (_refreshSubscription == null &&
        _syncSubscription == null &&
        _pipelineSubscription == null) {
      initAutoReconnect();
    }

    _registeredStates.add(state);

    if (state.mapper != null) {
      _pipelineBindings.removeWhere((b) => b.state == state);
      _pipelineBindings.add(_LikePipelineStateBinding(
        state: state,
        getEndpointPath: () => state.endpointPath,
        getCleanEndpointPath: () => state.cleanEndpointPath,
        getActiveQuery: () => state.activeQuery ?? const {},
        exactQueryMatch: false,
        processAndAssign: (rawData) {
          if (state.value.isLoading || state.value.isRefreshing) return;
          final mappedData = state.mapper!(rawData);
          state.value = LikeStateResponse<T>.success(
            mappedData,
            isFromCache: false,
          );
        },
      ));
    }

    state.autoResync = autoResync;
    state.syncPriority = priority;
    state.refreshAction = () => fetch<T>(
          state: state,
          ars: const LikeARS(refresh: true),
          autoResync: autoResync,
          priority: priority,
          disableRequestCancellation: disableRequestCancellation,
          action: action,
        );

    return runZoned(() async {
      return await fetcher<T>(
        ars: ars,
        ct: state.ct,
        onRotate: (next) => state.ct = next,
        onUpdate: (newState) => state.value = newState,
        disableRequestCancellation: disableRequestCancellation,
        isObsolete: (next) => state.ct != next,
        action: action,
        previousState: state.value,
      );
    }, zoneValues: {#likeActiveState: state});
  }

  /// Primary orchestration method handling the fetch lifecycle.
  Future<LikeStateResponse<T>> fetcher<T>({
    LikeARS? ars,
    required CancelToken? ct,
    required void Function(CancelToken next) onRotate,
    required Future<LikeStateResponse<T>> Function(CancelToken ct, LikeARS ars)
        action,
    required void Function(LikeStateResponse<T> state) onUpdate,
    bool disableRequestCancellation = false,
    bool Function(CancelToken next)? isObsolete,
    LikeStateResponse<T>? previousState,
  }) async {
    ars ??= const LikeARS();

    final next = disableRequestCancellation ? (ct ?? CancelToken()) : newCT(ct);
    onRotate(next);

    final activeState = Zone.current[#likeActiveState];

    bool checkObsolete() {
      if (isObsolete != null) {
        return isObsolete(next);
      }
      if (activeState is LikeNotifierState) {
        return activeState.ct != next;
      }
      return false;
    }

    T? currentData;
    LikeStateResponse<T>? resolvedPreviousState = previousState;
    if (activeState is LikeNotifierState) {
      try {
        resolvedPreviousState ??= activeState.value as LikeStateResponse<T>?;
        currentData = activeState.data as T?;
      } catch (_) {}
    }

    final LikeStateResponse<T> fallbackState;
    if (resolvedPreviousState != null) {
      if (resolvedPreviousState.isRefreshing) {
        final data = resolvedPreviousState.data;
        fallbackState = data != null
            ? LikeStateResponse<T>.success(data)
            : LikeStateResponse<T>.idle();
      } else if (resolvedPreviousState.isLoading) {
        fallbackState = LikeStateResponse<T>.idle();
      } else {
        fallbackState = resolvedPreviousState;
      }
    } else {
      fallbackState = currentData != null
          ? LikeStateResponse<T>.success(currentData)
          : LikeStateResponse<T>.idle();
    }

    try {
      if (ars.refresh) {
        if (currentData != null) {
          onUpdate(LikeStateResponse<T>.refreshing(currentData));
        }
      } else {
        onUpdate(LikeStateResponse<T>.loading());
      }
      if (!_isDisposed) notifyListeners();

      final result = await action(next, ars);

      if (!checkObsolete()) {
        onUpdate(result);
        if (!_isDisposed) notifyListeners();
      }
      return result;
    } catch (e) {
      final isCancel = e is DioException && CancelToken.isCancel(e);
      final obsolete = checkObsolete();

      if (isCancel) {
        final shouldRevertState = !obsolete ||
            (activeState is LikeNotifierState &&
                activeState.ct == null &&
                (activeState.value.isLoading ||
                    activeState.value.isRefreshing));

        if (shouldRevertState) {
          onUpdate(fallbackState);
          if (!_isDisposed) notifyListeners();
        }
        return fallbackState;
      }

      if (obsolete) {
        return LikeStateResponse<T>.exception(e.toString());
      }

      final exception = LikeStateResponse<T>.exception(e.toString());
      onUpdate(exception);
      if (!_isDisposed) notifyListeners();
      return exception;
    }
  }

  /// Convenience method to return existing successful data or fetch it.
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

  /// Checks if query parameters of a state overlap with a sync event payload.
  bool checkQueryOverlap(
    Map<String, dynamic> stateQuery,
    Map<String, dynamic> eventPayload, {
    bool exact = false,
  }) {
    if (exact) {
      if (stateQuery.length != eventPayload.length) return false;
      for (final key in stateQuery.keys) {
        if (stateQuery[key]?.toString() != eventPayload[key]?.toString()) {
          return false;
        }
      }
      return true;
    }

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
    }

    return true;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshSubscription?.cancel();
    _syncSubscription?.cancel();
    _pipelineSubscription?.cancel();
    _granularTasks.clear();
    _pipelineBindings.clear();
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
  bool get isRecovery {
    if (!isInitial && _mixin.shouldRetry) return true;
    for (final state in _mixin._registeredStates) {
      if (state.autoResync && _mixin.regularRetry(state.value, state.ct)) {
        return true;
      }
    }
    return false;
  }

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

    for (final state in _mixin._registeredStates) {
      if (state.autoResync && state.refreshAction != null) {
        if (_mixin.regularRetry(state.value, state.ct)) {
          LikeSyncManager().registerTask(_LikeStateSyncTask(state));
        }
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
