import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:like/src/core/like_ars.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/models/like_api_result.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_resync_state.dart';
import 'package:like/src/models/like_sync_event.dart';
import 'package:like/src/client/like_client.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/models/like_connectivity_transition.dart';
import 'package:like/src/models/like_sync_task.dart';
import 'package:like/src/models/like_event.dart';
import 'package:like/src/services/like_pipeline.dart';

class _LikeLifecycleObserver with WidgetsBindingObserver {
  _LikeLifecycleObserver(this.onChanged);
  final ValueChanged<AppLifecycleState> onChanged;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onChanged(state);
}

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

/// A mixin that provides automatic reconnection and synchronization logic for Notifiers.
/// Features a declarative [syncWith] API for intelligent data refreshes.
/// Matches the exact logic and contract of enterprise's AutoReconnectMixin.
class LikeEngine {
  static int _ownerSequence = 0;
  static const List<Duration> _resyncDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<LikeSyncEvent>? _syncSubscription;
  StreamSubscription<LikeEvent>? _pipelineSubscription;
  StreamSubscription<LikeConnectivityTransition>? _restorationSubscription;
  _LikeLifecycleObserver? _lifecycleObserver;
  final Set<_LikeGranularSyncTask> _granularTasks = {};
  final Set<LikeNotifierState<dynamic>> _registeredStates = {};
  final Set<_LikePipelineStateBinding> _pipelineBindings = {};
  final Map<LikeNotifierState<dynamic>, Future<void>> _resyncRuns = {};
  final Set<LikeNotifierState<dynamic>> _cancelledResyncStates = {};
  final Map<LikeNotifierState<dynamic>, Timer> _resyncTimers = {};
  final Map<LikeNotifierState<dynamic>, Completer<bool>>
      _resyncDelayCompleters = {};
  final Map<_LikeGranularSyncTask, Future<void>> _granularRuns = {};
  late final String _resyncOwnerScope =
      '${runtimeType}_${identityHashCode(this)}_${_ownerSequence++}';
  bool _isResyncActive = true;
  bool _isDisposed = false;

  /// Unique lifecycle scope used to isolate this provider's UI resync work.
  String get resyncOwnerScope => _resyncOwnerScope;

  /// Whether owner-scoped UI resynchronization is currently allowed.
  bool get isResyncActive => _isResyncActive && !_isDisposed;

  /// Whether the provider is in a state that requires a retry/sync.
  bool get shouldRetry => false;

  /// Default priority for sync tasks from this provider.
  LikeSyncPriority get syncPriority => LikeSyncPriority.critical;

  /// Initializes the auto-reconnect and synchronization logic.
  ///
  /// If [registerInitialTask] is true, a critical sync task is registered immediately
  /// to ensure data is fetched upon initialization if needed.
  void initAutoReconnect({bool registerInitialTask = false}) {
    if (_isDisposed || _refreshSubscription != null) return;

    if (registerInitialTask) {
      scheduleMicrotask(() => _runLegacyReconnect(LikeResyncTrigger.initial));
    }

    _lifecycleObserver = _LikeLifecycleObserver(_handleAppLifecycleState);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);

    _restorationSubscription = LikeConnectivityManager()
        .originRestorations
        .listen((event) => _handleOriginRestoration(event.origin));

