import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:like/src/engine/like_engine.dart';
import 'package:like/src/models/like_connectivity_check_result.dart';
import 'package:like/src/models/like_connectivity_transition.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Global route observer for [LikeScreenMixin].
/// Must be added to `MaterialApp.navigatorObservers`.
final RouteObserver<ModalRoute<void>> likeRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// Unified screen-level [State] mixin combining route/tab visibility tracking
/// with connectivity and origin-reachability callbacks.
///
/// Register [likeRouteObserver] in `MaterialApp.navigatorObservers` for route
/// transitions, and call [notifyVisibility] for tab containers such as
/// [IndexedStack].
///
/// When connectivity is restored while the screen is offscreen, recovery is
/// deferred until the screen becomes visible again (controlled by
/// [deferRecoveryUntilVisible]).
mixin LikeScreenMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  bool _isVisible = false;
  bool _isRecovering = false;
  bool _focusRefetchScheduled = false;
  bool _lastOnlineState = LikeConnectivityManager().isOnline;
  LikeConnectivityTransition? _pendingRestoration;

  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<LikeConnectivityTransition>? _transitionSubscription;

  /// Optional [LikeEngine] instances bound to this screen's visibility and
  /// focus refetch lifecycle.
  List<LikeEngine> get likeEngines => const [];

  /// Whether this widget should call `setState` automatically when
  /// [LikeConnectivityManager.connectionChange] emits a new status.
  bool get rebuildOnConnectivityChange => false;

  /// Whether origin restorations that occur while this screen is hidden should
  /// be deferred and executed when the screen becomes visible again.
  bool get deferRecoveryUntilVisible => true;

  /// Whether both internet and the primary server origin are currently reachable.
  bool get isOnline => LikeConnectivityManager().isOnline;

  /// Whether the device currently has an active interface and internet reachability.
  bool get isInternetConnected => LikeConnectivityManager().isInternetConnected;

  /// Whether the primary configured server origin is currently reachable.
  bool get isServerAvailable => LikeConnectivityManager().isServerAvailable;

  /// Whether this widget is currently visible on screen (respecting navigation
  /// routes, [TickerMode], layout size, and [Offstage]).
  bool get isCurrentlyVisible {
    if (!_isVisible || !mounted) return false;

    // ignore: deprecated_member_use
    if (!TickerMode.of(context)) return false;

    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) return false;
    if (renderObject is RenderBox) {
      if (!renderObject.hasSize || renderObject.size.isEmpty) return false;
    }

    final offstage = context.findAncestorWidgetOfExactType<Offstage>();
    if (offstage != null && offstage.offstage) return false;

    return true;
  }

  /// Called when route or explicit tab visibility changes.
  void onVisibilityChanged(bool visible) {}

  /// Called whenever the combined [isOnline] status changes.
  void onConnectivityChanged(bool isOnline) {}

  /// Called when connectivity transitions from offline to online.
  void onOnline() {}

  /// Called when connectivity transitions from online to offline.
  void onOffline() {}

  /// Called on any origin reachability transition emitted by
  /// [LikeConnectivityManager.originTransitions].
  void onOriginTransition(LikeConnectivityTransition transition) {}

  /// Called when a previously unavailable origin becomes reachable again
  /// (immediately if visible, or upon becoming visible when
  /// [deferRecoveryUntilVisible] is `true`).
  Future<void> onConnectivityRestored(
    LikeConnectivityTransition transition,
  ) async {}

  /// Custom recovery hook (e.g. re-executing screen API calls) invoked on
  /// origin restoration when the screen is visible.
  Future<void> onRecover() async {}

  /// Combined callback invoked when the screen becomes visible (`restored = false`)
  /// or when connectivity is restored while visible / upon returning (`restored = true`).
  FutureOr<void> onVisibleRestored(bool restored) {}

  /// Explicit visibility signal for containers such as [IndexedStack] or
  /// [TabBarView] that do not emit [RouteAware] transitions.
  void notifyVisibility(bool visible) {
    _updateVisibility(visible);
  }

  /// Triggers a connectivity check on [LikeConnectivityManager].
  Future<LikeConnectivityCheckResult> checkConnectivity({bool force = false}) {
    return LikeConnectivityManager().checkConnectivity(force: force);
  }

  /// Triggers a server reachability check on [LikeConnectivityManager].
  Future<LikeConnectivityCheckResult> checkServerReachability(
    String serverUrl, {
    bool force = false,
  }) {
    return LikeConnectivityManager().checkServerReachability(
      serverUrl,
      force: force,
    );
  }

  @override
  void initState() {
    super.initState();
    final manager = LikeConnectivityManager();
    _lastOnlineState = manager.isOnline;

    _connectionSubscription = manager.connectionChange.listen((online) {
      if (!mounted) return;
      final changed = _lastOnlineState != online;
      _lastOnlineState = online;
      if (rebuildOnConnectivityChange && changed) {
        setState(() {});
      }
      onConnectivityChanged(online);
      if (changed) {
        if (online) {
          onOnline();
        } else {
          onOffline();
        }
      }
    });

    _transitionSubscription = manager.originTransitions.listen((transition) {
      if (!mounted) return;
      onOriginTransition(transition);
      if (transition.becameUnavailable && !deferRecoveryUntilVisible) {
        _pendingRestoration = null;
      }
      if (transition.isRestoration) {
        if (isCurrentlyVisible) {
          _runRecovery(transition);
        } else if (deferRecoveryUntilVisible) {
          _pendingRestoration = transition;
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) {
      likeRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _transitionSubscription?.cancel();
    likeRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() => _updateVisibility(true);

  @override
  void didPopNext() => _updateVisibility(true);

  @override
  void didPushNext() => _updateVisibility(false);

  @override
  void didPop() => _updateVisibility(false);

  void _updateVisibility(bool visible) {
    if (_isVisible == visible) return;
    _isVisible = visible;
    scheduleMicrotask(() {
      if (!mounted) return;
      for (final engine in likeEngines) {
        engine.setResyncActive(visible);
      }
      if (visible) {
        _scheduleFocusRefetch();
        if (_pendingRestoration != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final pending = _pendingRestoration;
            if (pending != null && isCurrentlyVisible) {
              _pendingRestoration = null;
              _runRecovery(pending);
            }
          });
        } else {
          unawaited(Future<void>.sync(() => onVisibleRestored(false)));
        }
      }
      onVisibilityChanged(visible);
    });
  }

  void _runRecovery(LikeConnectivityTransition transition) {
    if (_isRecovering || !mounted) return;
    _isRecovering = true;
    unawaited(
      Future.wait<void>([
        Future<void>.sync(() => onConnectivityRestored(transition)),
        Future<void>.sync(onRecover),
        Future<void>.sync(() => onVisibleRestored(true)),
      ]).whenComplete(() {
        _isRecovering = false;
      }),
    );
    _scheduleFocusRefetch();
  }

  void _scheduleFocusRefetch() {
    if (_focusRefetchScheduled) return;
    _focusRefetchScheduled = true;
    scheduleMicrotask(() {
      _focusRefetchScheduled = false;
      if (!mounted || !isCurrentlyVisible) return;
      for (final engine in likeEngines) {
        engine.triggerFocusRefetch();
      }
    });
  }
}
