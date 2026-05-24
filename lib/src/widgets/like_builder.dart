import 'package:flutter/material.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_error.dart';

/// A state management builder widget that handles [LikeStateResponse] with
/// SWR (stale-while-revalidate) support.
/// Matches the exact signature of the original StateBuilder for seamless integration.
class LikeBuilder<T> extends StatefulWidget {
  /// A function that returns the current [LikeStateResponse] or [LikeNotifierState] to observe.
  /// Usually returns a property from a provider or state manager.
  final dynamic Function() observe;

  /// Builder function called when data is successfully retrieved.
  ///
  /// This builder supports "Sticky Data":
  /// * Also called during [LikeState.refreshing] and [LikeState.staleWhileRevalidate]
  ///   to ensure the UI never flickers to a loading state while new data is
  ///   being fetched in the background.
  /// * [isRefreshing] is true if an explicit refresh (e.g. pull-to-refresh) is active.
  /// * [isFromStaleWhileRevalidate] is true if cached data is being displayed
  ///   while a background network update is in progress.
  final Widget Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// Optional builder called when the initial data load is in progress.
  /// If [onSuccess] was previously called, [LikeBuilder] will continue to show
  /// the old data via [onSuccess] (sticky behavior) instead of switching to [onLoading].
  final Widget Function()? onLoading;

  /// Optional builder called when the state is [LikeState.idle].
  final Widget Function()? onIdle;

  /// Optional builder called when an explicit [LikeError] occurs.
  final Widget Function(LikeError error)? onError;

  /// Optional builder called when an unexpected exception or system error occurs.
  final Widget Function(String message)? onException;

  /// An optional side-effect listener that triggers every time the observed state changes.
  /// Useful for showing Toasts, Snackerbars, or navigating based on state.
  final void Function(LikeStateResponse<dynamic> response)? listener;

  const LikeBuilder({
    super.key,
    required this.observe,
    required this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
    this.listener,
  });

  @override
  State<LikeBuilder<T>> createState() => _LikeBuilderState<T>();
}

class _LikeBuilderState<T> extends State<LikeBuilder<T>> {
  LikeStateResponse<dynamic>? _lastNotifiedResponse;
  Listenable? _observedListenable;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant LikeBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unsubscribe();
    _subscribe();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    final rawObserved = widget.observe();
    if (rawObserved is Listenable) {
      _observedListenable = rawObserved;
      _observedListenable!.addListener(_handleUpdate);
    }
  }

  void _unsubscribe() {
    if (_observedListenable != null) {
      _observedListenable!.removeListener(_handleUpdate);
      _observedListenable = null;
    }
  }

  void _handleUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  T? _castData(dynamic data) {
    if (data == null) return null;
    if (data is T) return data;
    try {
      return data as T;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawObserved = widget.observe();
    final response = rawObserved is LikeNotifierState
        ? rawObserved.value
        : rawObserved as LikeStateResponse<dynamic>;

    if (widget.listener != null && _lastNotifiedResponse != response) {
      _lastNotifiedResponse = response;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.listener!(response);
      });
    }

    final casted = _castData(response.data);

    switch (response.state) {
      case LikeState.idle:
        return widget.onIdle?.call() ?? const SizedBox.shrink();

      case LikeState.loading:
        return widget.onLoading?.call() ??
            const Center(child: CircularProgressIndicator());

      case LikeState.success:
      case LikeState.refreshing:
      case LikeState.staleWhileRevalidate:
        if (casted == null) {
          throw StateError(
            'Success/Refreshing/SWR state requires non-null data. '
            'Expected type: $T, Received: ${response.data?.runtimeType ?? "null"}',
          );
        }
        return widget.onSuccess(
          casted,
          response.state == LikeState.refreshing,
          response.state == LikeState.staleWhileRevalidate ||
              response.isFromStaleWhileRevalidate,
        );

      case LikeState.error:
        return widget.onError?.call(response.error!) ?? const SizedBox.shrink();

      case LikeState.exception:
        return widget.onException?.call(response.message) ??
            const SizedBox.shrink();
    }
  }
}

/// A specialized version of [LikeBuilder] that takes a [LikeStateResponse] directly.
/// Useful when you already have the response object (e.g. from a Stream or local variable).
class LikeStateResponseBuilder<T> extends StatelessWidget {
  /// The [LikeStateResponse] to build the UI from.
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
  final Widget Function(String message)? onException;

  const LikeStateResponseBuilder({
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
    return LikeBuilder<T>(
      observe: () => response,
      onSuccess: onSuccess,
      onLoading: onLoading,
      onIdle: onIdle,
      onError: onError,
      onException: onException,
    );
  }
}