    _refreshSubscription = LikeClient().refreshStream.listen((path) {
      // Manual compatibility signal only. Automatic connectivity restoration
      // uses the origin-scoped stream above and never broadcasts this value.
      if (path == 'reconnected') {
        unawaited(_runLegacyReconnect(LikeResyncTrigger.legacyReconnection));
        return;
      }


      // 2. Automated syncWith support
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
              unawaited(_runGranularTask(task));
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
                unawaited(triggerResync(
                  state,
                  trigger: LikeResyncTrigger.mutation,
                ));
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
        // notifyListeners() is now handled by the State object
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
      unawaited(_runGranularTask(task));
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

  /// Enables or pauses all UI resynchronization owned by this provider.
  ///
  /// Pausing cancels pending delays and active requests without disposing the
  /// provider. Calling this with `true` does not replay work by itself.
  void setResyncActive(bool active) {
    if (_isDisposed || _isResyncActive == active) return;
    _isResyncActive = active;
    if (!active) cancelResync();
  }

  /// Starts or joins a bounded resynchronization run for [state].
  ///
  /// Restoration-triggered runs require a retained refresh action, an active
  /// owner, matching canonical origin, `autoResync`, and a retryable network
  /// state or resiliency fallback. Mutation-triggered runs require `autoResync`
  /// but intentionally accept a successful state because they invalidate
  /// previously loaded data. Manual calls require only an active owner and a
  /// retained refresh action.
  Future<void> triggerResync(
    LikeNotifierState<dynamic> state, {
    LikeResyncTrigger trigger = LikeResyncTrigger.manual,
    String? origin,
  }) {
    final existing = _resyncRuns[state];
    if (existing != null) return existing;

    // We removed the strict !isResyncActive check here. If the user backgrounded the app,
    // we still want to allow restoration syncs to fire so they don't get lost.
    // We only skip if there's no refreshAction.
    if (state.refreshAction == null) {
      return Future<void>.value();
    }

    final requiresRecoveryState = trigger == LikeResyncTrigger.restoration ||
        trigger == LikeResyncTrigger.initial ||
        trigger == LikeResyncTrigger.legacyReconnection;
    if (trigger != LikeResyncTrigger.manual && !state.autoResync) {
      return Future<void>.value();
    }

    // For automatic triggers, we retry if it's in a failure state.
    // For restorations, we also retry if it's currently loading, because the previous
    // socket is likely dead.
    bool needsRefresh =
        state.isError || state.isException || state.value.isResiliencyFallback;
    if (trigger == LikeResyncTrigger.restoration ||
        trigger == LikeResyncTrigger.legacyReconnection) {
      needsRefresh = needsRefresh || state.value.isLoading;
    }

    if (requiresRecoveryState && !needsRefresh) {
      return Future<void>.value();
    }
    if (trigger == LikeResyncTrigger.restoration &&
        (state.canonicalOrigin == null || state.canonicalOrigin != origin)) {
      return Future<void>.value();
    }

    _cancelledResyncStates.remove(state);
    final run =
        _runStateResync(state, trigger, origin ?? state.canonicalOrigin);
    _resyncRuns[state] = run;
    void cleanup() {
      if (identical(_resyncRuns[state], run)) {
        _resyncRuns.remove(state);
        _cancelledResyncStates.remove(state);
      }
    }

    // Cleanup must not create a second failing future when [run] fails.
    run.then<void>((_) => cleanup(), onError: (Object _, StackTrace __) {
      cleanup();
    });
    return run;
  }

  /// Cancels one state run, or every UI resync run owned by this provider.
  ///
  /// Pending work is not retained globally and will not outlive this owner.
  void cancelResync([LikeNotifierState<dynamic>? state]) {
    final targets = state == null
        ? <LikeNotifierState<dynamic>>{
            ..._registeredStates,
            ..._resyncRuns.keys,
          }.toList(growable: false)
        : <LikeNotifierState<dynamic>>[state];
    final now = DateTime.now();
    for (final target in targets) {
      if (_resyncRuns.containsKey(target)) {
        _cancelledResyncStates.add(target);
      }
      _resyncTimers.remove(target)?.cancel();
      final delayCompleter = _resyncDelayCompleters.remove(target);
      if (delayCompleter != null && !delayCompleter.isCompleted) {
        delayCompleter.complete(false);
      }
      target.cancel('UI resync cancelled');
      if (!_isDisposed && target.resyncState.isActive) {
        target.resyncState = LikeResyncState(
          phase: LikeResyncPhase.cancelled,
          trigger: target.resyncState.trigger,
          attempt: target.resyncState.attempt,
          maxAttempts: target.resyncState.maxAttempts,
          origin: target.resyncState.origin,
          startedAt: target.resyncState.startedAt,
          updatedAt: now,
          completedAt: now,
        );
      }
    }
  }

  /// Manually triggers a refresh for all registered states that are marked for focus refetching.
  void triggerFocusRefetch() {
    for (final state in _registeredStates) {
      if (state.refetchOnFocus && state.refreshAction != null) {
        triggerResync(state, trigger: LikeResyncTrigger.manual);
      }
    }
  }

  void _handleOriginRestoration(String origin) {
    if (!isResyncActive) return;
    for (final state in _registeredStates.toList(growable: false)) {
      unawaited(triggerResync(
        state,
        trigger: LikeResyncTrigger.restoration,
        origin: origin,
      ));
    }
  }

  AppLifecycleState _lastAppState = AppLifecycleState.resumed;

  void _handleAppLifecycleState(AppLifecycleState appState) {
    final wasResumed = _lastAppState == AppLifecycleState.resumed;
    _lastAppState = appState;
    if (appState == AppLifecycleState.resumed && !wasResumed) {
      if (_isResyncActive) {
        for (final state in _registeredStates) {
          if (state.autoResync && regularRetry(state.value, state.ct)) {
            triggerResync(state, trigger: LikeResyncTrigger.legacyReconnection);
          }
        }
      }
    }
  }

  Future<void> _runLegacyReconnect(LikeResyncTrigger trigger) async {
    if (!isResyncActive) return;
    if (!isResyncActive) return;
    for (final task in _granularTasks.toList(growable: false)) {
      if (task.condition()) await _runGranularTask(task);
    }
    for (final state in _registeredStates.toList(growable: false)) {
      if (state.autoResync && regularRetry(state.value, state.ct)) {
        await triggerResync(state, trigger: trigger);
      }
    }
  }

  Future<void> _runGranularTask(_LikeGranularSyncTask task) {
    final existing = _granularRuns[task];
    if (existing != null) return existing;
    if (!isResyncActive || !task.condition()) return Future<void>.value();
    final run = task.run();
    _granularRuns[task] = run;
    void cleanup() {
      if (identical(_granularRuns[task], run)) _granularRuns.remove(task);
    }

    // Cleanup must not create a second failing future when [run] fails.
    run.then<void>((_) => cleanup(), onError: (Object _, StackTrace __) {
      cleanup();
    });
    return run;
  }

  Future<void> _runStateResync(
    LikeNotifierState<dynamic> state,
    LikeResyncTrigger trigger,
    String? origin,
  ) async {
    final startedAt = DateTime.now();
    final maximum =
        LikeConstants.maxAutoRetries < 1 ? 1 : LikeConstants.maxAutoRetries;
    Object? terminalError;

    bool canContinue() =>
        isResyncActive &&
        !_cancelledResyncStates.contains(state) &&
        state.refreshAction != null;

    for (var attempt = 1; attempt <= maximum; attempt++) {
      if (!canContinue()) return;

      Duration? delay;
      if (attempt > 1) {
        final index = (attempt - 2).clamp(0, _resyncDelays.length - 1);
        delay = _resyncDelays[index];
        final nextRetryAt = DateTime.now().add(delay);
        state.resyncState = LikeResyncState(
          phase: LikeResyncPhase.waiting,
          trigger: trigger,
          attempt: attempt,
          maxAttempts: maximum,
          delay: delay,
          nextRetryAt: nextRetryAt,
          origin: origin,
          startedAt: startedAt,
          updatedAt: DateTime.now(),
        );
        if (!await _waitForResyncDelay(state, delay)) return;
      }

      if (!canContinue()) return;
      state.resyncState = LikeResyncState(
        phase: LikeResyncPhase.running,
        trigger: trigger,
        attempt: attempt,
        maxAttempts: maximum,
        delay: delay,
        origin: origin,
        startedAt: startedAt,
        updatedAt: DateTime.now(),
      );

      try {
        await state.refreshAction!();
        if (!canContinue()) return;
        if (!regularRetry(state.value, null)) {
          final now = DateTime.now();
          state.resyncState = LikeResyncState(
            phase: LikeResyncPhase.succeeded,
            trigger: trigger,
            attempt: attempt,
            maxAttempts: maximum,
            origin: origin,
            startedAt: startedAt,
            updatedAt: now,
            completedAt: now,
          );
          return;
        }
        terminalError = state.error ?? state.message;
      } catch (error) {
        terminalError = error;
      }
    }

    if (!canContinue()) return;
    final now = DateTime.now();
    state.resyncState = LikeResyncState(
      phase: LikeResyncPhase.failed,
      trigger: trigger,
      attempt: maximum,
      maxAttempts: maximum,
      origin: origin,
      terminalError: terminalError,
      startedAt: startedAt,
      updatedAt: now,
      completedAt: now,
    );
  }

  Future<bool> _waitForResyncDelay(
    LikeNotifierState<dynamic> state,
    Duration delay,
  ) {
    final completer = Completer<bool>();
    _resyncDelayCompleters[state] = completer;
    final timer = Timer(delay, () {
      _resyncTimers.remove(state);
      _resyncDelayCompleters.remove(state);
      if (!completer.isCompleted) {
        completer.complete(
          isResyncActive && !_cancelledResyncStates.contains(state),
        );
      }
    });
    _resyncTimers[state] = timer;
    return completer.future;
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
  ///
  /// ### State Transitions and Returns
  /// Depending on the request lifecycle and parameters, the state transitions and returned values are:
  ///
  /// | Action / Phase | Condition | State Transition (`state.value`) | Returned Value |
  /// | :--- | :--- | :--- | :--- |
  /// | **Start (Clean)** | `!ars.refresh` | `StateResponse.loading()` | N/A (In-flight) |
  /// | **Start (Refresh)** | `ars.refresh` & `currentData != null` | `StateResponse.refreshing(currentData)` | N/A (In-flight) |
  /// | **Start (Refresh)** | `ars.refresh` & `currentData == null` | *Preserves current state* | N/A (In-flight) |
  /// | **Completion** | Request is not obsolete | `StateResponse.success(...)` or error | The result state |
  /// | **Completion** | Request is obsolete | *No change (ignored)* | The result state |
  /// | **Cancellation (Obsolete)** | `DioException.cancel` | *No change (ignored)* | Reverted previous state |
  /// | **Cancellation (Active)** | `DioException.cancel` | Reverted previous state | Reverted previous state |
  /// | **Failure** | Generic Exception | `StateResponse.exception(...)` | `StateResponse.exception(...)` |
  Future<StateResponse<T>> fetch<T>({
    required NotifierState<T> state,
    LikeARS? ars,
    bool autoResync = false,
    LikeSyncPriority priority = LikeSyncPriority.normal,
    bool disableRequestCancellation = false,
    required Future<StateResponse<T>> Function() action,
  }) async {
    if (_refreshSubscription == null &&
        _syncSubscription == null &&
        _pipelineSubscription == null) {
      initAutoReconnect();
    }

    _registeredStates.add(state);

    // Auto-wire pipeline binding if the state has a mapper declared.
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
          state.value = StateResponse<T>.success(
            mappedData,
            isFromCache: false,
          );
        },
      ));
    }

