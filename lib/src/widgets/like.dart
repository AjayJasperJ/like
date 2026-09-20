import 'dart:async';
import 'package:flutter/material.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:like/src/core/like_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/interceptors/like_auth_interceptor.dart';
import 'package:like/src/services/like_service.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_utils.dart';
import 'package:like/src/debug/like_suggestions.dart' as sug;

/// # Like
///
/// The **Master Coordinator & Root Wrapper Widget** that powers the entire LIKE network engine.
class Like extends StatefulWidget {
  /// The main application widget tree (typically your [MaterialApp]).
  final Widget child;

  /// A custom [ValueNotifier] used to programmatically trigger or listen to the global syncing overlay.
  final ValueNotifier<bool>? isSyncing;

  /// The custom widget overlay shown when the app is performing background data synchronization (`isSyncing` is true).
  final Widget? syncOverlay;

  /// A custom loading screen displayed while the LIKE engine initializes.
  final Widget? loadingWidget;

  /// Whether to automatically trigger connectivity notifications when connection status changes.
  final bool showConnectivityToasts;

  /// Optional notification/toast callback hooks configuration.
  final LikeToastConfig? toastConfig;

  /// Optional debug-only wrapper used to inject developer dashboards or HUD overlays.
  final Widget Function(Widget child)? devTool;

  /// Optional authentication configuration.
  final LikeAuthConfig? authConfig;

  /// Prints a cheatsheet listing all features of the LIKE package in the terminal.
  static void help() => sug.printAllSuggestions();

  /// Prints a random suggestion in the developer terminal.
  static void printRandomSuggestion() => sug.printRandomSuggestion();

  const Like({
    super.key,
    required this.child,
    this.isSyncing,
    this.syncOverlay,
    this.loadingWidget,
    this.showConnectivityToasts = true,
    this.authConfig,
    this.toastConfig,
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
      final engineConfig = LikeConstants.current;
      await LikeService.init(config: engineConfig);

      if (widget.toastConfig != null) {
        LikeConstants.apply(
          LikeConstants.current.copyWith(toastConfig: widget.toastConfig),
        );
      }

      if (widget.authConfig != null) {
        LikeConstants.apply(
          LikeConstants.current.copyWith(authConfig: widget.authConfig),
        );
        if (widget.authConfig!.getToken != null) {
          LikeAuthInterceptor.getToken = widget.authConfig!.getToken!;
        }
        if (widget.authConfig!.refreshToken != null) {
          LikeAuthInterceptor.refreshToken = widget.authConfig!.refreshToken!;
        }
        if (widget.authConfig!.onLogout != null) {
          LikeAuthInterceptor.onLogout = widget.authConfig!.onLogout!;
        }
        if (widget.authConfig!.getApiKey != null) {
          LikeAuthInterceptor.getApiKey = widget.authConfig!.getApiKey!;
        }
      }

      if (widget.showConnectivityToasts) {
        _subscription = LikeConnectivityManager().connectionChange.listen((
          isConnected,
        ) {
          if (!mounted) return;
          final cfg = LikeConstants.current.toastConfig;
          if (isConnected) {
            const msg = 'Internet Connection Restored';
            if (cfg?.connected != null) {
              cfg!.connected!(msg);
            } else {
              LikeUtils.showToast(
                message: msg,
                type: LikeToastStyle.success,
                context: context,
              );
            }
          } else {
            const msg = 'No Internet Connection';
            if (cfg?.disconnected != null) {
              cfg!.disconnected!(msg);
            } else {
              LikeUtils.showToast(
                message: msg,
                type: LikeToastStyle.warning,
                context: context,
              );
            }
          }
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
        if (snapshot.connectionState != ConnectionState.done) {
          return widget.loadingWidget ?? const _DefaultLoadingScreen();
        }

        final coreStack = Stack(
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

        return widget.devTool != null ? widget.devTool!(coreStack) : coreStack;
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
