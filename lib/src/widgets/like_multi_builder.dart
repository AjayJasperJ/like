import 'package:flutter/material.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/widgets/like_multi_helper.dart';

/// # LikeMultiBuilder
/// 
/// A sophisticated state-aggregation widget designed to monitor **multiple** independent 
/// data requests (`LikeNotifierState` or `LikeStateResponse`) simultaneously.
/// 
/// Instead of writing multiple nested `LikeBuilder` widgets (which creates messy, unreadable indentations), 
/// `LikeMultiBuilder` lets you track all requests in a single, flat widget.
/// 
/// ### How State Aggregation Works:
/// * **Priority #1 (Exception):** If any observed state has a client-side crash/exception, the entire 
///   builder immediately displays [onException].
/// * **Priority #2 (Error):** If any observed state fails with a server-side error, the entire 
///   builder immediately displays [onError].
/// * **Priority #3 (Loading):** If any observed state is currently loading and no sticky (old) data exists, 
///   the entire builder displays [onLoading].
/// * **Priority #4 (Success):** When **all** observed states have successfully resolved, the builder 
///   calls [onSuccess] with a list containing the unpacked results.
/// 
/// ### Example Usage:
/// ```dart
/// LikeMultiBuilder(
///   observes: [
///     () => myProvider.userInfoState,    // Index 0: User info request
///     () => myProvider.statsState,       // Index 1: Stats info request
///   ],
///   onLoading: () => CircularProgressIndicator(),
///   onSuccess: (results, isRefreshing, isSWR) {
///     // Data order matches the order in "observes" list exactly!
///     final UserInfo user = results[0] as UserInfo;
///     final DashboardStats stats = results[1] as DashboardStats;
/// 
///     return Column(
///       children: [
///         Text('Hello, ${user.name}'),
///         Text('Views today: ${stats.viewCount}'),
///       ],
///     );
///   },
/// );
/// ```
class LikeMultiBuilder extends StatefulWidget {
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
  final Widget Function(
    List<dynamic> results,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// **onLoading**
  /// 
  /// Optional builder active when at least one of the observed states is loading for the first time.
  /// If old/cached data was previously loaded for all states, `LikeMultiBuilder` will continue 
  /// to display the old success screen (*sticky data*) instead of showing this loader.
  final Widget Function()? onLoading;

  /// **onIdle**
  /// 
  /// Optional builder active when at least one of the states is in an uninitialized (idle) state.
  final Widget Function()? onIdle;

  /// **onError**
  /// 
  /// Optional builder active when at least one of the requests fails with a server error.
  /// Receives the [LikeError] of the first failed request found in the list.
  final Widget Function(LikeError error)? onError;

  /// **onException**
  /// 
  /// Optional builder active when at least one of the requests triggers a client-side exception.
  /// Receives the exception string of the first crashed request found.
  final Widget Function(String message)? onException;

  /// **listener**
  /// 
  /// An optional side-effect callback that triggers whenever the aggregated state or individual 
  /// responses change.
  /// 
  /// * **Use Case:** Triggering alerts, tracking page navigation, or analytics events when combinations 
  ///   of states resolve.
  final void Function(
    LikeState aggregatedState,
    List<LikeStateResponse<dynamic>> responses,
  )? listener;

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
  final List<Listenable> _subscribedListenables = [];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant LikeMultiBuilder oldWidget) {
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

    // 5. Build the UI tree representing our aggregated state.
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
            // Sticky Data Support: Display old success screen instead of a blank loader
            if (_lastSuccessfulResults != null) {
              final isRefreshing = responses.any((r) => r.isRefreshing);
              return widget.onSuccess(_lastSuccessfulResults!, isRefreshing, false);
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
