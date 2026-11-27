import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_state_response.dart';

/// Backwards-compatible alias for [LikeResponseBuilder].
typedef LikeStateResponseBuilder<T> = LikeResponseBuilder<T>;

T? _castLikeData<T>(dynamic data) {
  if (data == null) return null;
  if (data is T) return data;
  try {
    return data as T;
  } catch (_) {
    assert(
      false,
      'LikeBuilder: Type cast failed. Expected $T, got ${data.runtimeType}. '
      'Check the generic type argument on LikeBuilder<T>.',
    );
    return null;
  }
}

Widget _buildLikeStateWidget<T>({
  required LikeStateResponse<dynamic> response,
  required Widget Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess,
  Widget Function()? onLoading,
  Widget Function()? onIdle,
  Widget Function(LikeError error)? onError,
  Widget Function(String message, LikeError? error)? onException,
}) {
  switch (response.state) {
    case LikeState.idle:
      return onIdle?.call() ?? const SizedBox.shrink();

    case LikeState.loading:
      return onLoading?.call() ??
          const Center(child: CircularProgressIndicator());

    case LikeState.success:
    case LikeState.refreshing:
    case LikeState.staleWhileRevalidate:
      final casted = _castLikeData<T>(response.data);
      if (casted == null) {
        throw StateError(
          'Success/Refreshing/SWR state requires non-null data. '
          'Expected type: $T, Received: ${response.data?.runtimeType ?? "null"}',
        );
      }
      return onSuccess(
        casted,
        response.state == LikeState.refreshing,
        response.state == LikeState.staleWhileRevalidate ||
            response.isFromStaleWhileRevalidate,
      );

    case LikeState.error:
      final err =
          response.error ??
          LikeError(
            message: response.message,
            type: response.errorType ?? LikeApiErrorType.unknown,
          );
      return onError?.call(err) ?? const SizedBox.shrink();

    case LikeState.exception:
      return onException?.call(response.message, response.error) ??
          const SizedBox.shrink();
  }
}

/// # `LikeBuilder<T>`
///
/// A reactive Flutter widget designed to manage and render UI dynamically
/// based on [LikeStateResponse] lifecycles.
///
/// Uses [ValueListenableBuilder] directly when observing a [LikeNotifierState]
/// (or any [ValueListenable<LikeStateResponse>]) without `buildWhen`/`selector`,
/// and only attaches a filtering [ValueNotifier] bridge when `buildWhen` or
/// `selector` is provided.
class LikeBuilder<T> extends StatefulWidget {
  /// Closure returning either a [LikeNotifierState<T>] / [ValueListenable]
  /// or a direct immutable [LikeStateResponse<T>].
  final dynamic Function() observe;

  /// Builder called when data is available (`success`, `refreshing`, or `staleWhileRevalidate`).
  final Widget Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// Optional builder for [LikeState.loading]. Defaults to a centered [CircularProgressIndicator].
  final Widget Function()? onLoading;

  /// Optional builder for [LikeState.idle]. Defaults to [SizedBox.shrink].
  final Widget Function()? onIdle;

  /// Optional builder for [LikeState.error].
  final Widget Function(LikeError error)? onError;

  /// Optional builder for [LikeState.exception].
  final Widget Function(String message, LikeError? error)? onException;

  /// Optional side-effect callback triggered post-frame whenever the observed state changes,
  /// even if [buildWhen] or [selector] skips a UI rebuild.
  final void Function(LikeStateResponse<dynamic> response)? listener;

  /// Optional predicate to skip rebuilding when [previous] and [next]
  /// represent no visual change for this widget.
  final bool Function(
    LikeStateResponse<dynamic> previous,
    LikeStateResponse<dynamic> next,
  )? buildWhen;

  /// Optional selector on success [T] data. When provided, consecutive
  /// success/refreshing/SWR notifications with equal selected values skip rebuilds.
  final Object? Function(T data)? selector;

  const LikeBuilder({
    super.key,
    required this.observe,
    required this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
    this.listener,
    this.buildWhen,
    this.selector,
  });

  @override
  State<LikeBuilder<T>> createState() => _LikeBuilderState<T>();
}

class _LikeBuilderState<T> extends State<LikeBuilder<T>> {
  LikeStateResponse<dynamic>? _lastNotifiedResponse;
  LikeStateResponse<dynamic>? _lastRenderedResponse;
  Object? _lastSelectedValue;
  bool _hasSelectedValue = false;
  Listenable? _observedListenable;
  ValueNotifier<LikeStateResponse<dynamic>>? _filteredNotifier;

