import 'package:flutter/material.dart';
import 'package:like/src/services/like_toast_manager.dart';
import 'package:like/src/models/like_state_response.dart';

/// Supported animation types for custom LIKE toasts.
enum LikeToastAnimation { slide, fade, scale }

/// Standard toast message severity types for LIKE.
enum LikeToastMessageType { success, info, warning, error }

/// Delegate for handling Toast UI in the LIKE package.
/// Allows users to provide custom designs or custom toast libraries (e.g. Toastification, CherryToast).
abstract class LikeToastDelegate {
  /// Shows a toast for connectivity changes.
  void showConnectivityToast(BuildContext context, bool isOnline);

  /// Shows a toast for API response results (Success/Error/Exception).
  void showResponseToast(
    BuildContext context,
    LikeStateResponse<dynamic> response,
  );

  /// Shows a generic toast.
  void showToast(
    BuildContext context, {
    required String message,
    String? submessage,
    required LikeToastMessageType type,
    Duration? autoCloseDuration,
  });

  /// Shows a custom toast widget with advanced control.
  void showCustomToast(
    BuildContext context, {
    required Widget child,
    LikeToastAnimation animationType = LikeToastAnimation.slide,
    LikeToastAnimation? exitAnimationType,
    DismissDirection dismissDirection = DismissDirection.horizontal,
    Duration? autoCloseDuration = const Duration(seconds: 3),
    bool isDismissible = true,
    Alignment alignment = Alignment.topCenter,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
    Duration entryDuration = const Duration(milliseconds: 600),
    Duration? exitDuration,
    Offset? slideInOffset,
    Offset? slideOutOffset,
  });

  /// Shows a loading/progress toast.
  void showLoadingToast(
    BuildContext context, {
    required String title,
    String? message,
  });

  /// Shows a toast for synchronization progress.
  void showSyncProgressToast(
    BuildContext context, {
    required String title,
    required String message,
    required double progress,
  });

  /// Dismisses specific toasts or all managed toasts.
  void dismiss(BuildContext context, {bool showRemoveAnimation = false});
}

/// Anti-fragile default implementation of [LikeToastDelegate] using Flutter's zero-dependency [ScaffoldMessenger].
class DefaultLikeToastDelegate implements LikeToastDelegate {
  /// A builder for custom synchronization progress toasts.
  final Widget Function(String title, String message, double progress)?
      syncProgressBuilder;

  /// Creates a [DefaultLikeToastDelegate] with optional custom builders.
  DefaultLikeToastDelegate({this.syncProgressBuilder});

  ScaffoldMessengerState? _findScaffoldMessenger(BuildContext context) {
    try {
      return ScaffoldMessenger.maybeOf(context);
    } catch (_) {
      return null;
    }
  }

  @override
  void showConnectivityToast(BuildContext context, bool isOnline) {
    final customWidget = isOnline
        ? LikeToastManager.onlineWidget
        : LikeToastManager.offlineWidget;

    if (customWidget != null) {
      showCustomToast(context, child: customWidget);
      return;
    }

    showToast(
      context,
      message: isOnline ? 'Back Online' : 'No Connection',
      submessage: isOnline
          ? 'Internet connection restored.'
          : 'Please check your network.',
      type: isOnline ? LikeToastMessageType.success : LikeToastMessageType.error,
    );
  }

  @override
  void showResponseToast(
    BuildContext context,
    LikeStateResponse<dynamic> response,
  ) {
    if (response.isIdle || response.isLoading || response.isRefreshing) return;

    final type = response.isSuccess
        ? LikeToastMessageType.success
        : (response.isError
            ? LikeToastMessageType.warning
            : LikeToastMessageType.error);

    showToast(context, message: response.message, type: type);
  }

  @override
  void showToast(
    BuildContext context, {
    required String message,
    String? submessage,
    required LikeToastMessageType type,
    Duration? autoCloseDuration,
  }) {
    final messenger = _findScaffoldMessenger(context);
    if (messenger == null) return;

    final theme = Theme.of(context);
    final colors = _resolveColors(type, theme);

    messenger.hideCurrentSnackBar();

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(colors.icon, color: colors.foreground, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    color: colors.foreground,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (submessage != null && submessage.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    submessage,
                    style: TextStyle(
                      color: colors.foreground.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      backgroundColor: colors.background,
      behavior: SnackBarBehavior.floating,
      duration: autoCloseDuration ?? const Duration(seconds: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      elevation: 4,
    );

    messenger.showSnackBar(snackBar);
  }

  @override
  void showCustomToast(
    BuildContext context, {
    required Widget child,
    LikeToastAnimation animationType = LikeToastAnimation.slide,
    LikeToastAnimation? exitAnimationType,
    DismissDirection dismissDirection = DismissDirection.horizontal,
    Duration? autoCloseDuration = const Duration(seconds: 3),
    bool isDismissible = true,
    Alignment alignment = Alignment.topCenter,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
    Duration entryDuration = const Duration(milliseconds: 600),
    Duration? exitDuration,
    Offset? slideInOffset,
    Offset? slideOutOffset,
  }) {
    final messenger = _findScaffoldMessenger(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    final snackBar = SnackBar(
      content: GestureDetector(
        onTap: onTap,
        child: child,
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      duration: autoCloseDuration ?? const Duration(seconds: 3),
      margin: margin ?? const EdgeInsets.all(16),
      padding: EdgeInsets.zero,
      dismissDirection: isDismissible ? dismissDirection : DismissDirection.none,
    );

    messenger.showSnackBar(snackBar);
  }

  @override
  void showLoadingToast(
    BuildContext context, {
    required String title,
    String? message,
  }) {
    final messenger = _findScaffoldMessenger(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();

    final snackBar = SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (message != null && message.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      backgroundColor: Colors.black87,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(days: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    );

    messenger.showSnackBar(snackBar);
  }

  @override
  void showSyncProgressToast(
    BuildContext context, {
    required String title,
    required String message,
    required double progress,
  }) {
    if (syncProgressBuilder != null) {
      showCustomToast(
        context,
        alignment: Alignment.bottomCenter,
        autoCloseDuration: null,
        child: syncProgressBuilder!(title, message, progress),
      );
      return;
    }

    showCustomToast(
      context,
      alignment: Alignment.bottomCenter,
      autoCloseDuration: const Duration(seconds: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(99),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                strokeWidth: 2.5,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dismiss(BuildContext context, {bool showRemoveAnimation = false}) {
    final messenger = _findScaffoldMessenger(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
    }
  }

  _ToastColors _resolveColors(LikeToastMessageType type, ThemeData theme) {
    switch (type) {
      case LikeToastMessageType.success:
        return const _ToastColors(
          background: Color(0xFF1B5E20),
          foreground: Colors.white,
          icon: Icons.check_circle_outline,
        );
      case LikeToastMessageType.info:
        return const _ToastColors(
          background: Color(0xFF0D47A1),
          foreground: Colors.white,
          icon: Icons.info_outline,
        );
      case LikeToastMessageType.warning:
        return const _ToastColors(
          background: Color(0xFFE65100),
          foreground: Colors.white,
          icon: Icons.warning_amber_outlined,
        );
      case LikeToastMessageType.error:
        return const _ToastColors(
          background: Color(0xFFB71C1C),
          foreground: Colors.white,
          icon: Icons.error_outline,
        );
    }
  }
}

class _ToastColors {
  final Color background;
  final Color foreground;
  final IconData icon;

  const _ToastColors({
    required this.background,
    required this.foreground,
    required this.icon,
  });
}
