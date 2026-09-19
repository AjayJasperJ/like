import 'dart:async';
import 'package:flutter/material.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:toastification/toastification.dart';
import 'package:like/src/interceptors/like_auth_interceptor.dart';
import 'package:like/src/services/like_service.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_toast_manager.dart';
import 'package:like/src/services/like_toast_delegate.dart';
import 'package:like/src/debug/like_suggestions.dart' as sug;

/// # Like
///
/// The **Master Coordinator & Root Wrapper Widget** that powers the entire LIKE network engine.
///
/// ### Why is the [Like] widget necessary?
/// In a standard Flutter application, bootstrapping offline storage, network reachability observers,
/// auth interceptors, and contextless popup notifications involves a massive amount of scattered,
/// fragile boilerplate code.
///
/// The [Like] widget unifies all of this under a single declarative root wrapper:
/// 1. **Bootstrap Coordinator:** Automatically initializes offline cache (Hive) and
///    client network pipelines asynchronously before letting the app render.
/// 2. **Network Connection Tracker:** Dynamically observes real-time internet connectivity,
///    showing interactive online/offline warning toasts automatically.
/// 3. **Authentication Hub:** Handles secure header JWT token injection, automatic silent 401 token refresh
///    replays, and force logouts.
/// 4. **Progress Sync Overlay:** Renders a gorgeous full-screen modal blocking user interactions
///    while important offline tasks are actively syncing to the server on recovery.
/// 5. **Contextless Toasts Provider:** Configures overlays so notifications can be shown from *any* file
///    (even in raw background services) without needing a BuildContext reference.
///
/// ### Where to Place It:
/// Always wrap your primary [MaterialApp] with the [Like] widget inside `main.dart`:
/// ```dart
/// void main() {
///   runApp(
///     Like(
///       getToken: () async => secureStorage.read('jwt'),
///       refreshToken: () async => api.refreshToken(),
///       child: const MyApp(),
///     ),
///   );
/// }
/// ```
class Like extends StatefulWidget {
  /// The main application widget tree (typically your [MaterialApp]).
  final Widget child;

  /// A custom [ValueNotifier] used to programmatically trigger or listen to the global syncing overlay.
  ///
  /// * **Default behavior:** If left `null`, the widget automatically listens to the global [LikeService.isSyncing] notifier.
  ///   When true, it blocks interaction and displays a clean, user-friendly synchronizing progress screen.
  final ValueNotifier<bool>? isSyncing;

  /// A custom builder to customize the appearance of the background synchronization progress toast.
  ///
  /// Allows you to completely override the layout, texts, and styles of the sync toast with your own design.
  final Widget Function(String title, String message, double progress)?
      syncProgressBuilder;

  /// The custom widget overlay shown when the app is performing background data synchronization (`isSyncing` is true).
  ///
  /// Allows you to design a premium, full-screen blur or animated loader that blocks user interaction
  /// while critical local outboxes are synced to your server upon internet recovery.
  final Widget? syncOverlay;

  /// A custom loading screen displayed while the LIKE engine initializes Hive database files
  /// and checks initial internet connectivity.
  ///
  /// If your app starts up instantly, this prevents any "flash" of empty layout by holding
  /// a beautiful splash loader until the underlying storage layers are fully ready.
  final Widget? loadingWidget;

  /// Whether to automatically show gorgeous animated popup alerts whenever internet connection drops or restores.
  ///
  /// **Default:** `true` (strongly recommended). Instantly warns the user when they go offline, preventing confusion
  /// when data updates stop responding.
  final bool showConnectivityToasts;

  /// A secure callback function that retrieves the current user's JWT/session token.
  ///
  /// Once provided, the network engine automatically injects this token as a `Bearer` authorization
  /// header on every outgoing API request.
  ///
  /// **Example:** `getToken: () => secureStorage.read('jwt_token')`
  final Future<String?> Function()? getToken;

  /// A secure callback function that performs token refreshing when the backend reports an expired token (401 Unauthorized).
  ///
  /// If a request fails due to expiration, the interceptor pauses outgoing calls, triggers this callback
  /// to fetch a fresh token, saves the new token, and replays the original failed request seamlessly.
  final Future<String?> Function()? refreshToken;

  /// A callback triggered when a session is unrecoverable (e.g. token refresh fails).
  ///
  /// Commonly used to instantly clear local database storage, wipe tokens, and redirect the user
  /// to the login screen.
  final Future<void> Function({int? statusCode, bool force})? onLogout;

  /// A secure callback that retrieves the server API key to append to headers or query parameters.
  final Future<String?> Function()? getApiKey;

  /// Custom design configuration for the network-related toasts.
  ///
  /// Allows you to supply custom widgets to replace the default success, info, and offline toast views.
  final LikeToastConfig? toastConfig;

  /// A delegate that controls exactly how toasts are triggered, designed, and presented throughout the app lifecycle.
  /// Takes precedence over custom configuration widgets if provided.
  final LikeToastDelegate? toastDelegate;

  /// Optional debug-only wrapper used to inject developer dashboards or HUD overlays.
  ///
  /// **Example:** Passing a callback that wraps the app with a Floating Action Button to launch the LIKE devtool:
  /// `devTool: (child) => LikeDevTool(child: child)`
  final Widget Function(Widget child)? devTool;

  /// Optional authentication configuration (token getters, refresh, logout callbacks).
  final LikeAuthConfig? authConfig;

  /// A global navigator key that can be linked to your [MaterialApp.navigatorKey].
  ///
  /// Enables the LIKE engine to trigger beautiful, premium toast notifications from any layer of your
  /// codebase (services, repositories, providers) **without requiring a BuildContext**.
  static GlobalKey<NavigatorState> get navigatorKey =>
      LikeToastManager.navigatorKey;

