import 'dart:async';
import 'package:flutter/widgets.dart';
import '../engine/like_engine.dart';

/// Global route observer for LikeVisibilityMixin. 
/// Must be added to MaterialApp.navigatorObservers.
final RouteObserver<ModalRoute<void>> likeRouteObserver = RouteObserver<ModalRoute<void>>();

/// A mixin for State classes that provides visibility tracking based on route navigation.
/// 
/// It automatically subscribes to [likeRouteObserver] and calls [onVisibilityChanged]
/// when the route is pushed, popped, or covered by another route.
mixin LikeVisibilityMixin<T extends StatefulWidget> on State<T> implements RouteAware {
  bool _isVisible = false;

  /// Override this to provide a list of [LikeEngine]s that should be bound
  List<LikeEngine> get likeEngines => const [];

  /// Override this method to handle visibility changes manually.
  void onVisibilityChanged(bool visible) {}



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
