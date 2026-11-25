import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_ars.dart';
import 'package:like/src/models/like_api_result.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_state_response.dart';

/// Lightweight [ChangeNotifier] base class for individual request execution.
///
/// Provides [fetch], [fetchResult], [fetcher], and [CancelToken] rotation/cleanup
/// without any automatic resync, background sync, or pipeline subscriptions.
mixin LikeChangeNotifier on ChangeNotifier {
  final Set<LikeNotifierState<dynamic>> _registeredStates = {};
  final Map<Object, LikeNotifierState<dynamic>> _keyedStates = {};
  final Map<Object, PaginatedNotifierState<dynamic>> _paginatedStates = {};
  final Map<Object, LikeStateResponse<dynamic>> _keyedResponses = {};
  final Map<Object, CancelToken> _responseTokens = {};
  bool _isDisposed = false;

  /// Read-only view of states registered by key via [getByKey].
  Map<Object, LikeNotifierState<dynamic>> get keyedStates =>
      Map<Object, LikeNotifierState<dynamic>>.unmodifiable(_keyedStates);

  /// Read-only view of paginated states registered by key via [getPaginatedByKey].
  Map<Object, PaginatedNotifierState<dynamic>> get paginatedStates =>
      Map<Object, PaginatedNotifierState<dynamic>>.unmodifiable(
        _paginatedStates,
      );

  /// Read-only view of [LikeStateResponse] snapshots stored by key via
  /// [getResponseByKey], [setResponseByKey], or [fetchResponseByKey].
  Map<Object, LikeStateResponse<dynamic>> get keyedResponses =>
      Map<Object, LikeStateResponse<dynamic>>.unmodifiable(_keyedResponses);

  /// Returns the [LikeNotifierState<T>] associated with [key], creating and
  /// registering one if it does not exist yet (or was disposed).
  LikeNotifierState<T> getByKey<T>(
    Object key, {
    LikeStateResponse<T>? initialValue,
    T Function(dynamic json)? mapper,
  }) {
    final existing = _keyedStates[key];
    if (existing != null &&
        !existing.isDisposed &&
        existing is LikeNotifierState<T>) {
      return existing;
    }
    final created = LikeNotifierState<T>(
      initialValue: initialValue,
      mapper: mapper,
    );
    _keyedStates[key] = created;
    _registeredStates.add(created);
    return created;
  }

  /// Returns the [PaginatedNotifierState<T>] associated with [key], creating
  /// and registering one if it does not exist yet (or was disposed).
  PaginatedNotifierState<T> getPaginatedByKey<T>(
    Object key, {
    int pageSize = 10,
    Future<LikeApiResult<List<T>>> Function(int page, int limit)? fetcher,
    LikeStateResponse<List<T>>? initialValue,
  }) {
    final existing = _paginatedStates[key];
    if (existing != null &&
        !existing.isDisposed &&
        existing is PaginatedNotifierState<T>) {
      return existing;
    }
    final created = PaginatedNotifierState<T>(
      pageSize: pageSize,
      fetcher: fetcher,
      initialValue: initialValue,
    );
    _paginatedStates[key] = created;
    _registeredStates.add(created);
    return created;
  }

  /// Returns the [LikeStateResponse<T>] associated with [key], initializing it
  /// with [initialValue] (or `LikeStateResponse<T>.idle()`) if absent.
  LikeStateResponse<T> getResponseByKey<T>(
    Object key, {
    LikeStateResponse<T>? initialValue,
  }) {
    final existing = _keyedResponses[key];
    if (existing is LikeStateResponse<T>) {
      return existing;
    }
    final created = existing != null && existing.isIdle
        ? LikeStateResponse<T>.idle(message: existing.message)
        : (initialValue ?? LikeStateResponse<T>.idle());
    _keyedResponses[key] = created;
    return created;
  }

  /// Stores [response] under [key] in [keyedResponses] and notifies listeners.
  void setResponseByKey<T>(Object key, LikeStateResponse<T> response) {
    _keyedResponses[key] = response;
    if (!_isDisposed) notifyListeners();
  }

  /// Resets the state for [key] (or all registered states if [key] is omitted)
  /// back to its initial `idle` state.
  void toInitState([Object? key, String? message]) {
    if (key != null) {
      _keyedStates[key]?.toInitState(message: message);
      _paginatedStates[key]?.toInitState(message: message);
      if (_keyedResponses.containsKey(key)) {
        _keyedResponses[key] = LikeStateResponse<dynamic>.idle(
          message: message,
        );
      }
      cancelTokenNow(_responseTokens.remove(key), message);
    } else {
      for (final state in _keyedStates.values) {
        if (!state.isDisposed) state.toInitState(message: message);
      }
      for (final state in _paginatedStates.values) {
        if (!state.isDisposed) state.toInitState(message: message);
      }
      for (final state in _registeredStates) {
        if (!state.isDisposed) state.toInitState(message: message);
      }
      for (final k in _keyedResponses.keys.toList()) {
        _keyedResponses[k] = LikeStateResponse<dynamic>.idle(message: message);
      }
      for (final token in _responseTokens.values) {
        cancelTokenNow(token, message);
      }
      _responseTokens.clear();
    }
    if (!_isDisposed) notifyListeners();
  }

  /// Cancels [cancelToken] if it is non-null and not already cancelled.
  void cancelTokenNow(CancelToken? cancelToken, [String? message]) {
    if (cancelToken != null && !cancelToken.isCancelled) {
      cancelToken.cancel(message ?? 'Request cancelled');
    }
  }

  /// Cancels [cancelToken] and returns a fresh [CancelToken].
  CancelToken newCT(CancelToken? cancelToken, [String? message]) {
    cancelTokenNow(cancelToken, message ?? 'Old Request cancelled');
    return CancelToken();
  }

  /// Executes [action] for [state] with [CancelToken] rotation and
  /// automatic `loading` / `refreshing` / `success` / `exception` transitions.
  Future<LikeStateResponse<T>> fetch<T>({
    required LikeNotifierState<T> state,
    LikeARS? ars,
    bool disableRequestCancellation = false,
    required Future<LikeStateResponse<T>> Function(CancelToken ct, LikeARS ars)
    action,
  }) {
    _registeredStates.removeWhere((s) => s.isDisposed);
    _registeredStates.add(state);
    final effectiveArs = ars ?? const LikeARS();

    return runZoned(
      () => fetcher<T>(
        ars: effectiveArs,
        ct: state.ct,
        onRotate: (next) => state.ct = next,
        onUpdate: (newState) => state.value = newState,
        disableRequestCancellation: disableRequestCancellation,
        isObsolete: (next) => state.ct != next,
        previousState: state.value,
        action: action,
      ),
      zoneValues: <Object?, Object?>{
        #likeActiveState: state,
        #likeActiveArs: effectiveArs,
      },
    );
  }

  /// Streamlined [fetch] that unwraps [LikeApiResult] via `toStateResponse()`.
  Future<LikeStateResponse<T>> fetchResult<T>({
    required LikeNotifierState<T> state,
    LikeARS? ars,
    bool disableRequestCancellation = false,
    required Future<LikeApiResult<T>> Function(CancelToken ct, LikeARS ars)
    action,
  }) {
    return fetch<T>(
      state: state,
      ars: ars,
      disableRequestCancellation: disableRequestCancellation,
      action: (ct, effectiveArs) async {
        final result = await action(ct, effectiveArs);
        return result.toStateResponse();
      },
    );
  }

  /// Executes [action] against a plain immutable [LikeStateResponse<T>] field
  /// instead of a [LikeNotifierState<T>], calling [onUpdate] and
  /// `notifyListeners()` on each lifecycle transition.
  ///
  /// When [ct] and [onRotate] are omitted, [LikeChangeNotifier] manages
  /// [CancelToken] rotation and disposal automatically under [key] (or [T]).
  Future<LikeStateResponse<T>> fetchResponse<T>({
    required LikeStateResponse<T> state,
    required void Function(LikeStateResponse<T> next) onUpdate,
    Object? key,
    CancelToken? ct,
    void Function(CancelToken next)? onRotate,
    LikeARS? ars,
    bool disableRequestCancellation = false,
    required Future<LikeStateResponse<T>> Function(CancelToken ct, LikeARS ars)
    action,
  }) {
    final tokenKey = key ?? T;
    final effectiveCt = ct ?? _responseTokens[tokenKey];
    return fetcher<T>(
      ars: ars,
      ct: effectiveCt,
      onRotate: onRotate ?? (next) => _responseTokens[tokenKey] = next,
      onUpdate: onUpdate,
      disableRequestCancellation: disableRequestCancellation,
      isObsolete: (next) =>
          onRotate == null ? _responseTokens[tokenKey] != next : false,
      previousState: state,
      action: action,
    );
  }

  /// Streamlined [fetchResponse] that unwraps [LikeApiResult] via `toStateResponse()`.
  Future<LikeStateResponse<T>> fetchResponseResult<T>({
    required LikeStateResponse<T> state,
    required void Function(LikeStateResponse<T> next) onUpdate,
    Object? key,
    CancelToken? ct,
    void Function(CancelToken next)? onRotate,
    LikeARS? ars,
    bool disableRequestCancellation = false,
    required Future<LikeApiResult<T>> Function(CancelToken ct, LikeARS ars)
    action,
  }) {
    return fetchResponse<T>(
      state: state,
      onUpdate: onUpdate,
      key: key,
      ct: ct,
      onRotate: onRotate,
      ars: ars,
      disableRequestCancellation: disableRequestCancellation,
      action: (cancelToken, effectiveArs) async {
        final result = await action(cancelToken, effectiveArs);
        return result.toStateResponse();
      },
    );
  }

  /// Executes [action] for the keyed [LikeStateResponse<T>] stored under [key]
  /// in [keyedResponses], automatically updating the map and notifying listeners.
  Future<LikeStateResponse<T>> fetchResponseByKey<T>({
    required Object key,
    LikeStateResponse<T>? initialValue,
    LikeARS? ars,
    bool disableRequestCancellation = false,
    required Future<LikeStateResponse<T>> Function(CancelToken ct, LikeARS ars)
    action,
  }) {
    final current = getResponseByKey<T>(key, initialValue: initialValue);
    return fetchResponse<T>(
      key: key,
      state: current,
      onUpdate: (next) => _keyedResponses[key] = next,
      ars: ars,
      disableRequestCancellation: disableRequestCancellation,
      action: action,
    );
  }

  /// Streamlined [fetchResponseByKey] that unwraps [LikeApiResult] via `toStateResponse()`.
  Future<LikeStateResponse<T>> fetchResponseResultByKey<T>({
    required Object key,
    LikeStateResponse<T>? initialValue,
    LikeARS? ars,
    bool disableRequestCancellation = false,
    required Future<LikeApiResult<T>> Function(CancelToken ct, LikeARS ars)
    action,
  }) {
    return fetchResponseByKey<T>(
      key: key,
      initialValue: initialValue,
      ars: ars,
      disableRequestCancellation: disableRequestCancellation,
      action: (ct, effectiveArs) async {
        final result = await action(ct, effectiveArs);
        return result.toStateResponse();
      },
    );
  }

  /// Low-level request orchestrator managing [CancelToken] rotation,
  /// loading/refreshing states, obsolete-call suppression, and cancellation revert.
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

    final activeState = Zone.current[#likeActiveState];
    T? currentData;
    LikeStateResponse<T>? resolvedPreviousState = previousState;
    if (activeState is LikeNotifierState) {
      try {
        resolvedPreviousState ??= activeState.value as LikeStateResponse<T>?;
        currentData = activeState.data as T?;
      } catch (_) {}
    }
    currentData ??= resolvedPreviousState?.data;

    if (ars.skip &&
        resolvedPreviousState != null &&
        resolvedPreviousState.isSuccess &&
        resolvedPreviousState.data != null) {
      return resolvedPreviousState;
    }

    final next = disableRequestCancellation ? (ct ?? CancelToken()) : newCT(ct);
    onRotate(next);

    bool checkObsolete() {
      if (_isDisposed) return true;
      if (isObsolete != null) return isObsolete(next);
      if (activeState is LikeNotifierState) return activeState.ct != next;
      return false;
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
      final useSilentLoading = ars.checkAvailability && currentData != null;
      if (ars.refresh || useSilentLoading) {
        if (currentData != null) {
          onUpdate(LikeStateResponse<T>.refreshing(currentData));
        }
      } else {
        onUpdate(LikeStateResponse<T>.loading());
      }
      if (!_isDisposed) notifyListeners();

      final result = await action(next, ars);

      final isCancelledResult =
          result.isError && result.error?.type == LikeApiErrorType.cancelled;
      if (isCancelledResult) {
        final obsolete = checkObsolete();
        if (!obsolete && !_isDisposed) {
          onUpdate(fallbackState);
          notifyListeners();
        }
        return fallbackState;
      }

      if (!checkObsolete()) {
        onUpdate(result);
        if (!_isDisposed) notifyListeners();
      }
      return result;
    } catch (e) {
      final isCancel = e is DioException && CancelToken.isCancel(e);
      final obsolete = checkObsolete();

      if (isCancel) {
        final shouldRevertState =
            !obsolete ||
            (activeState is LikeNotifierState &&
                activeState.ct == null &&
                (activeState.value.isLoading ||
                    activeState.value.isRefreshing));

        if (shouldRevertState && !_isDisposed) {
          onUpdate(fallbackState);
          notifyListeners();
        }
        return fallbackState;
      }

      const userMsg = 'Something went wrong. Please try again.';
      final exception = LikeStateResponse<T>.exception(userMsg, error: e);
      if (!obsolete) {
        onUpdate(exception);
        if (!_isDisposed) notifyListeners();
      }
      return exception;
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final state in _keyedStates.values) {
      if (!state.isDisposed) state.dispose();
    }
    _keyedStates.clear();
    for (final state in _paginatedStates.values) {
      if (!state.isDisposed) state.dispose();
    }
    _paginatedStates.clear();
    for (final state in _registeredStates) {
      state.cancel('Provider disposed');
    }
    _registeredStates.clear();
    for (final token in _responseTokens.values) {
      cancelTokenNow(token, 'Provider disposed');
    }
    _responseTokens.clear();
    _keyedResponses.clear();
    super.dispose();
  }
}