    final effectiveAutoResync = (ars?.visibility == true) ? true : autoResync;
    final effectiveRefetchOnFocus = (ars?.visibility == true);

    state.autoResync = effectiveAutoResync;
    state.refetchOnFocus = effectiveRefetchOnFocus;
    state.syncPriority = priority;
    state.refreshAction = () => fetch<T>(
          state: state,
          ars: const LikeARS(refresh: true),
          autoResync: effectiveAutoResync,
          priority: priority,
          disableRequestCancellation: disableRequestCancellation,
          action: action,
        );

    final actualArs = ars ?? const LikeARS();

    // Rotate token
    final nextCt = disableRequestCancellation
        ? (state.ct ?? CancelToken())
        : newCT(state.ct);
    state.ct = nextCt;

    bool isObsolete() => state.ct != nextCt;

    final StateResponse<T> previousState = state.value;
    final T? currentData = state.data;

    // Determine the fallback state if cancellation occurs
    final StateResponse<T> fallbackState;
    if (previousState.isRefreshing) {
      fallbackState = currentData != null
          ? StateResponse<T>.success(currentData)
          : StateResponse<T>.idle();
    } else if (previousState.isLoading) {
      fallbackState = StateResponse<T>.idle();
    } else {
      fallbackState = previousState;
    }

