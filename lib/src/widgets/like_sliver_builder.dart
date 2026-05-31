import 'package:flutter/material.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_error.dart';

/// # `LikeSliverBuilder<T>`
/// 
/// A dedicated sliver-compatible version of [LikeBuilder] engineered for rendering 
/// network lifecycle states directly inside a [CustomScrollView].
/// 
/// Instead of building a single box widget, its builder functions return a list of 
/// slivers (`List<Widget>`).
/// 
/// ### CustomScrollView Scroll Integration
/// In traditional Flutter development, placing a standard `CircularProgressIndicator` or 
/// error `Container` directly into a `CustomScrollView`'s `slivers` property causes a crash! 
/// `LikeSliverBuilder` prevents this by automatically wrapping default placeholders inside 
/// sliver containers (e.g. wrapping standard loaders inside a `SliverFillRemaining`).
/// 
/// ### Example Usage:
/// ```dart
/// CustomScrollView(
///   slivers: [
///     SliverAppBar(title: Text('User Feed')),
///     LikeSliverBuilder<List<Post>>(
///       observe: () => feedProvider.postsState,
///       onLoading: () => [
///         SliverToBoxAdapter(child: LinearProgressIndicator()),
///       ],
///       onSuccess: (posts, isRefreshing, isSWR) {
///         return [
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
class LikeSliverBuilder<T extends Object> extends StatefulWidget {
  /// **observe**
  /// 
  /// A closure returning the notifier state (`LikeNotifierState<T>`) or immutable response 
  /// snapshot (`LikeStateResponse<T>`) to listen to.
  final dynamic Function() observe;

  /// **onSuccess**
  /// 
  /// The builder function called when the request resolves successfully.
  /// Must return a list of sliver widgets.
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// **onLoading**
  /// 
  /// Optional loading builder. Must return a list of slivers. 
  /// Defaults to a centered loader wrapped inside `SliverFillRemaining`.
  final List<Widget> Function()? onLoading;

  /// **onIdle**
  /// 
  /// Optional uninitialized (idle) builder. Must return a list of slivers.
  final List<Widget> Function()? onIdle;

  /// **onError**
  /// 
  /// Optional server-side error builder. Receives a [LikeError]. Must return a list of slivers.
  final List<Widget> Function(LikeError error)? onError;

  /// **onException**
  /// 
  /// Optional client-side exception builder. Receives an error message. Must return a list of slivers.
  final List<Widget> Function(String message)? onException;

  /// **listener**
  /// 
  /// An optional side-effect callback that triggers whenever the observed state changes.
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
  Listenable? _observedListenable;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant LikeSliverBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _unsubscribe();
    _subscribe();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  /// Subscribes to the observed Listenable (e.g. LikeNotifierState) to automatically rebuild when state changes.
  void _subscribe() {
    final rawObserved = widget.observe();
    assert(
      rawObserved is Listenable || rawObserved is LikeStateResponse,
      'LikeSliverBuilder.observe() must return either a Listenable (e.g. a LikeNotifierState) '
      'or a direct LikeStateResponse. '
      'Received: ${rawObserved.runtimeType}. '
      'Hint: use `observe: () => provider.myState` '
      'not `observe: () => provider.myState.value`.',
    );
    if (rawObserved is Listenable) {
      _observedListenable = rawObserved;
      _observedListenable!.addListener(_handleUpdate);
    }
  }

  /// Unsubscribes from listener to prevent memory leaks.
  void _unsubscribe() {
    if (_observedListenable != null) {
      _observedListenable!.removeListener(_handleUpdate);
      _observedListenable = null;
    }
  }

  /// Rebuilds the UI when state changes occur.
  void _handleUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Safely casts dynamic data to generic type T.
  T? _castData(dynamic data) {
    if (data == null) return null;
    if (data is T) return data;
    try {
      return data as T;
    } catch (e) {
      assert(
        false,
        'LikeSliverBuilder: Type cast failed. Expected $T, got ${data.runtimeType}. '
        'Check the generic type argument on LikeSliverBuilder<T>.',
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawObserved = widget.observe();
    final response = rawObserved is LikeNotifierState
        ? rawObserved.value
        : rawObserved as LikeStateResponse<dynamic>;

    // Handle frame-safe side-effect listener.
    if (widget.listener != null && _lastNotifiedResponse != response) {
      _lastNotifiedResponse = response;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.listener!(response);
      });
    }

    final casted = _castData(response.data);

    // Group slivers together under a single axis block for clean list structure.
    return SliverMainAxisGroup(
      slivers: () {
        switch (response.state) {
          case LikeState.idle:
            return widget.onIdle?.call() ?? [];

          case LikeState.loading:
            return widget.onLoading?.call() ??
                [
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ];

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

/// # `LikeStateResponseBuilderSliver<T>`
/// 
/// A specialized, lightweight version of [LikeSliverBuilder] useful when you already have an immutable 
/// [LikeStateResponse] directly in scope (e.g. from local variables, streams, or sliver-child indices) 
/// rather than observing a dynamic [LikeNotifierState].
class LikeStateResponseBuilderSliver<T extends Object> extends StatelessWidget {
  /// The [LikeStateResponse] to build the slivers from.
  final LikeStateResponse<T> response;

  /// Builder function called when data is successfully retrieved.
  /// Returns a list of slivers.
  final List<Widget> Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

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
