import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/services/like_utils.dart';

/// # `updateNotifier<T>`
///
/// The **Full Service** async action handler designed to manage user feedback and side-effects
/// automatically when an API action changes state.
///
/// ### Built-in Automated Actions:
/// 1. **Toasting:** Automatically pops up styled toast messages for success, error, or loading.
/// 2. **Haptic Feedback:** Vibrates the device using custom weights (Light impact on success,
///    Medium on warnings/errors, Heavy on severe network exceptions) to provide professional physical feedback.
/// 3. **Callback Mapping:** Automatically routes to [onSuccess], [onError], [onException], and [onInit]
///    async functions.
/// 4. **Context Safety Guards:** Since API requests resolve asynchronously, the user might navigate
///    away from the active page before the request completes. This helper strictly checks
///    `context.mounted` to prevent popping toasts or calling widgets on discarded/unmounted contexts!
///
/// ### Example Usage:
/// ```dart
/// ElevatedButton(
///   onPressed: () async {
///     final state = await myNotifier.updateProfile(newProfile);
///     await updateNotifier<UserProfile>(
///       response: state,
///       context: context,
///       onSuccess: (data) async {
///         Navigator.pop(context); // close screen on success!
///       },
///     );
///   },
///   child: Text('Save Profile'),
/// );
/// ```
Future<void> updateNotifier<T extends Object>({
  required LikeStateResponse<dynamic> response,
  BuildContext? context,
  Future<void> Function(LikeState state)? onInit,
  Future<void> Function(T data)? onSuccess,
  Future<void> Function(LikeError error)? onError,
  Future<void> Function(String message)? onException,

  // Toast Control Flags (Disable toasts for specific states if desired)
  bool disableLoadingToast = true,
  bool disableSuccessToast = false,
  bool disableErrorToast = false,
  bool disableExceptionToast = false,
  bool disableCancelledToast = true,
  bool enableHaptics = true,
  Map<LikeState, String>? messageOverrides,
}) async {
  // 1. Fire initialization callback
  if (onInit != null) {
    if (context != null && !context.mounted) return;
    await onInit(response.state);
  }

  // 2. Safe casting utility
  T? castData(dynamic data) {
    if (data == null) return null;
    if (data is T) return data;
    try {
      return data as T;
    } catch (_) {
      return null;
    }
  }

  // 3. Resolve user message overrides
  String resolveMessage(String defaultMsg, LikeState state) {
    return messageOverrides != null && messageOverrides.containsKey(state)
        ? messageOverrides[state]!
        : defaultMsg;
  }

  // 4. Map and execute state-specific automated actions
  switch (response.state) {
    case LikeState.idle:
      break;

    case LikeState.loading:
      if (!disableLoadingToast) {
        if (context != null && !context.mounted) return;
        LikeUtils.showToast(
          context: context,
          message: resolveMessage(response.message, LikeState.loading),
          type: LikeToastStyle.info,
        );
      }
      break;

    case LikeState.success:
    case LikeState.refreshing:
    case LikeState.staleWhileRevalidate:
      if (onSuccess != null) {
        final data = castData(response.data);
        if (data != null) {
          if (context != null && !context.mounted) return;
          await onSuccess(data);
        }
      }

      if (response.state == LikeState.success && !disableSuccessToast) {
        if (context != null && !context.mounted) return;
        if (enableHaptics) {
          HapticFeedback.lightImpact(); // Light vibration on success
        }
        LikeUtils.showToast(
          context: context,
          message: resolveMessage(response.resolvedMessage, LikeState.success),
          type: LikeToastStyle.success,
        );
      }
      break;

    case LikeState.error:
      final error = response.error ??
          LikeError(
            message: response.message,
            type: response.errorType ?? LikeApiErrorType.unknown,
            code: response.code,
          );

      if (context != null && !context.mounted) return;
      await onError?.call(error);

      if (!disableErrorToast) {
        if (context != null && !context.mounted) return;
        if (enableHaptics) {
          HapticFeedback.mediumImpact(); // Medium warning vibration
        }
        if (error.type != LikeApiErrorType.cancelled ||
            !disableCancelledToast) {
          LikeUtils.showToast(
            context: context,
            message: resolveMessage(error.message, LikeState.error),
            type: LikeToastStyle.warning,
          );
        }
      }
      break;

    case LikeState.exception:
      if (context != null && !context.mounted) return;
      await onException?.call(response.message);

      if (!disableExceptionToast) {
        if (context != null && !context.mounted) return;
        if (enableHaptics) {
          HapticFeedback.heavyImpact(); // Strong warning vibration for crashes
        }
        LikeUtils.showToast(
          context: context,
          message: resolveMessage(response.message, LikeState.exception),
          type: LikeToastStyle.error,
        );
      }
      break;
  }
}

