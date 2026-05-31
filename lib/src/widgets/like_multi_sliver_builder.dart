import 'package:flutter/material.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/widgets/like_multi_helper.dart';

/// # LikeMultiSliverBuilder
/// 
/// A specialized, performance-optimized layout widget designed to aggregate **multiple** 
/// network or data requests directly within a [CustomScrollView].
/// 
/// Similar to [LikeMultiBuilder], but instead of returning standard box layout widgets 
/// (like Columns/Containers), `LikeMultiSliverBuilder` builders return a **List of Slivers** 
/// (`List<Widget>`).
/// 
/// ### Beginner Note: What is a Sliver?
/// In Flutter, a "Sliver" is a portion of a scrollable area that behaves dynamically during scrolling. 
/// Standard widgets (like `ListView` or `Container`) cannot be placed directly inside a 
/// `CustomScrollView`'s slivers property. Instead, you must use sliver-compatible versions 
/// (such as `SliverList`, `SliverGrid`, or wrap standard boxes in `SliverToBoxAdapter`).
/// 
/// ### Example Usage:
/// ```dart
/// CustomScrollView(
///   slivers: [
///     SliverAppBar(title: Text('My Feed')),
///     LikeMultiSliverBuilder(
///       observes: [
///         () => myProvider.storiesState, // Story request
///         () => myProvider.postsState,   // Post request
///       ],
///       onSuccess: (results, isRefreshing, isSWR) {
///         final List<Story> stories = results[0] as List<Story>;
///         final List<Post> posts = results[1] as List<Post>;
/// 
///         return [
///           SliverToBoxAdapter(child: HorizontalStoryList(stories)),
///           SliverList(
///             delegate: SliverChildBuilderDelegate(
///               (context, index) => PostCard(posts[index]),
///               childCount: posts.length,
///             ),
///           ),
///         ];
///       },
///     ),
///   ],
/// );
/// ```
class LikeMultiSliverBuilder extends StatefulWidget {
  /// **observes**
  /// 
  /// A flat list of callback functions, each returning either a `LikeNotifierState` or 
  /// `LikeStateResponse` to monitor.
  final List<dynamic Function()> observes;

  /// **onSuccess**
  /// 
  /// The builder function called when all observed requests have resolved successfully.
  /// 
  /// Receives:
  /// * `results`: A list containing the unwrapped `data` payloads. The order of items in this 
  ///   list **exactly matches** the index order defined in the [observes] list.
  /// * `isRefreshing`: True if at least one of the observed requests is undergoing an active background refresh.
  /// * `isFromStaleWhileRevalidate`: True if at least one of the observed requests is currently 
  ///   displaying cached data while a network update resolves in the background.
  /// 
  /// Must return a `List<Widget>` of slivers.
  final List<Widget> Function(
    List<dynamic> results,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// **onLoading**
  /// 
  /// Optional builder active when at least one of the observed states is loading for the first time.
  /// Must return a list of sliver widgets. If not provided, displays a centered circular loader 
  /// wrapped inside a `SliverFillRemaining`.
  final List<Widget> Function()? onLoading;

  /// **onIdle**
  /// 
  /// Optional builder active when at least one of the states is in an uninitialized (idle) state.
  final List<Widget> Function()? onIdle;

  /// **onError**
  /// 
  /// Optional builder active when at least one of the requests fails with a server error.
  /// Receives the [LikeError] of the first failed request found.
  final List<Widget> Function(LikeError error)? onError;

  /// **onException**
  /// 
  /// Optional builder active when at least one of the requests triggers a client-side exception.
  /// Receives the exception string of the first crashed request found.
  final List<Widget> Function(String message)? onException;

  /// **listener**
  /// 
  /// An optional side-effect callback that triggers whenever the aggregated state or individual 
  /// responses change.
  final void Function(
    LikeState aggregatedState,
    List<LikeStateResponse<dynamic>> responses,
  )? listener;

  const LikeMultiSliverBuilder({
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
  State<LikeMultiSliverBuilder> createState() => _LikeMultiSliverBuilderState();
}

class _LikeMultiSliverBuilderState extends State<LikeMultiSliverBuilder> {
  List<dynamic>? _lastSuccessfulResults;
  LikeState? _lastAggregatedState;
  final List<Listenable> _subscribedListenables = [];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant LikeMultiSliverBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unsubscribe();
    _subscribe();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  /// Iterates through observes list and registers listeners to all ChangeNotifiers.
  void _subscribe() {
    for (final observe in widget.observes) {
      final raw = observe();
      if (raw is Listenable) {
        raw.addListener(_handleUpdate);
        _subscribedListenables.add(raw);
      }
    }
  }

  /// Unregisters listeners to prevent memory leaks.
  void _unsubscribe() {
    for (final listenable in _subscribedListenables) {
      listenable.removeListener(_handleUpdate);
    }
    _subscribedListenables.clear();
  }

  /// Rebuilds the UI when any of the observed states trigger a change notification.
  void _handleUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Resolve all current response snapshots.
    final responses = widget.observes.map((o) {
      final raw = o();
      return raw is LikeNotifierState
          ? raw.value
          : raw as LikeStateResponse<dynamic>;
    }).toList();
    
    // 2. Compute the single aggregated state representing all responses.
    final aggregatedState = LikeMultiHelper.aggregate(responses);

    // 3. Keep track of sticky data.
    final hasResolvedAll = responses.every(
      (r) => (r.state == LikeState.success ||
              r.state == LikeState.refreshing ||
              r.state == LikeState.staleWhileRevalidate) &&
          r.data != null,
    );
    if (hasResolvedAll) {
      _lastSuccessfulResults = responses.map((r) => r.data).toList();
    }

    // 4. Trigger the listener side-effect securely inside post-frame callback.
    if (widget.listener != null && _lastAggregatedState != aggregatedState) {
      _lastAggregatedState = aggregatedState;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.listener!(aggregatedState, responses);
      });
    }

    // 5. Build the list of sliver widgets representing our aggregated state.
    return SliverMainAxisGroup(
      slivers: () {
        switch (aggregatedState) {
          case LikeState.exception:
            final first = responses.firstWhere(
              (r) => r.isException,
              orElse: () => responses.first,
            );
            return widget.onException?.call(first.message) ?? [];

          case LikeState.error:
            final first = responses.firstWhere(
              (r) => r.isError,
              orElse: () => responses.first,
            );
            return widget.onError?.call(first.error!) ?? [];

          case LikeState.idle:
            return widget.onIdle?.call() ?? [];

          case LikeState.loading:
            // Sticky Data Support: Display old success slivers instead of a blank loader sliver
            if (_lastSuccessfulResults != null) {
              final isRefreshing = responses.any((r) => r.isRefreshing);
              return widget.onSuccess(_lastSuccessfulResults!, isRefreshing, false);
            }
            return widget.onLoading?.call() ??
                [
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ];

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
