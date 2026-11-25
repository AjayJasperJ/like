import 'package:flutter/material.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_error.dart';

/// # `LikeBuilder<T>`
///
/// A powerful, beginner-friendly Flutter widget designed to manage and render user interfaces
/// dynamically based on network/data request lifecycles (`LikeStateResponse`).
///
/// It acts like a smart `AnimatedBuilder` or `ValueListenableBuilder`, automatically listening
/// to changes in a state provider and instantly rebuilding the widget tree when the state changes.
///
/// ### Key Feature: Sticky Data (SWR - Stale While Revalidate)
/// Beginners often struggle with "UI flicker" (when the screen turns white/shows a loader briefly
/// while fetching new data). `LikeBuilder` solves this by keeping old data visible on screen
/// (*sticky data*) while a background refresh is in progress.
///
/// ### Example Usage:
/// ```dart
/// LikeBuilder<UserProf>(
///   observe: () => myProvider.profileState, // returns a LikeNotifierState
///   onLoading: () => CircularProgressIndicator(), // initial load only
///   onSuccess: (profile, isRefreshing, isSWR) {
///     return Column(
///       children: [
///         Text('Name: ${profile.name}'),
///         if (isRefreshing) Text('Updating in background...'),
///       ],
///     );
///   },
///   onError: (error) => Text('Failed to load profile: ${error.message}'),
/// );
/// ```
class LikeBuilder<T> extends StatefulWidget {
  /// **observe**
  ///
  /// A closure/callback function that returns either a `LikeNotifierState<T>` (which is a
  /// ChangeNotifier) or a direct immutable `LikeStateResponse<T>`.
  ///
  /// * **Rule of Thumb:** Always pass the state container itself: `observe: () => provider.myState`
  ///   so the widget can subscribe to updates. Do *not* pass the value field directly
  ///   like `observe: () => provider.myState.value` because that returns an immutable object
  ///   that can't be listened to!
  final dynamic Function() observe;

  /// **onSuccess**
  ///
  /// The builder function called when the request has completed successfully and data is available.
  ///
  /// Receives:
  /// * `data`: The parsed model object of type [T]. Guaranteed to be non-null.
  /// * `isRefreshing`: True if the user manually triggered a refresh (e.g., Pull-to-Refresh)
  ///   and the widget is displaying old data while loading new data.
  /// * `isFromStaleWhileRevalidate`: True if the widget is displaying cached data from disk/RAM
  ///   while a background fetch is silently resolving.
  final Widget Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// **onLoading**
  ///
  /// Optional builder that renders a loading indicator.
  /// Only active when fetching data for the very first time (when no cached or old data is available).
  /// If not provided, defaults to a centered [CircularProgressIndicator].
  final Widget Function()? onLoading;

  /// **onIdle**
  ///
  /// Optional builder active when the state is [LikeState.idle] (uninitialized/ready to fetch).
  /// If not provided, renders an empty widget ([SizedBox.shrink]).
  final Widget Function()? onIdle;

  /// **onError**
  ///
  /// Optional builder active when a server-side or API error is returned.
  /// Receives a [LikeError] containing status codes, messages, and raw responses.
  final Widget Function(LikeError error)? onError;

  /// **onException**
  ///
  /// Optional builder active when a client-side or system-level exception (e.g. SocketException,
  /// JSON parsing error, or hardware failure) occurs.
  /// Receives the exception error message and optional [LikeError] or exception object.
  final Widget Function(String message, LikeError? error)? onException;

  /// **listener**
  ///
  /// An optional side-effect callback that triggers whenever the observed state changes.
  ///
  /// * **Use Case:** Trigger actions that shouldn't render UI directly, such as showing a Toast,
  ///   opening a dialog, or navigating to another page based on the request result.
  /// * **Safety Guarantee:** Automatically called inside a post-frame callback so it won't
  ///   interfere with the active widget build cycle.
  final void Function(LikeStateResponse<dynamic> response)? listener;

  /// Optional predicate to skip rebuilding when [previous] and [next]
  /// represent no visual change for this widget.
  final bool Function(
    LikeStateResponse<dynamic> previous,
    LikeStateResponse<dynamic> next,
  )? buildWhen;

  /// Optional selector on success [T] data. When provided, consecutive
  /// success/refreshing/SWR notifications with equal selected values skip rebuilds.
  final Object? Function(T data)? selector;

  const LikeBuilder({
    super.key,
    required this.observe,
    required this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
    this.listener,
    this.buildWhen,
    this.selector,
  });

  @override
  State<LikeBuilder<T>> createState() => _LikeBuilderState<T>();
}

class _LikeBuilderState<T> extends State<LikeBuilder<T>> {
  LikeStateResponse<dynamic>? _lastNotifiedResponse;
  LikeStateResponse<dynamic>? _lastRenderedResponse;
  Object? _lastSelectedValue;
  bool _hasSelectedValue = false;
  Listenable? _observedListenable;
  late ValueNotifier<LikeStateResponse<dynamic>> _responseNotifier;

  @override
  void initState() {
    super.initState();
    final rawObserved = widget.observe();
    _responseNotifier = ValueNotifier<LikeStateResponse<dynamic>>(
      _resolveResponse(rawObserved),
    );
    _syncSubscription(rawObserved);
  }