  /// Prints a beautiful quickstart and help cheatsheet listing all widgets, methods, classes, and mixins
  /// of the LIKE package in the terminal, complete with colored headings and copy-pasteable snippets.
  static void help() => sug.printAllSuggestions();

  /// Prints a random, bite-sized tip or code snippet in the developer terminal.
  static void printRandomSuggestion() => sug.printRandomSuggestion();

  const Like({
    super.key,
    required this.child,
    this.isSyncing,
    this.syncOverlay,
    this.loadingWidget,
    this.showConnectivityToasts = true,
    this.getToken,
    this.refreshToken,
    this.onLogout,
    this.getApiKey,
    this.authConfig,
    this.syncProgressBuilder,
    this.toastConfig,
    this.toastDelegate,
    this.devTool,
  });

  @override
  State<Like> createState() => _LikeState();
}

class _LikeState extends State<Like> {
  StreamSubscription<bool>? _subscription;
  Future<void>? _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
  }

  Future<void> _initialize() async {
    void logDebug(String msg) {
      if (LikeConstants.debugMode && !LikeConstants.silentConsole) {
        debugPrint(msg);
      }
    }

    logDebug('DEBUG: _initialize starting');
    try {
      // 1. Centralized Initialization (Hive, Connectivity, Client, Sync)
      final engineConfig = LikeConstants.current;

      logDebug('DEBUG: Calling LikeService.init');
      await LikeService.init(config: engineConfig);
      logDebug('DEBUG: LikeService.init completed');

      // 2. Toasts & Security (Context-dependent setup)
      if (widget.toastConfig != null) {
        if (widget.toastConfig!.online != null) {
          LikeToastManager.onlineWidget = widget.toastConfig!.online;
        }
        if (widget.toastConfig!.offline != null) {
          LikeToastManager.offlineWidget = widget.toastConfig!.offline;
        }
      }

      if (widget.toastDelegate != null) {
        LikeToastManager.setDelegate(widget.toastDelegate!);
      } else if (widget.syncProgressBuilder != null ||
          widget.toastConfig?.syncProgressBuilder != null) {
        LikeToastManager.setDelegate(
          DefaultLikeToastDelegate(
            syncProgressBuilder: widget.syncProgressBuilder ??
                widget.toastConfig?.syncProgressBuilder,
          ),
        );
      }

      // Hook up OAuth Interceptors & AuthConfig
      final effectiveAuthConfig = widget.authConfig ??
          LikeAuthConfig(
            getToken: widget.getToken,
            refreshToken: widget.refreshToken,
            onLogout: widget.onLogout,
            getApiKey: widget.getApiKey,
          );

      if (effectiveAuthConfig.hasTokenSupplier ||
          effectiveAuthConfig.hasRefreshSupplier ||
          effectiveAuthConfig.hasLogoutSupplier ||
          effectiveAuthConfig.hasApiKeySupplier) {
        LikeConstants.apply(
          LikeConstants.current.copyWith(authConfig: effectiveAuthConfig),
        );
      }

      if (widget.getToken != null) {
        LikeAuthInterceptor.getToken = widget.getToken!;
      }
      if (widget.refreshToken != null) {
        LikeAuthInterceptor.refreshToken = widget.refreshToken!;
      }
      if (widget.onLogout != null) {
        LikeAuthInterceptor.onLogout = widget.onLogout!;
      }
      if (widget.getApiKey != null) {
        LikeAuthInterceptor.getApiKey = widget.getApiKey!;
      }

      // 3. Connectivity Toasts Listener
      if (widget.showConnectivityToasts) {
        _subscription = LikeConnectivityManager().connectionChange.listen((
          isConnected,
        ) {
          if (!mounted) return;
          LikeToastManager.showConnectivityToast(isConnected);
        });
      }
      logDebug('DEBUG: _initialize completed successfully');
    } catch (e, stack) {
      logDebug('DEBUG: _initialize threw exception: $e\n$stack');
      rethrow;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Show loading screen while bootstrapping Storage database and Connectivity Managers
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.loadingWidget ?? const _DefaultLoadingScreen();
        }

        // Build the core app stack with a lightweight Overlay and Directionality
        // to guarantee that the registered context has an Overlay ancestor in release builds.
        final coreStack = Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) {
                  return Builder(
                    builder: (innerContext) {
                      // Register BuildContext to allow showing toasts without context from anywhere in the codebase!
                      LikeToastManager.registerContext(innerContext);
                      return Stack(
                        alignment: Alignment.topLeft,
                        children: [
                          widget.child,
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                widget.isSyncing ?? LikeService.isSyncing,
                            builder: (context, syncing, _) {
                              if (!syncing) return const SizedBox.shrink();
                              return widget.syncOverlay ??
                                  _DefaultSyncOverlay();
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
        );

        // Wrap with devTool overlay if provided (debug-only by convention)
        final appTree =
            widget.devTool != null ? widget.devTool!(coreStack) : coreStack;

        return ToastificationWrapper(child: appTree);
      },
    );
  }
}

/// The default synchronizing blocker modal widget.
class _DefaultSyncOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: ColoredBox(
          color: Colors.black45,
          child: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Synchronizing Data...',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Please do not close the app.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The default loader screen shown during engine bootstrap.
class _DefaultLoadingScreen extends StatelessWidget {
  const _DefaultLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
    );
  }
}

/// Configuration for the LIKE toast system.
class LikeToastConfig {
  /// Custom widget for the online state.
  final Widget? online;

  /// Custom widget for the offline state.
  final Widget? offline;

  /// Custom builder for synchronization progress.
  final Widget Function(String title, String message, double progress)?
      syncProgressBuilder;

  const LikeToastConfig({this.online, this.offline, this.syncProgressBuilder});
}
