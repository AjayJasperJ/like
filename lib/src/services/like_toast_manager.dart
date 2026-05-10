import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';
import 'package:like/src/services/like_toast_delegate.dart';
import 'package:like/src/models/like_state_response.dart';

/// Centralized manager for handling toasts in the LIKE package.
/// Uses a [LikeToastDelegate] to allow users to override the default UI.
class LikeToastManager {
  static LikeToastDelegate _delegate = DefaultLikeToastDelegate();
  static BuildContext? _context;

  /// Updates the delegate to use a custom UI implementation.
  static void setDelegate(LikeToastDelegate delegate) {
    _delegate = delegate;
  }

  /// Registers a global context for contextless toast calls.
  static void registerContext(BuildContext context) {
    _context = context;
  }

  /// Shows a toast for connectivity changes.
  static void showConnectivityToast(bool isOnline, {BuildContext? context}) {
    final effectiveContext = context ?? _context;
    if (effectiveContext == null) return;
    _delegate.showConnectivityToast(effectiveContext, isOnline);
  }

  /// Shows a toast for API response results.
  static void showResponseToast(
    LikeStateResponse<dynamic> response, {
    BuildContext? context,
  }) {
    final effectiveContext = context ?? _context;
    if (effectiveContext == null) return;
    _delegate.showResponseToast(effectiveContext, response);
  }

  /// Shows a generic toast.
  static void showToast({
    BuildContext? context,
    required String message,
    String? submessage,
    required ToastificationType type,
    Duration? autoCloseDuration,
  }) {
    final effectiveContext = context ?? _context;
    if (effectiveContext == null) return;
    _delegate.showToast(
      effectiveContext,
      message: message,
      submessage: submessage,
      type: type,
      autoCloseDuration: autoCloseDuration,
    );
  }

  /// Shows a custom toast widget with advanced control.
  static void showCustomToast({
    BuildContext? context,
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
    final effectiveContext = context ?? _context;
    if (effectiveContext == null) return;
    _delegate.showCustomToast(
      effectiveContext,
      child: child,
      animationType: animationType,
      exitAnimationType: exitAnimationType,
      dismissDirection: dismissDirection,
      autoCloseDuration: autoCloseDuration,
      isDismissible: isDismissible,
      alignment: alignment,
      margin: margin,
      onTap: onTap,
      entryDuration: entryDuration,
      exitDuration: exitDuration,
      slideInOffset: slideInOffset,
      slideOutOffset: slideOutOffset,
    );
  }

  /// Shows a loading toast.
  static void showLoadingToast({
    BuildContext? context,
    required String title,
    String? message,
  }) {
    final effectiveContext = context ?? _context;
    if (effectiveContext == null) return;
    _delegate.showLoadingToast(effectiveContext, title: title, message: message);
  }

  /// Shows a toast for synchronization progress.
  static void showSyncProgressToast({
    BuildContext? context,
    required String title,
    required String message,
    required double progress,
  }) {
    final effectiveContext = context ?? _context;
    if (effectiveContext == null) return;
    _delegate.showSyncProgressToast(
      effectiveContext,
      title: title,
      message: message,
      progress: progress,
    );
  }

  /// Dismisses all active toasts managed by the delegate.
  static void dismiss({BuildContext? context, bool showRemoveAnimation = false}) {
    final effectiveContext = context ?? _context;
    if (effectiveContext == null) return;
    _delegate.dismiss(effectiveContext, showRemoveAnimation: showRemoveAnimation);
  }
}

/// A central class that developers can use to define application-specific toast types.
/// Fresh developers can create extensions on this class to add their own toast shortcuts.
///
/// Example:
/// ```dart
/// extension MyAppToasts on LikeToastType {
///   void showSuccess() {
///     LikeToastManager.showCustomToast(child: MySuccessWidget());
///   }
/// }
/// ```
class LikeToastType {
  const LikeToastType._();
}
