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

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    void logDebug(String msg) {
      if (LikeConstants.debugMode && !LikeConstants.silentConsole) {
        debugPrint(msg);
      }
    }

    logDebug('DEBUG: _initialize starting');
    try {
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

      // Apply widget-level configuration before asynchronous engine startup so
      // descendants can read it during their first frame.
      final engineConfig = LikeConstants.current;
      await LikeService.init(config: engineConfig);

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
    return widget.devTool != null
        ? widget.devTool!(widget.child)
        : widget.child;
  }
}
