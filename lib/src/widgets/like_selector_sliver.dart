import 'package:flutter/material.dart';
import 'package:like/src/models/like_error.dart';
import 'package:provider/provider.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/widgets/like_sliver_builder.dart';

/// # `LikeSelectorSliver<N, T>`
///
/// A specialized, performance-optimized layout widget designed to select and observe
/// a specific state from a Provider and render a **List of Slivers** (`List<Widget>`)
/// inside a [CustomScrollView].
///
/// This widget combines the O(1) rebuild filtration of Provider's `Selector`
/// with the frame-efficient scroll rendering of `LikeSliverBuilder`.
///
/// ### Example Usage:
/// ```dart
/// CustomScrollView(
///   slivers: [
///     SliverAppBar(title: Text('Search Results')),
///     LikeSelectorSliver<SearchNotifier, List<SearchResult>>(
///       selector: (notifier) => notifier.searchResultsState, // only rebuilds when searchResultsState changes!
///       onLoading: () => [SliverToBoxAdapter(child: LoadingSpinner())],
///       onSuccess: (results, isRefreshing, isSWR) {
///         return [
///           SliverList(
///             delegate: SliverChildBuilderDelegate(
///               (context, index) => ResultTile(results[index]),
///               childCount: results.length,
///             ),
///           ),
///         ];
///       },
///     ),
///   ],
/// );
/// ```
class LikeSelectorSliver<N, T extends Object> extends StatelessWidget {
  /// **selector**
  ///
  /// A function that receives the notifier [N] from the widget context and returns
  /// the specific [LikeStateResponse] you want this widget to observe.
  final LikeStateResponse<dynamic> Function(N notifier) selector;

  /// **onSuccess**
  ///
  /// The builder function called when the selected state contains successful data.
  ///
  /// Receives:
  /// * `data`: The parsed model object of type [T]. Guaranteed to be non-null.
  /// * `isRefreshing`: True if the user manually triggered a refresh.
  /// * `isFromStaleWhileRevalidate`: True if cached data is currently being displayed.
  ///
  /// Must return a list of sliver widgets.
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// **onLoading**
  ///
  /// Optional builder active when the selected state is loading for the very first time.
  /// Must return a list of sliver widgets.
  final List<Widget> Function()? onLoading;

  /// **onIdle**
  ///
  /// Optional builder active when the selected state is in an uninitialized (idle) phase.
  /// Must return a list of sliver widgets.
  final List<Widget> Function()? onIdle;

  /// **onError**
  ///
  /// Optional builder active when a server-side error is returned.
  /// Receives the [LikeError] payload. Must return a list of sliver widgets.
  final List<Widget> Function(LikeError error)? onError;

  /// **onException**
  ///
  /// Optional builder active when a client-side exception occurs.
  /// Receives the exception string. Must return a list of sliver widgets.
  final List<Widget> Function(String message)? onException;

  /// **listener**
  ///
  /// An optional side-effect callback that triggers whenever the selected state changes.
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
