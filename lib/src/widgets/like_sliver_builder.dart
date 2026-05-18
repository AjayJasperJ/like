import 'package:flutter/material.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_error.dart';

/// A sliver version of [LikeBuilder] for rendering states in a [CustomScrollView].
/// Handles [LikeStateResponse] and provides sticky data support for slivers.
/// Matches the exact signature of the original StateBuilderSliver.
class LikeSliverBuilder<T extends Object> extends StatefulWidget {
  /// A function that returns the current [LikeStateResponse] or [LikeNotifierState] to observe.
  final dynamic Function() observe;

  /// Builder function called when data is successfully retrieved.
  /// Returns a list of sliver widgets.
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  )
  onSuccess;

  /// Optional builder called when the initial load is in progress.
  final List<Widget> Function()? onLoading;

  /// Optional builder called when the state is [LikeState.idle].
  final List<Widget> Function()? onIdle;

  /// Optional builder called when an explicit [LikeError] occurs.
  final List<Widget> Function(LikeError error)? onError;

  /// Optional builder called when an unexpected exception or system error occurs.
  final List<Widget> Function(String message)? onException;

  /// An optional side-effect listener that triggers every time the observed state changes.
  final void Function(LikeStateResponse<dynamic> response)? listener;

  const LikeSliverBuilder({
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
  State<LikeSliverBuilder<T>> createState() => _LikeSliverBuilderState<T>();
}

class _LikeSliverBuilderState<T extends Object>
    extends State<LikeSliverBuilder<T>> {
  LikeStateResponse<dynamic>? _lastNotifiedResponse;
  T? _lastSuccessfulData;

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

    // Update sticky data
    final casted = _castData(response.data);
    if (casted != null) {
      _lastSuccessfulData = casted;
    }

    return SliverMainAxisGroup(
      slivers: () {
        switch (response.state) {
          case LikeState.idle:
            return widget.onIdle?.call() ?? [];

          case LikeState.loading:
            if (_lastSuccessfulData != null) {
              return widget.onSuccess(_lastSuccessfulData!, true, false);
            }
            return widget.onLoading?.call() ?? [];

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
            return widget.onError?.call(response.error!) ?? [];

          case LikeState.exception:
            return widget.onException?.call(response.message) ?? [];
        }
      }(),
    );
  }
}

/// A specialized version of [LikeSliverBuilder] that takes a [LikeStateResponse] directly.
/// Useful when you already have the response object and need to render slivers.
class LikeStateResponseBuilderSliver<T extends Object> extends StatelessWidget {
  /// The [LikeStateResponse] to build the slivers from.
  final LikeStateResponse<T> response;

  /// Builder function called when data is successfully retrieved.
  /// Returns a list of slivers.
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  )
  onSuccess;

  /// Optional builder called when the initial load is in progress.
  final List<Widget> Function()? onLoading;

  /// Optional builder called when the state is [LikeState.idle].
  final List<Widget> Function()? onIdle;

  /// Optional builder called when an explicit [LikeError] occurs.
  final List<Widget> Function(LikeError error)? onError;

  /// Optional builder called when an unexpected exception or system error occurs.
  final List<Widget> Function(String message)? onException;

  const LikeStateResponseBuilderSliver({
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
    return LikeSliverBuilder<T>(
      observe: () => response,
      onSuccess: onSuccess,
      onLoading: onLoading,
      onIdle: onIdle,
      onError: onError,
      onException: onException,
    );
  }
}
