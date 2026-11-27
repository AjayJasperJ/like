# `LikeScreenMixin` Guide: Screen Visibility & Connectivity

`LikeScreenMixin<T extends StatefulWidget> on State<T> implements RouteAware` is a unified screen-level `State` mixin combining route/tab visibility tracking with connectivity and origin-reachability callbacks.

---

## 1. Setup `likeRouteObserver`

Register the global `likeRouteObserver` in `MaterialApp.navigatorObservers` so route pushes and pops update screen visibility automatically:

```dart
MaterialApp(
  navigatorObservers: [likeRouteObserver],
  home: const FeedScreen(),
);
```

---

## 2. Basic Screen Example

```dart
import 'package:flutter/material.dart';
import 'package:like/like.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with LikeScreenMixin<FeedScreen> {
  @override
  bool get rebuildOnConnectivityChange => true;

  @override
  void onVisibilityChanged(bool visible) {
    if (visible) {
      // Screen became visible with no pending connectivity restoration:
      // fetch only if not already success with data (ars: LikeARS(skip: true)).
      context.read<FeedProvider>().loadFeed(skipIfCached: true);
    }
  }

  @override
  Future<void> onVisibleRestored(bool restored) async {
    // Connectivity was restored while visible (or upon returning to this screen):
    // force refresh to fetch fresh data. (onVisibilityChanged(true) does NOT fire here.)
    await context.read<FeedProvider>().loadFeed(refresh: true);
  }

  @override
  void onOffline() {
    // Optional: show an offline banner or toast.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isOnline ? 'Feed' : 'Feed (Offline)'),
      ),
      body: const SizedBox(),
    );
  }
}
```

---

## 3. Tabs & `IndexedStack` (`notifyVisibility`)

Flutter's `RouteObserver` does not fire when switching tabs inside an `IndexedStack`. Call `notifyVisibility(bool visible)` when the active tab index changes:

```dart
childStateKey.currentState?.notifyVisibility(isActiveTab);
```

`isCurrentlyVisible` checks route visibility, `TickerMode.of(context)`, attached non-empty `RenderBox` size, and `Offstage`.

---

## 4. Binding `LikeEngine`s & Deferred Recovery

- Override `likeEngines` to automatically pause/resume engine resync on route visibility changes and trigger focus refetches when visible or restored.
- `deferRecoveryUntilVisible` defaults to `true`: if an origin drops and recovers while the screen is covered or hidden, `onConnectivityRestored`, `onRecover`, and `onVisibleRestored(true)` are queued and run post-frame as soon as `isCurrentlyVisible` becomes `true`.

---

## 5. Complete `LikeScreenMixin` API Reference

### Configuration Getters (Override)
| Getter | Default | Purpose |
|---|---|---|
| `likeEngines` | `const []` | `LikeEngine` instances bound to visibility & focus refetch |
| `rebuildOnConnectivityChange` | `false` | Automatically call `setState` when `isOnline` changes |
| `deferRecoveryUntilVisible` | `true` | Queue offscreen origin restorations until the screen becomes visible |

### Status Getters
| Getter | Type | Purpose |
|---|---|---|
| `isOnline` | `bool` | Combined `isInternetConnected && isServerAvailable` |
| `isInternetConnected` | `bool` | Active network interface and internet reachability |
| `isServerAvailable` | `bool` | Reachability of the primary configured server origin |
| `isCurrentlyVisible` | `bool` | Whether the widget is visible (route, `TickerMode`, `RenderBox`, `Offstage`) |

### Lifecycle Callbacks (Override)
| Callback | When It Fires |
|---|---|
| `onVisibilityChanged(bool visible)` | Route or `notifyVisibility` visibility changes |
| `onConnectivityChanged(bool isOnline)` | Combined `isOnline` status changes |
| `onOnline()` | Transition from offline to online |
| `onOffline()` | Transition from online to offline |
| `onOriginTransition(LikeConnectivityTransition transition)` | Any origin reachability transition |
| `onConnectivityRestored(LikeConnectivityTransition transition)` | Origin transitions from unavailable to available (respecting `deferRecoveryUntilVisible`) |
| `onRecover()` | Custom recovery hook invoked alongside `onConnectivityRestored` |
| `onVisibleRestored(bool restored)` | Invoked on origin restoration when visible (or upon return); mutually exclusive with `onVisibilityChanged(true)` |

### Imperative Methods
| Method | Purpose |
|---|---|
| `notifyVisibility(bool visible)` | Manually update visibility for `IndexedStack` / tab containers |
| `checkConnectivity({bool force = false})` | Trigger a connectivity check via `LikeConnectivityManager` |
| `checkServerReachability(String serverUrl, {bool force = false})` | Trigger an origin reachability check for `serverUrl` |
