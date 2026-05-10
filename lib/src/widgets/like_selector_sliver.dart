import 'package:flutter/material.dart';
import 'package:like/src/models/like_error.dart';
import 'package:provider/provider.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/widgets/like_sliver_builder.dart';

/// A specialized sliver version of [LikeSelector] for use in [CustomScrollView].
/// Matches the exact signature of the original StateSelectorSliver.
class LikeSelectorSliver<N, T extends Object> extends StatelessWidget {
  /// Selects the [LikeStateResponse] to observe from a specific notifier [N].
  final LikeStateResponse<dynamic> Function(N notifier) selector;

  /// Builder function called when the selected state contains successful data.
  /// Returns a list of slivers.
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  )
  onSuccess;

  /// Optional builder called when the state is [LikeState.loading].
  final List<Widget> Function()? onLoading;

  /// Optional builder called when the state is [LikeState.idle].
  final List<Widget> Function()? onIdle;

  /// Optional builder called when an explicit [LikeError] occurs.
  final List<Widget> Function(LikeError error)? onError;

  /// Optional builder called when an unexpected exception or system error occurs.
  final List<Widget> Function(String message)? onException;

  /// An optional side-effect listener that triggers every time the selected state changes.
  final void Function(LikeStateResponse<dynamic> response)? listener;

  const LikeSelectorSliver({
    super.key,
    required this.selector,
    required this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
    this.listener,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<N, LikeStateResponse<dynamic>>(
      selector: (context, notifier) => selector(notifier),
      builder: (context, response, _) {
        return LikeSliverBuilder<T>(
          observe: () => response,
          onSuccess: onSuccess,
          onLoading: onLoading,
          onIdle: onIdle,
          onError: onError,
          onException: onException,
          listener: listener,
        );
      },
    );
  }
}
