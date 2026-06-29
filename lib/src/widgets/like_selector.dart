import 'package:flutter/material.dart';
import 'package:like/src/models/like_error.dart';
import 'package:provider/provider.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/widgets/like_builder.dart';

/// # `LikeSelector<N, T>`
///
/// A performance-optimized state management widget designed for complex screens
/// powered by the `provider` package.
///
/// It integrates standard `LikeBuilder` state rendering with Provider's `Selector`
/// optimization pattern.
///
/// ### Why is this useful? (The "Selector" Advantage)
/// Normally, using `context.watch<MyNotifier>()` causes your widget to rebuild *every single time*
/// **any** property inside `MyNotifier` changes, even if your widget doesn't care about that property.
///
/// `LikeSelector` solves this. It filters state updates so that your widget **only rebuilds** when
/// the *specific* `LikeStateResponse` selected by your [selector] function actually mutates.
///
/// ### Example Usage:
/// ```dart
/// LikeSelector<DashboardNotifier, List<NewsItem>>(
///   // N is DashboardNotifier (the provider)
///   // T is List<NewsItem> (the resolved success data type)
///   selector: (context, notifier) => notifier.newsState, // only rebuilds when newsState changes!
///   onLoading: () => CircularProgressIndicator(),
///   onSuccess: (newsList, isRefreshing, isSWR) {
///     return ListView.builder(
///       itemCount: newsList.length,
///       itemBuilder: (context, index) => NewsCard(newsList[index]),
///     );
///   },
/// );
/// ```
class LikeSelector<N, T> extends StatelessWidget {
  /// **selector**
  ///
  /// A selector function that receives the notifier [N] from the widget context and returns
  /// the specific [LikeStateResponse] you want this widget to observe.
  final LikeStateResponse<dynamic> Function(BuildContext context, N notifier)
      selector;

  /// **builder**
  ///
  /// An optional builder function providing full granular control over both the [LikeStateResponse]
  /// and the pre-built [child] widget.
  /// * **Note:** If you supply [builder], then [onSuccess], [onLoading], [onError], and other specific
  ///   sub-builders are completely ignored.
  final Widget Function(
    BuildContext context,
    LikeStateResponse<dynamic> response,
    Widget? child,
  )? builder;

  /// **onSuccess**
  ///
  /// The builder function called when the selected state contains successful data.
  ///
  /// Receives:
  /// * `data`: The parsed model object of type [T]. Guaranteed to be non-null.
  /// * `isRefreshing`: True if the user manually triggered a refresh.
  /// * `isFromStaleWhileRevalidate`: True if cached data is currently being displayed.
  final Widget Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  )? onSuccess;

  /// **onLoading**
  ///
  /// Optional builder active when the selected state is loading for the very first time.
  final Widget Function()? onLoading;

  /// **onIdle**
  ///
  /// Optional builder active when the selected state is in an idle, uninitialized phase.
  final Widget Function()? onIdle;

  /// **onError**
  ///
  /// Optional builder active when a server-side error is returned.
  final Widget Function(LikeError error)? onError;

  /// **onException**
  ///
  /// Optional builder active when a client-side exception occurs.
  final Widget Function(String message)? onException;

  /// **listener**
  ///
  /// An optional side-effect callback that triggers whenever the selected state changes.
  final void Function(LikeStateResponse<dynamic> response)? listener;

  /// **child**
  ///
  /// An optional, pre-built constant child widget that is passed to your custom [builder].
  /// Useful to prevent rebuilding static elements of your page.
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