    try {
      final useSilentLoading = ars?.checkAvailability == true &&
          previousState.isSuccess &&
          currentData != null;
      if (actualArs.refresh || useSilentLoading) {
        if (currentData != null) {
          state.value = StateResponse<T>.refreshing(
            currentData,
          );
        }
      } else {
        state.value = StateResponse<T>.loading();
      }

      final result = await runZoned(
        () => action(),
        zoneValues: {
          #likeActiveState: state,
          #likeActiveArs: actualArs,
        },
      );

      if (!isObsolete()) {
        state.value = result;
      }
      return result;
    } catch (e) {
      final isCancel = e is DioException && CancelToken.isCancel(e);
      final obsolete = isObsolete();

      if (isCancel) {
        final shouldRevertState = !obsolete ||
            (state.ct == null &&
                (state.value.isLoading || state.value.isRefreshing));

        if (shouldRevertState) {
          state.value = fallbackState;
        }
        return fallbackState;
      }

      final exceptionState = StateResponse<T>.exception(e.toString());
      if (obsolete) {
        return exceptionState;
      }

      state.value = exceptionState;
      return exceptionState;
    }
  }

  /// A streamlined version of [fetch] that automatically unwraps [ApiResult]s
  /// and maps them to [StateResponse]s using `toStateResponse()`. 
  /// This significantly reduces boilerplate in Provider classes.
  Future<StateResponse<T>> fetchResult<T>({
    required NotifierState<T> state,
    LikeARS? ars,
    bool autoResync = false,
    LikeSyncPriority priority = LikeSyncPriority.normal,
    bool disableRequestCancellation = false,
    required Future<ApiResult<T>> Function() action,
  }) async {
    return fetch<T>(
      state: state,
      ars: ars,
      autoResync: autoResync,
      priority: priority,
      disableRequestCancellation: disableRequestCancellation,
      action: () async {
        final result = await action();
        return result.toStateResponse();
      },
    );
  }

  /// Checks if the query parameters of a state overlap with a sync event payload.
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

      if (key == 'date') {
        if (stateQuery.containsKey('startDate') &&
            stateQuery.containsKey('endDate')) {
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

  void dispose() {
    cancelResync();
    _isDisposed = true;
    _isResyncActive = false;
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
    }
    _refreshSubscription?.cancel();
    _syncSubscription?.cancel();
    _pipelineSubscription?.cancel();
    _restorationSubscription?.cancel();
    for (final timer in _resyncTimers.values) {
      timer.cancel();
    }
    _resyncTimers.clear();
    for (final completer in _resyncDelayCompleters.values) {
      if (!completer.isCompleted) completer.complete(false);
    }
    _resyncDelayCompleters.clear();
    _resyncRuns.clear();
    _cancelledResyncStates.clear();
    _granularRuns.clear();
    _granularTasks.clear();
    _pipelineBindings.clear();
    for (final state in _registeredStates) {
      state.cancel('Provider disposed');
    }
    _registeredStates.clear();
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

/// A convenience alias for [LikeEngine].
typedef StateEngine = LikeEngine;
