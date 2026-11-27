import 'dart:async';

import 'package:flutter/widgets.dart';

/// # `LikeInfiniteScroll`
///
/// A lightweight [StatelessWidget] wrapper around [NotificationListener<ScrollNotification>]
/// that triggers [onLoadMore] when the wrapped scrollable approaches the end of its
/// scroll extent (within [threshold] logical pixels).
///
/// Always returns `false` from `onNotification` so parent widgets such as
/// [RefreshIndicator] or [Scrollbar] continue receiving scroll notifications.
class LikeInfiniteScroll extends StatelessWidget {
  /// The scrollable widget (e.g. [ListView], [GridView], [CustomScrollView]) to observe.
  final Widget child;

  /// Callback invoked when the scroll position reaches within [threshold] of the end
  /// while [hasMore] is `true` and [isLoadingMore] is `false`.
  final FutureOr<void> Function() onLoadMore;

  /// Whether more pages/items are available to load (e.g.
  /// `feed.hasMore && !feed.isLoadingMore && feed.loadMoreError == null`).
  final bool hasMore;

  /// Distance in logical pixels from the end of the scrollable at which
  /// [onLoadMore] triggers. Defaults to `200.0`.
  final double threshold;

  /// Axis filter. Defaults to [Axis.vertical] so horizontal scrollables
  /// (e.g. carousels or `TabBarView`) do not trigger load-more. Pass `null`
  /// to allow any axis, or [Axis.horizontal] for horizontal lists.
  final Axis? scrollDirection;

  /// Optional predicate to filter which [ScrollNotification]s are handled.
  /// Defaults to `notification.depth == 0` so nested scrollables are ignored.
  final bool Function(ScrollNotification notification)? notificationPredicate;

  const LikeInfiniteScroll({
    super.key,
    required this.child,
    required this.onLoadMore,
    this.hasMore = true,
    this.threshold = 200.0,
    this.scrollDirection = Axis.vertical,
    this.notificationPredicate,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!hasMore) return false;
        if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;

        final matchesPredicate = notificationPredicate != null
            ? notificationPredicate!(notification)
            : notification.depth == 0;
        if (!matchesPredicate) return false;

        if (scrollDirection != null &&
            notification.metrics.axis != scrollDirection) {
          return false;
        }

        final isForwardScroll =
            (notification is ScrollUpdateNotification &&
                (notification.scrollDelta ?? 0) > 0) ||
            (notification is OverscrollNotification &&
                notification.overscroll > 0);

        if (isForwardScroll) {
          final metrics = notification.metrics;
          if (metrics.maxScrollExtent > 0 &&
              metrics.extentAfter <= threshold) {
            onLoadMore();
          }
        }
        return false;
      },
      child: child,
    );
  }
}
