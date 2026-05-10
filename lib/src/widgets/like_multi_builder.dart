import 'package:flutter/material.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/widgets/like_multi_helper.dart';

/// A builder that observes multiple [LikeStateResponse]s and aggregates their states.
/// It waits for all states to resolve before calling [onSuccess].
/// Matches the exact signature of the original MultiStateBuilder.
class LikeMultiBuilder extends StatefulWidget {
  /// A list of functions, each returning a [LikeStateResponse] to monitor.
  final List<LikeStateResponse<dynamic> Function()> observes;

  /// Builder function called when all observed states have successfully retrieved data.
  /// Provides the list of results in the same order as [observes].
  final Widget Function(
    List<dynamic> results,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  )
  onSuccess;

  /// Optional builder called when at least one state is in [LikeState.loading].
  /// Supports sticky behavior: if [onSuccess] was previously called, it remains visible.
  final Widget Function()? onLoading;

  /// Optional builder called when at least one state is in [LikeState.idle].
  final Widget Function()? onIdle;

  /// Optional builder called when at least one state has an explicit [LikeError].
  final Widget Function(LikeError error)? onError;

  /// Optional builder called when at least one state has an unexpected exception.
  final Widget Function(String message)? onException;

  /// An optional side-effect listener that triggers when the aggregated state or individual responses change.
  final void Function(
    LikeState aggregatedState,
    List<LikeStateResponse<dynamic>> responses,
  )?
  listener;

  const LikeMultiBuilder({
    super.key,
    required this.observes,
    required this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
    this.listener,
  });

  @override
  State<LikeMultiBuilder> createState() => _LikeMultiBuilderState();
}

class _LikeMultiBuilderState extends State<LikeMultiBuilder> {
  List<dynamic>? _lastSuccessfulResults;
  LikeState? _lastAggregatedState;

  @override
  Widget build(BuildContext context) {
    final responses = widget.observes.map((o) => o()).toList();
    final aggregatedState = LikeMultiHelper.aggregate(responses);

    // Update sticky data
    final hasResolvedAll = responses.every((r) => r.data != null);
    if (hasResolvedAll) {
      _lastSuccessfulResults = responses.map((r) => r.data).toList();
    }

    if (widget.listener != null && _lastAggregatedState != aggregatedState) {
      _lastAggregatedState = aggregatedState;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.listener!(aggregatedState, responses);
      });
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: () {
        switch (aggregatedState) {
          case LikeState.exception:
            final first = responses.firstWhere(
              (r) => r.isException,
              orElse: () => responses.first,
            );
            return widget.onException?.call(first.message) ??
                const SizedBox.shrink();

          case LikeState.error:
            final first = responses.firstWhere(
              (r) => r.isError,
              orElse: () => responses.first,
            );
            return widget.onError?.call(first.error!) ??
                const SizedBox.shrink();

          case LikeState.idle:
            return widget.onIdle?.call() ?? const SizedBox.shrink();

          case LikeState.loading:
            if (_lastSuccessfulResults != null) {
              return widget.onSuccess(_lastSuccessfulResults!, true, false);
            }
            return widget.onLoading?.call() ??
                const Center(child: CircularProgressIndicator());

          case LikeState.success:
          case LikeState.refreshing:
          case LikeState.staleWhileRevalidate:
            final results = responses.map((r) => r.data).toList();
            final isRefreshing = responses.any((r) => r.isRefreshing);
            final isStaleWhileRevalidate = responses.any(
              (r) => r.isStaleWhileRevalidate || r.isFromStaleWhileRevalidate,
            );
            return widget.onSuccess(
              results,
              isRefreshing,
              isStaleWhileRevalidate,
            );
        }
      }(),
    );
  }
}