/// # `likeWhenNotifier<T>`
///
/// The **Silent / Raw** action handler.
///
/// Unlike `updateNotifier`, this contains absolutely **no** automated toasts, physical vibrations,
/// or context guards. It is a pure, functional state-mapping callback tool.
///
/// ### Use Case:
/// Use this when you want 100% manual, custom control over what happens during state changes,
/// or when triggering requests silently in background processes.
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
      if (onError != null) {
        final error = response.error ??
            LikeError(
              message: response.message,
              type: response.errorType ?? LikeApiErrorType.unknown,
              code: response.code,
            );
        await onError(error);
      }
      break;
    case LikeState.exception:
      if (onException != null) {
        await onException(response.message);
      }
      break;
  }
}

/// # `LikeWhen<T>`
///
/// A clean, declarative **pattern-matching widget** for resolving [LikeStateResponse] snapshots inline.
///
/// Rather than writing full verbose switch-case statements inside your `build` methods,
/// `LikeWhen` allows matching states in a elegant functional declarative style.
///
/// ### Example Usage:
/// ```dart
/// LikeWhen<UserProfile>(
///   response: myProfileState,
///   onLoading: () => LoadingWidget(),
///   onSuccess: (profile) => Text('Welcome back, ${profile.username}'),
///   onError: (err) => ErrorWidget(err.message),
/// );
/// ```
class LikeWhen<T> extends StatelessWidget {
  /// The state response snapshot to match.
  final LikeStateResponse<dynamic> response;

  /// Builder function called when the state is successful and data is ready.
  final Widget Function(T data) onSuccess;

  /// Optional builder called when the initial loading fetch is active.
  final Widget Function()? onLoading;

  /// Optional builder called when the state is in an idle uninitialized phase.
  final Widget Function()? onIdle;

  /// Optional builder called when a server-side error is returned.
  final Widget Function(LikeError error)? onError;

  /// Optional builder called when a client-side exception occurs.
  final Widget Function(String message)? onException;

  const LikeWhen({
    super.key,
    required this.response,
    required this.onSuccess,
    this.onLoading,
    this.onIdle,
    this.onError,
    this.onException,
  });

  T? _castData(dynamic data) {
    if (data == null) return null;
    if (data is T) return data;
    try {
      return data as T;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final casted = _castData(response.data);

    switch (response.state) {
      case LikeState.idle:
        return onIdle?.call() ?? const SizedBox.shrink();

      case LikeState.loading:
        return onLoading?.call() ??
            const Center(child: CircularProgressIndicator());

      case LikeState.success:
      case LikeState.refreshing:
      case LikeState.staleWhileRevalidate:
        if (casted == null) {
          throw StateError(
            'LikeWhen: Success state requires non-null data of type $T. '
            'Received: ${response.data?.runtimeType ?? "null"}',
          );
        }
        return onSuccess(casted);

      case LikeState.error:
        return onError?.call(response.error ??
                LikeError(
                  message: response.message,
                  type: response.errorType ?? LikeApiErrorType.unknown,
                  code: response.code,
                )) ??
            const SizedBox.shrink();

      case LikeState.exception:
        return onException?.call(response.message) ?? const SizedBox.shrink();
    }
  }
}