  bool get _needsFiltering =>
      widget.buildWhen != null || widget.selector != null;

  @override
  void initState() {
    super.initState();
    final rawObserved = widget.observe();
    _resolveResponse(rawObserved);
    _syncSubscription(rawObserved);
  }

  @override
  void didUpdateWidget(covariant LikeBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rawObserved = widget.observe();
    final prevListenable = _observedListenable;
    _syncSubscription(rawObserved);

    if (_filteredNotifier != null) {
      final resolved = _resolveResponse(rawObserved);
      final listenableChanged = !identical(
        rawObserved is Listenable ? rawObserved : null,
        prevListenable,
      );
      if (listenableChanged || resolved != _filteredNotifier!.value) {
        final oldNotifier = _filteredNotifier!;
        _filteredNotifier = ValueNotifier<LikeStateResponse<dynamic>>(resolved);
        WidgetsBinding.instance.addPostFrameCallback((_) => oldNotifier.dispose());
      }
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    _filteredNotifier?.dispose();
    super.dispose();
  }

  LikeStateResponse<dynamic> _resolveResponse(dynamic rawObserved) {
    assert(
      rawObserved is Listenable || rawObserved is LikeStateResponse,
      'LikeBuilder.observe() must return either a Listenable (e.g. a LikeNotifierState) '
      'or a direct LikeStateResponse. '
      'Received: ${rawObserved.runtimeType}. '
      'Hint: use `observe: () => provider.myState` '
      'not `observe: () => provider.myState.value`.',
    );
    if (rawObserved is ValueListenable<LikeStateResponse<dynamic>>) {
      return rawObserved.value;
    }
    if (rawObserved is LikeNotifierState) {
      return rawObserved.value;
    }
    return rawObserved as LikeStateResponse<dynamic>;
  }

  void _syncSubscription(dynamic rawObserved) {
    final nextListenable = rawObserved is Listenable ? rawObserved : null;
    final hasTypedValue =
        nextListenable is LikeNotifierState ||
        nextListenable is ValueListenable<LikeStateResponse<dynamic>>;
    final needsBridge =
        nextListenable != null && (_needsFiltering || !hasTypedValue);

    if (!needsBridge) {
      _unsubscribe();
      final old = _filteredNotifier;
      _filteredNotifier = null;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      return;
    }

    _filteredNotifier ??= ValueNotifier<LikeStateResponse<dynamic>>(
      _resolveResponse(rawObserved),
    );

    if (identical(nextListenable, _observedListenable)) return;
    _unsubscribe();
    _observedListenable = nextListenable;
    _observedListenable!.addListener(_handleUpdate);
  }

  void _unsubscribe() {
    if (_observedListenable != null) {
      _observedListenable!.removeListener(_handleUpdate);
      _observedListenable = null;
    }
  }

  void _notifyListenerIfNeeded(LikeStateResponse<dynamic> response) {
    if (widget.listener != null && _lastNotifiedResponse != response) {
      _lastNotifiedResponse = response;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.listener!(response);
      });
    }
  }

  bool _shouldSkipRebuild(
    LikeStateResponse<dynamic>? prev,
    LikeStateResponse<dynamic> next,
  ) {
    if (prev == null) return false;
    if (prev == next) return true;
    if (widget.buildWhen != null && !widget.buildWhen!(prev, next)) {
      return true;
    }
    if (widget.selector != null &&
        _hasSelectedValue &&
        prev.state == next.state &&
        prev.isFromStaleWhileRevalidate == next.isFromStaleWhileRevalidate) {
      final casted = _castLikeData<T>(next.data);
      if (casted != null && widget.selector!(casted) == _lastSelectedValue) {
        return true;
      }
    }
    return false;
  }

  void _handleUpdate() {
    if (!mounted) return;
    final current = _observedListenable;
    if (current is ValueListenable<LikeStateResponse<dynamic>> ||
        current is LikeNotifierState) {
      final next = _resolveResponse(current);
      // Always fire side-effect listener even if UI rebuild is skipped.
      _notifyListenerIfNeeded(next);
      if (_shouldSkipRebuild(_lastRenderedResponse, next)) return;
      _filteredNotifier?.value = next;
    }
  }

  Widget _renderResponse(LikeStateResponse<dynamic> response) {
    _lastRenderedResponse = response;
    _notifyListenerIfNeeded(response);

    final casted = _castLikeData<T>(response.data);
    if (widget.selector != null && casted != null) {
      _lastSelectedValue = widget.selector!(casted);
      _hasSelectedValue = true;
    } else {
      _hasSelectedValue = false;
      _lastSelectedValue = null;
    }

    return _buildLikeStateWidget<T>(
      response: response,
      onSuccess: widget.onSuccess,
      onLoading: widget.onLoading,
      onIdle: widget.onIdle,
      onError: widget.onError,
      onException: widget.onException,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawObserved = widget.observe();

    // Direct immutable snapshot (no Listenable): render without ValueListenableBuilder.
    if (rawObserved is! Listenable) {
      return _renderResponse(_resolveResponse(rawObserved));
    }

    // Fast path: pass LikeNotifierState / ValueListenable straight to ListenableBuilder.
    if (!_needsFiltering &&
        (rawObserved is LikeNotifierState ||
            rawObserved is ValueListenable<LikeStateResponse<dynamic>>)) {
      return ListenableBuilder(
        listenable: rawObserved,
        builder: (context, _) => _renderResponse(_resolveResponse(rawObserved)),
      );
    }

    // Filtered path: buildWhen / selector / generic Listenable.
    final notifier = _filteredNotifier;
    if (notifier == null) {
      return _renderResponse(_resolveResponse(rawObserved));
    }
    return ValueListenableBuilder<LikeStateResponse<dynamic>>(
      valueListenable: notifier,
      builder: (context, response, _) => _renderResponse(response),
    );
  }
}

