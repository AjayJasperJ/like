import 'package:flutter/material.dart';
import 'package:like/src/models/like_error.dart';
import 'package:provider/provider.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/widgets/like_builder.dart';

/// A specialized version of [LikeBuilder] that integrates with the [Selector]
/// pattern from the `provider` package.
///
/// This widget is highly efficient as it only rebuilds when the specific
/// [LikeStateResponse] returned by the [selector] actually changes.
///
/// Ideal for screens that listen to multiple properties from the same provider.
class LikeSelector<N, T> extends StatelessWidget {
  /// Selects the [LikeStateResponse] to observe from a specific notifier [N].
  final LikeStateResponse<dynamic> Function(BuildContext context, N notifier)
  selector;

  /// A custom builder that gives you full control over the [LikeStateResponse] and [child].
  /// If provided, [onSuccess] and other specific builders are ignored.
  final Widget Function(
    BuildContext context,
    LikeStateResponse<dynamic> response,
    Widget? child,
  )?
  builder;

  /// Builder function called when the selected state contains successful data.
  final Widget Function(T data, bool isRefreshing, bool isFromStaleWhileRevalidate)? onSuccess;

  /// Optional builder called when the state is [LikeState.loading].
  final Widget Function()? onLoading;

  /// Optional builder called when the state is [LikeState.idle].
  final Widget Function()? onIdle;

  /// Optional builder called when an explicit [LikeError] occurs.
  final Widget Function(LikeError error)? onError;

  /// Optional builder called when an unexpected exception or system error occurs.
  final Widget Function(String message)? onException;

  /// An optional side-effect listener that triggers every time the selected state changes.
  final void Function(LikeStateResponse<dynamic> response)? listener;

  /// An optional constant child widget that is passed to [builder].
  final Widget? child;

  const LikeSelector({
    super.key,
    required this.selector,
    this.builder,
    this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
    this.listener,
    this.child,
  }) : assert(
         builder != null || onSuccess != null,
         'Either builder or onSuccess must be provided',
       );

  @override
  Widget build(BuildContext context) {
    return Selector<N, LikeStateResponse<dynamic>>(
      selector: selector,
      builder: (context, response, child) {
        if (builder != null) {
          return builder!(context, response, child);
        }
        return LikeBuilder<T>(
          observe: () => response,
          onSuccess: onSuccess!,
          onLoading: onLoading,
          onIdle: onIdle,
          onError: onError,
          onException: onException,
          listener: listener,
        );
      },
      child: child,
    );
  }
}
