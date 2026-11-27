import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_state_response.dart';

/// Backwards-compatible alias for [LikeResponseSliver].
typedef LikeStateResponseBuilderSliver<T extends Object> = LikeResponseSliver<T>;

T? _castSliverData<T extends Object>(dynamic data) {
  if (data == null) return null;
  if (data is T) return data;
  try {
    return data as T;
  } catch (_) {
    assert(
      false,
      'LikeSliverBuilder: Type cast failed. Expected $T, got ${data.runtimeType}. '
      'Check the generic type argument on LikeSliverBuilder<T>.',
    );
    return null;
  }
}

Widget _buildLikeSliverWidget<T extends Object>({
  required LikeStateResponse<dynamic> response,
  required List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess,
  List<Widget> Function()? onLoading,
  List<Widget> Function()? onIdle,
  List<Widget> Function(LikeError error)? onError,
  List<Widget> Function(String message, LikeError? error)? onException,
}) {
  final List<Widget> slivers;
  switch (response.state) {
    case LikeState.idle:
      slivers = onIdle?.call() ?? const [];

    case LikeState.loading:
      slivers =
          onLoading?.call() ??
          const [
            SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
          ];

    case LikeState.success:
    case LikeState.refreshing:
    case LikeState.staleWhileRevalidate:
      final casted = _castSliverData<T>(response.data);
      if (casted == null) {
        throw StateError(
          'Success/Refreshing/SWR state requires non-null data. '
          'Expected type: $T, Received: ${response.data?.runtimeType ?? "null"}',
        );
      }
      slivers = onSuccess(
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
      slivers = onError?.call(err) ?? const [];

    case LikeState.exception:
      slivers = onException?.call(response.message, response.error) ?? const [];
  }

  return SliverMainAxisGroup(slivers: slivers);
}

/// # `LikeSliverBuilder<T>`
///
/// A sliver-compatible version of [LikeBuilder] for rendering network lifecycle
/// states directly inside a [CustomScrollView].
class LikeSliverBuilder<T extends Object> extends StatefulWidget {
  /// Closure returning either a [LikeNotifierState<T>] / [ValueListenable]
  /// or an immutable [LikeStateResponse<T>].
  final dynamic Function() observe;

  /// Builder called when data resolves successfully. Must return a list of slivers.
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// Optional loading builder. Defaults to a centered loader inside `SliverFillRemaining`.
  final List<Widget> Function()? onLoading;

  /// Optional idle builder.
  final List<Widget> Function()? onIdle;

  /// Optional error builder.
  final List<Widget> Function(LikeError error)? onError;

  /// Optional exception builder.
  final List<Widget> Function(String message, LikeError? error)? onException;

  /// Optional side-effect callback triggered post-frame when state changes.
  final void Function(LikeStateResponse<dynamic> response)? listener;

  /// Optional predicate to skip rebuilding when [previous] and [next]
  /// represent no visual change.
  final bool Function(
    LikeStateResponse<dynamic> previous,
    LikeStateResponse<dynamic> next,
  )? buildWhen;

  /// Optional selector on success [T] data.
  final Object? Function(T data)? selector;

  const LikeSliverBuilder({
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
  State<LikeSliverBuilder<T>> createState() => _LikeSliverBuilderState<T>();
}

class _LikeSliverBuilderState<T extends Object>
    extends State<LikeSliverBuilder<T>> {
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
  void didUpdateWidget(covariant LikeSliverBuilder<T> oldWidget) {
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
      'LikeSliverBuilder.observe() must return either a Listenable (e.g. a LikeNotifierState) '
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
      final casted = _castSliverData<T>(next.data);
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
      _notifyListenerIfNeeded(next);
      if (_shouldSkipRebuild(_lastRenderedResponse, next)) return;
      _filteredNotifier?.value = next;
    }
  }

  Widget _renderResponse(LikeStateResponse<dynamic> response) {
    _lastRenderedResponse = response;
    _notifyListenerIfNeeded(response);

    final casted = _castSliverData<T>(response.data);
    if (widget.selector != null && casted != null) {
      _lastSelectedValue = widget.selector!(casted);
      _hasSelectedValue = true;
    } else {
      _hasSelectedValue = false;
      _lastSelectedValue = null;
    }

    return _buildLikeSliverWidget<T>(
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

    if (rawObserved is! Listenable) {
      return _renderResponse(_resolveResponse(rawObserved));
    }

    if (!_needsFiltering &&
        (rawObserved is LikeNotifierState ||
            rawObserved is ValueListenable<LikeStateResponse<dynamic>>)) {
      return ListenableBuilder(
        listenable: rawObserved,
        builder: (context, _) => _renderResponse(_resolveResponse(rawObserved)),
      );
    }

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

/// # `LikeNotifierSliver<T>`
///
/// Dedicated sliver builder for [LikeNotifierState<T>] (`ValueNotifier`-based state).
/// Uses [ValueListenableBuilder] directly when [buildWhen] and [selector] are omitted.
class LikeNotifierSliver<T extends Object> extends StatelessWidget {
  final LikeNotifierState<T> state;
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;
  final List<Widget> Function()? onLoading;
  final List<Widget> Function()? onIdle;
  final List<Widget> Function(LikeError error)? onError;
  final List<Widget> Function(String message, LikeError? error)? onException;
  final void Function(LikeStateResponse<dynamic> response)? listener;
  final bool Function(
    LikeStateResponse<dynamic> previous,
    LikeStateResponse<dynamic> next,
  )? buildWhen;
  final Object? Function(T data)? selector;

  const LikeNotifierSliver({
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
        builder: (context, _) => _buildLikeSliverWidget<T>(
          response: state.value,
          onSuccess: onSuccess,
          onLoading: onLoading,
          onIdle: onIdle,
          onError: onError,
          onException: onException,
        ),
      );
    }
    return LikeSliverBuilder<T>(
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

/// # `LikeResponseSliver<T>`
///
/// Pure [StatelessWidget] sliver builder for immutable [LikeStateResponse<T>] snapshots
/// (ideal with `Provider` / `Selector`, `Riverpod`, `BLoC`, or `LikeChangeNotifier.getResponseByKey`).
/// Allocates zero `State` or `ValueNotifier` objects.
class LikeResponseSliver<T extends Object> extends StatelessWidget {
  /// The [LikeStateResponse] to build the slivers from.
  final LikeStateResponse<T> response;

  /// Builder function called when data is successfully retrieved.
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// Optional builder called when the initial load is in progress.
  final List<Widget> Function()? onLoading;

  /// Optional builder called when the state is [LikeState.idle].
  final List<Widget> Function()? onIdle;

  /// Optional builder called when an explicit [LikeError] occurs.
  final List<Widget> Function(LikeError error)? onError;

  /// Optional builder called when an unexpected exception or system error occurs.
  final List<Widget> Function(String message, LikeError? error)? onException;

  const LikeResponseSliver({
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
    return _buildLikeSliverWidget<T>(
      response: response,
      onSuccess: onSuccess,
      onLoading: onLoading,
      onIdle: onIdle,
      onError: onError,
      onException: onException,
    );
  }
}
