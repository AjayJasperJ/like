import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:like/src/models/like_connectivity_transition.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import '../engine/like_engine.dart';

/// Global route observer for LikeVisibilityMixin.
/// Must be added to MaterialApp.navigatorObservers.
final RouteObserver<ModalRoute<void>> likeRouteObserver =
    RouteObserver<ModalRoute<void>>();

/// A mixin for State classes that provides visibility tracking based on route navigation.
///
/// It automatically subscribes to [likeRouteObserver] and calls [onVisibilityChanged]
/// when the route is pushed, popped, or covered by another route.
mixin LikeVisibilityMixin<T extends StatefulWidget> on State<T>
    implements RouteAware {
  bool _isVisible = false;

  /// Override this to provide a list of [LikeEngine]s that should be bound
  List<LikeEngine> get likeEngines => const [];

  /// Override this method to handle visibility changes manually.
  void onVisibilityChanged(bool visible) {}

  StreamSubscription<LikeConnectivityTransition>? _connectivitySubscription;

  /// Override this method to perform custom recovery (like re-executing screen API calls) when network/server is restored.
  Future<void> onRecover() async {}

  /// Whether this widget is currently visible on screen (respecting navigation routes, TickerMode, IndexedStack, and Offstage).
  bool get isCurrentlyVisible {
    if (!_isVisible || !mounted) return false;

    // 1. IndexedStack / TabBarView / PageView check (Flutter disables TickerMode for hidden tabs)
    // ignore: deprecated_member_use
    if (!TickerMode.of(context)) return false;

    // 2. RenderObject paint & layout check
    final renderObject = context.findRenderObject();
    if (renderObject == null || !renderObject.attached) return false;
    if (renderObject is RenderBox) {
      if (!renderObject.hasSize || renderObject.size.isEmpty) return false;
    }

    // 3. Offstage widget check
    final offstage = context.findAncestorWidgetOfExactType<Offstage>();
    if (offstage != null && offstage.offstage) return false;

    return true;
  }

  @override
  void initState() {
    super.initState();
    _connectivitySubscription =
        LikeConnectivityManager().originRestorations.listen((event) {
      if (!isCurrentlyVisible) return;
      onRecover();
      for (final engine in likeEngines) {
        engine.triggerFocusRefetch();
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
    _connectivitySubscription?.cancel();
    likeRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPush() {
    _updateVisibility(true);
  }

  @override
  void didPopNext() {
    _updateVisibility(true);
  }

  @override
  void didPushNext() {
    _updateVisibility(false);
  }

  @override
  void didPop() {
    _updateVisibility(false);
  }

  void _updateVisibility(bool visible) {
    if (_isVisible != visible) {
      _isVisible = visible;
      scheduleMicrotask(() {
        if (!mounted) return;
        for (final engine in likeEngines) {
          engine.setResyncActive(visible);
          if (visible) {
            engine.triggerFocusRefetch();
          }
        }
        onVisibilityChanged(visible);
      });
    }
  }
}