/// # `LikeNotifierBuilder<T>`
///
/// Dedicated builder for [LikeNotifierState<T>] (`ValueNotifier`-based state).
/// Uses [ValueListenableBuilder] directly when [buildWhen] and [selector] are omitted.
class LikeNotifierBuilder<T> extends StatelessWidget {
  final LikeNotifierState<T> state;
  final Widget Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;
  final Widget Function()? onLoading;
  final Widget Function()? onIdle;
  final Widget Function(LikeError error)? onError;
  final Widget Function(String message, LikeError? error)? onException;
  final void Function(LikeStateResponse<dynamic> response)? listener;
  final bool Function(
    LikeStateResponse<dynamic> previous,
    LikeStateResponse<dynamic> next,
  )? buildWhen;
  final Object? Function(T data)? selector;

  const LikeNotifierBuilder({
    super.key,
    required this.state,
    required this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
    this.listener,
    this.buildWhen,
    this.selector,
  });

  @override
  Widget build(BuildContext context) {
    if (buildWhen == null && selector == null && listener == null) {
      return ListenableBuilder(
        listenable: state,
        builder: (context, _) => _buildLikeStateWidget<T>(
          response: state.value,
          onSuccess: onSuccess,
          onLoading: onLoading,
          onIdle: onIdle,
          onError: onError,
          onException: onException,
        ),
      );
    }
    return LikeBuilder<T>(
      observe: () => state,
      onSuccess: onSuccess,
      onLoading: onLoading,
      onIdle: onIdle,
      onError: onError,
      onException: onException,
      listener: listener,
      buildWhen: buildWhen,
      selector: selector,
    );
  }
}

/// # `LikeResponseBuilder<T>`
///
/// Pure [StatelessWidget] builder for immutable [LikeStateResponse<T>] snapshots
/// (ideal with `Provider` / `Selector`, `Riverpod`, `BLoC`, or `LikeChangeNotifier.getResponseByKey`).
/// Allocates zero `State` or `ValueNotifier` objects.
class LikeResponseBuilder<T> extends StatelessWidget {
  /// The immutable [LikeStateResponse] snapshot to render.
  final LikeStateResponse<T> response;

  /// Builder function called when data is successfully retrieved.
  final Widget Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// Optional builder called when the initial data load is in progress.
  final Widget Function()? onLoading;

  /// Optional builder called when the state is [LikeState.idle].
  final Widget Function()? onIdle;

  /// Optional builder called when an explicit [LikeError] occurs.
  final Widget Function(LikeError error)? onError;

  /// Optional builder called when an unexpected exception or system error occurs.
  final Widget Function(String message, LikeError? error)? onException;

  const LikeResponseBuilder({
    super.key,
    required this.response,
    required this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
  });

  @override
  Widget build(BuildContext context) {
    return _buildLikeStateWidget<T>(
      response: response,
      onSuccess: onSuccess,
      onLoading: onLoading,
      onIdle: onIdle,
      onError: onError,
      onException: onException,
    );
  }
}