  @override
  void didUpdateWidget(covariant LikeBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rawObserved = widget.observe();
    final nextResponse = _resolveResponse(rawObserved);
    final listenableChanged =
        !identical(rawObserved is Listenable ? rawObserved : null, _observedListenable);
    // Replace the notifier when the observed source changes or a direct snapshot updates,
    // avoiding mutating the active ValueNotifier during the build/update phase.
    if (listenableChanged ||
        (rawObserved is! Listenable && nextResponse != _responseNotifier.value)) {
      final oldNotifier = _responseNotifier;
      _responseNotifier = ValueNotifier<LikeStateResponse<dynamic>>(nextResponse);
      WidgetsBinding.instance.addPostFrameCallback((_) => oldNotifier.dispose());
    }
    _syncSubscription(rawObserved);
  }

  @override
  void dispose() {
    _unsubscribe();
    _responseNotifier.dispose();
    super.dispose();
  }

  LikeStateResponse<dynamic> _resolveResponse(dynamic rawObserved) {
    assert(
      rawObserved is Listenable || rawObserved is LikeStateResponse,
      'LikeBuilder.observe() must return either a Listenable (e.g. a LikeNotifierState) '
      'or a direct LikeStateResponse. '
      'Received: ${rawObserved.runtimeType}. '
      'Hint: use `observe: () => provider.myState` '
      'not `observe: () => provider.myState.value`.',
    );
    return rawObserved is LikeNotifierState
        ? rawObserved.value
        : rawObserved as LikeStateResponse<dynamic>;
  }

  /// Registers a listener on the observed state if it is a Listenable (like LikeNotifierState),
  /// avoiding redundant unsubscribe/resubscribe churn when the instance is unchanged.
  void _syncSubscription(dynamic rawObserved) {
    final nextListenable = rawObserved is Listenable ? rawObserved : null;
    if (identical(nextListenable, _observedListenable)) return;
    _unsubscribe();
    if (nextListenable != null) {
      _observedListenable = nextListenable;
      _observedListenable!.addListener(_handleUpdate);
    }
  }

  /// Removes the listener registration to prevent memory leaks.
  void _unsubscribe() {
    if (_observedListenable != null) {
      _observedListenable!.removeListener(_handleUpdate);
      _observedListenable = null;
    }
  }

  /// Pushes updates to [_responseNotifier] only when the observed state (or selected slice) changed.
  void _handleUpdate() {
    if (!mounted) return;
    final current = _observedListenable;
    if (current is LikeNotifierState) {
      final next = current.value;
      final prev = _lastRenderedResponse;
      if (prev != null) {
        if (prev == next) return;
        if (widget.buildWhen != null && !widget.buildWhen!(prev, next)) {
          return;
        }
        if (widget.selector != null &&
            _hasSelectedValue &&
            prev.state == next.state &&
            prev.isFromStaleWhileRevalidate == next.isFromStaleWhileRevalidate) {
          final casted = _castData(next.data);
          if (casted != null &&
              widget.selector!(casted) == _lastSelectedValue) {
            return;
          }
        }
      }
      _responseNotifier.value = next;
    }
  }

  /// Safely casts dynamic data to our generic type T, outputting clean assertion diagnostics in debug mode.
  T? _castData(dynamic data) {
    if (data == null) return null;
    if (data is T) return data;
    try {
      return data as T;
    } catch (e) {
      assert(
        false,
        'LikeBuilder: Type cast failed. Expected $T, got ${data.runtimeType}. '
        'Check the generic type argument on LikeBuilder<T>.',
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LikeStateResponse<dynamic>>(
      valueListenable: _responseNotifier,
      builder: (context, response, _) {
        _lastRenderedResponse = response;

        // Handle the side-effect listener in a safe frame phase.
        if (widget.listener != null && _lastNotifiedResponse != response) {
          _lastNotifiedResponse = response;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.listener!(response);
          });
        }

        final casted = _castData(response.data);
        if (widget.selector != null && casted != null) {
          _lastSelectedValue = widget.selector!(casted);
          _hasSelectedValue = true;
        } else {
          _hasSelectedValue = false;
          _lastSelectedValue = null;
        }

        // Map each possible lifecycle state to its corresponding UI builder.
        switch (response.state) {
          case LikeState.idle:
            return widget.onIdle?.call() ?? const SizedBox.shrink();

          case LikeState.loading:
            return widget.onLoading?.call() ??
                const Center(child: CircularProgressIndicator());

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
            return widget.onError?.call(response.error!) ??
                const SizedBox.shrink();

          case LikeState.exception:
            return widget.onException?.call(response.message, response.error) ??
                const SizedBox.shrink();
        }
      },
    );
  }
}

/// # `LikeStateResponseBuilder<T>`
///
/// A specialized, lightweight version of [LikeBuilder] useful when you already have an immutable
/// [LikeStateResponse] directly in scope (e.g. from local variables, FutureBuilders, or Streams)
/// rather than observing a dynamic [LikeNotifierState].
class LikeStateResponseBuilder<T> extends StatelessWidget {
  /// The static [LikeStateResponse] containing current state data.
  final LikeStateResponse<T> response;

  /// Builder function called when data is successfully retrieved.
  final Widget Function(
    T data,
    bool isRefreshing,
    bool isFromStaleWhileRevalidate,
  ) onSuccess;

  /// Optional builder called when the initial data load is in progress.
  final Widget Function()? onLoading;

  /// Optional builder called when the state is [LikeState.idle].
  final Widget Function()? onIdle;

  /// Optional builder called when an explicit [LikeError] occurs.
  final Widget Function(LikeError error)? onError;

  /// Optional builder called when an unexpected exception or system error occurs.
  final Widget Function(String message, LikeError? error)? onException;

  const LikeStateResponseBuilder({
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
    return LikeBuilder<T>(
      observe: () => response,
      onSuccess: onSuccess,
      onLoading: onLoading,
      onIdle: onIdle,
      onError: onError,
      onException: onException,
    );
  }
}
