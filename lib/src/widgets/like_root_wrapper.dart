import 'dart:async';
import 'package:flutter/material.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:toastification/toastification.dart';
import 'package:like/src/interceptors/like_auth_interceptor.dart';
import 'package:like/src/services/like_service.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_toast_manager.dart';
import 'package:like/src/services/like_toast_delegate.dart';

/// The top-level wrapper for applications using the LIKE networking package.
/// Handles initialization of connectivity monitoring, persistent storage,
/// background synchronization, and authentication interceptors.
class Like extends StatefulWidget {
  /// The main application widget tree.
  final Widget child;

  /// A [ValueNotifier] used to show/hide the global synchronization overlay.
  /// If not provided, the widget will automatically use [LikeService.isSyncing].
  final ValueNotifier<bool>? isSyncing;

  /// Custom builder for the synchronization progress toast.
  final Widget Function(String title, String message, double progress)?
      syncProgressBuilder;

  /// Custom widget to display when [isSyncing] is true.
  final Widget? syncOverlay;

  /// Custom widget to display while the LIKE engine is performing its initial setup.
  final Widget? loadingWidget;

  /// Whether to automatically display [Toastification] alerts when internet connectivity changes.
  final bool showConnectivityToasts;

  /// The base URL for all network requests. This is the root-level configuration.
  final String? baseUrl;

  /// A function used by [LikeAuthInterceptor] to retrieve the current user's session token.
  final Future<String?> Function()? getToken;

  /// A function used by [LikeAuthInterceptor] to perform token refresh.
  final Future<String?> Function()? refreshToken;

  /// A function used by [LikeAuthInterceptor] to handle logout on authentication error.
  final Future<void> Function({int? statusCode, bool force})? onLogout;

  /// A function used by [LikeAuthInterceptor] to retrieve the API Key.
  final Future<String?> Function()? getApiKey;

  /// Configuration for network-related toasts.
  final LikeToastConfig? toastConfig;

  /// A custom delegate to control how network-related toasts are displayed and styled.
  /// If provided, this takes precedence over individual widget overrides.
  final LikeToastDelegate? toastDelegate;

  /// Optional debug-only wrapper injected by an external devtool package.
  ///
  /// Receives the fully assembled [child] tree and wraps it with overlay
  /// widgets (e.g., a developer panel FAB). Should be `null` in production.
  ///
  /// Example with `like_devtool`:
  /// ```dart
  /// Like(
  ///   baseUrl: 'https://api.example.com',
  ///   devTool: (child) => LikeDevTool(child: child),
  ///   child: MyApp(),
  /// )
  /// ```
  final Widget Function(Widget child)? devTool;

  /// Global navigator key that can be passed to [MaterialApp.navigatorKey]
  /// to enable contextless toasts to inherit the application's theme and navigator.
  static GlobalKey<NavigatorState> get navigatorKey => LikeToastManager.navigatorKey;

  const Like({
    super.key,
    required this.child,
    this.isSyncing,
    this.syncOverlay,
    this.loadingWidget,
    this.showConnectivityToasts = true,
    this.baseUrl,
    this.getToken,
    this.refreshToken,
    this.onLogout,
    this.getApiKey,
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
    print('DEBUG: _initialize starting');
    try {
      // 1. Centralized Initialization (Hive, Connectivity, Client, Sync)
      // Merge root-level baseUrl into the current app-level config
      final engineConfig = LikeConstants.current.copyWith(
        baseUrl: widget.baseUrl,
      );

      print('DEBUG: Calling LikeService.init');
      await LikeService.init(config: engineConfig);
      print('DEBUG: LikeService.init completed');

      // 2. Toasts & Security (Context-dependent)
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
      print('DEBUG: _initialize completed successfully');
    } catch (e, stack) {
      print('DEBUG: _initialize threw exception: $e\n$stack');
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
                      LikeToastManager.registerContext(innerContext);
                      return Stack(
                        alignment: Alignment.topLeft,
                        children: [
                          widget.child,
                          ValueListenableBuilder<bool>(
                            valueListenable: widget.isSyncing ?? LikeService.isSyncing,
                            builder: (context, syncing, _) {
                              if (!syncing) return const SizedBox.shrink();
                              return widget.syncOverlay ?? _DefaultSyncOverlay();
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
