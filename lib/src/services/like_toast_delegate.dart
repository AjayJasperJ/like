import 'package:flutter/material.dart';
import 'package:like/src/services/like_toast_manager.dart';
import 'package:toastification/toastification.dart';
import 'package:like/src/models/like_state_response.dart';

/// Supported animation types for LIKE toasts.
enum LikeToastAnimation { slide, fade, scale }

/// Delegate for handling Toast UI in the LIKE package.
/// Allows users to provide custom designs for connectivity, success, and error toasts.
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
    required ToastificationType type,
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

/// The default implementation of [LikeToastDelegate] using standard Material widgets.
class DefaultLikeToastDelegate implements LikeToastDelegate {
  /// A builder for custom synchronization progress toasts.
  final Widget Function(String title, String message, double progress)?
  syncProgressBuilder;

  /// Creates a [DefaultLikeToastDelegate] with optional custom builders.
  DefaultLikeToastDelegate({this.syncProgressBuilder});

  ToastificationItem? _current;

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
      type: isOnline ? ToastificationType.success : ToastificationType.error,
    );
  }

  @override
  void showResponseToast(
    BuildContext context,
    LikeStateResponse<dynamic> response,
  ) {
    if (response.isIdle || response.isLoading || response.isRefreshing) return;

    final type = response.isSuccess
        ? ToastificationType.success
        : (response.isError
              ? ToastificationType.warning
              : ToastificationType.error);

    showToast(context, message: response.message, type: type);
  }

  @override
  void showToast(
    BuildContext context, {
    required String message,
    String? submessage,
    required ToastificationType type,
    Duration? autoCloseDuration,
  }) {
    if (_current != null) {
      toastification.dismiss(_current!, showRemoveAnimation: false);
    }

    _current = toastification.show(
      context: context,
      type: type,
      style: ToastificationStyle.flat,
      title: Text(message),
      description: (submessage != null && submessage.isNotEmpty)
          ? Text(submessage)
          : null,
      autoCloseDuration: autoCloseDuration ?? const Duration(seconds: 4),
      alignment: Alignment.topCenter,
    );
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
    if (_current != null) {
      toastification.dismiss(_current!, showRemoveAnimation: false);
    }

    final effectiveExitDuration = exitDuration ?? entryDuration;
    final maxDuration = entryDuration > effectiveExitDuration
        ? entryDuration
        : effectiveExitDuration;

    _current = toastification.showCustom(
      context: context,
      alignment: alignment,
      autoCloseDuration: autoCloseDuration,
      animationDuration: maxDuration,
      callbacks: ToastificationCallbacks(onTap: (item) => onTap?.call()),
      animationBuilder: (context, animation, alignment, toastChild) {
        final isExiting =
            animation.status == AnimationStatus.reverse ||
            animation.status == AnimationStatus.dismissed;

        final currentDuration = isExiting
            ? effectiveExitDuration
            : entryDuration;
        final ratio =
            currentDuration.inMilliseconds / maxDuration.inMilliseconds;

        final curved = CurvedAnimation(
          parent: animation,
          curve: Interval(0.0, ratio, curve: Curves.easeInOut),
        );

        final effectiveType = (isExiting && exitAnimationType != null)
            ? exitAnimationType
            : animationType;

        switch (effectiveType) {
          case LikeToastAnimation.fade:
            return FadeTransition(opacity: curved, child: toastChild);
          case LikeToastAnimation.scale:
            return ScaleTransition(scale: curved, child: toastChild);
          case LikeToastAnimation.slide:
            final defaultOffsetVar = alignment.y > 0 ? 1.0 : -1.0;
            final offset = isExiting
                ? (slideOutOffset ??
                      slideInOffset ??
                      Offset(0, defaultOffsetVar))
                : (slideInOffset ?? Offset(0, defaultOffsetVar));

            return SlideTransition(
              position: Tween<Offset>(
                begin: offset,
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(opacity: curved, child: toastChild),
            );
        }
      },
      builder: (context, holder) {
        Widget content = Padding(
          padding: margin ?? EdgeInsets.zero,
          child: Material(
            color: Colors.transparent,
            child: Center(child: child),
          ),
        );

        if (dismissDirection == DismissDirection.none || !isDismissible) {
          return content;
        }

        return MouseRegion(
          onEnter: (_) => holder.pause(),
          onExit: (_) => holder.start(),
          child: GestureDetector(
            onLongPressStart: (_) => holder.pause(),
            onLongPressEnd: (_) => holder.start(),
            child: Dismissible(
              key: ValueKey('dismiss_${holder.id}'),
              direction: dismissDirection,
              onDismissed: (_) {
                toastification.dismiss(holder, showRemoveAnimation: false);
              },
              child: content,
            ),
          ),
        );
      },
    );
  }

  @override
  void showLoadingToast(
    BuildContext context, {
    required String title,
    String? message,
  }) {
    if (_current != null) {
      toastification.dismiss(_current!, showRemoveAnimation: false);
    }

    _current = toastification.show(
      context: context,
      type: ToastificationType.info,
      style: ToastificationStyle.flat,
      title: Text(title),
      description: message != null ? Text(message) : null,
      autoCloseDuration: null,
      showProgressBar: true,
      alignment: Alignment.topCenter,
    );
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

    // Ported sync UI logic
    showCustomToast(
      context,
      alignment: Alignment.bottomCenter,
      autoCloseDuration: null,
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
                value: progress,
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
    if (_current != null) {
      toastification.dismiss(
        _current!,
        showRemoveAnimation: showRemoveAnimation,
      );
      _current = null;
    } else {
      toastification.dismissAll(delayForAnimation: showRemoveAnimation);
    }
  }
}
