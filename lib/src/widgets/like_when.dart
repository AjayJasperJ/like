import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:toastification/toastification.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/services/like_toast_manager.dart';

/// [updateNotifier] is the "Full" action handler.
/// It provides built-in toasting, haptics, and state callbacks.
///
/// Use this for primary actions where you want automatic user feedback.
Future<void> updateNotifier<T extends Object>({
  required LikeStateResponse<dynamic> response,
  BuildContext? context,
  Future<void> Function(LikeState state)? onInit,
  Future<void> Function(T data)? onSuccess,
  Future<void> Function(LikeError error)? onError,
  Future<void> Function(String message)? onException,

  // Toast Control Flags
  bool disableLoadingToast = true,
  bool disableSuccessToast = false,
  bool disableErrorToast = false,
  bool disableExceptionToast = false,
  bool disableCancelledToast = true,

  bool enableHaptics = true,
  Map<LikeState, String>? messageOverrides,
}) async {
  if (onInit != null) await onInit(response.state);

  T? castData(dynamic data) {
    if (data == null) return null;
    if (data is T) return data;
    try {
      return data as T;
    } catch (_) {
      return null;
    }
  }

  String resolveMessage(String defaultMsg, LikeState state) {
    return messageOverrides != null && messageOverrides.containsKey(state)
        ? messageOverrides[state]!
        : defaultMsg;
  }

  switch (response.state) {
    case LikeState.idle:
      break;

    case LikeState.loading:
      if (!disableLoadingToast) {
        if (context != null && !context.mounted) return;
        LikeToastManager.showLoadingToast(
          context: context,
          title: 'Loading',
          message: resolveMessage(response.message, LikeState.loading),
        );
      }
      break;

    case LikeState.success:
    case LikeState.refreshing:
    case LikeState.staleWhileRevalidate:
      if (onSuccess != null) {
        final data = castData(response.data);
        if (data != null) await onSuccess(data);
      }

      if (response.state == LikeState.success && !disableSuccessToast) {
        if (enableHaptics) HapticFeedback.lightImpact();
        if (context != null && !context.mounted) return;
        LikeToastManager.showToast(
          context: context,
          message: resolveMessage(response.resolvedMessage, LikeState.success),
          type: ToastificationType.success,
        );
      }
      break;

    case LikeState.error:
      final error =
          response.error ??
          LikeError(
            message: response.message,
            type: response.errorType ?? LikeApiErrorType.unknown,
            code: response.code,
          );

      await onError?.call(error);

      if (!disableErrorToast) {
        if (enableHaptics) HapticFeedback.mediumImpact();
        if (error.type != LikeApiErrorType.cancelled ||
            !disableCancelledToast) {
          if (context != null && !context.mounted) return;
          LikeToastManager.showToast(
            context: context,
            message: resolveMessage(response.message, LikeState.error),
            type: ToastificationType.warning,
          );
        }
      }
      break;

    case LikeState.exception:
      await onException?.call(response.message);

      if (!disableExceptionToast) {
        if (enableHaptics) HapticFeedback.heavyImpact();
        if (context != null && !context.mounted) return;
        LikeToastManager.showToast(
          context: context,
          message: resolveMessage(response.message, LikeState.exception),
          type: ToastificationType.error,
        );
      }
      break;
  }
}

/// [likeWhenNotifier] is the "Empty" action handler.
/// It contains NO automatic toasts or haptics. Just raw state mapping.
///
/// Use this for full manual control over side-effects in your UI.
Future<void> likeWhenNotifier<T extends Object>({
  required LikeStateResponse<dynamic> response,
  Future<void> Function(T data)? onSuccess,
  Future<void> Function(LikeError error)? onError,
  Future<void> Function(String message)? onException,
  Future<void> Function(LikeState state)? onInit,
}) async {
  if (onInit != null) await onInit(response.state);

  switch (response.state) {
    case LikeState.idle:
    case LikeState.loading:
    case LikeState.refreshing:
      break;
    case LikeState.success:
    case LikeState.staleWhileRevalidate:
      if (onSuccess != null && response.data != null) {
        if (response.data is T) {
          await onSuccess(response.data as T);
        }
      }
      break;
    case LikeState.error:
      if (onError != null && response.error != null) {
        await onError(response.error!);
      }
      break;
    case LikeState.exception:
      if (onException != null) {
        await onException(response.message);
      }
      break;
  }
}
