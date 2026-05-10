import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

/// Enum for standardized LIKE toast types.
enum LikeToastType { success, info, warning, error }

/// Internal utilities for the LIKE networking engine.
/// Matches enterprise's NetworkUtils parity.
class LikeUtils {
  /// Deeply casts a dynamic map/list into a type-safe `Map<String, dynamic>` structure.
  /// Required for consistent Hive and JSON handling.
  static dynamic castToMapStringDynamic(dynamic data) {
    if (data is Map) {
      return data.map<String, dynamic>(
        (key, value) => MapEntry(key.toString(), castToMapStringDynamic(value)),
      );
    } else if (data is List) {
      return data.map((e) => castToMapStringDynamic(e)).toList();
    }
    return data;
  }

  /// Displays a standardized toast notification.
  static void showToast({
    required String message,
    String? submessage,
    required LikeToastType type,
    BuildContext? context,
  }) {
    // If context is null, it will use global toastification if available,
    // or simply log if not. Host app should ideally provide a context or use RootWrapper.
    toastification.show(
      context: context,
      title: Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
      description: (submessage != null && submessage.trim().isNotEmpty)
          ? Text(submessage)
          : null,
      type: _mapType(type),
      style: ToastificationStyle.flat,
      autoCloseDuration: const Duration(seconds: 4),
      alignment: Alignment.topCenter,
    );
  }

  static ToastificationType _mapType(LikeToastType type) {
    switch (type) {
      case LikeToastType.success:
        return ToastificationType.success;
      case LikeToastType.info:
        return ToastificationType.info;
      case LikeToastType.warning:
        return ToastificationType.warning;
      case LikeToastType.error:
        return ToastificationType.error;
    }
  }

  /// Displays a toast notification when data is served from L2/L3 cache while offline.
  static void notifyCacheUse(BuildContext context) {
    showToast(
      message: 'You are viewing offline data',
      type: LikeToastType.info,
      context: context,
    );
  }

  /// Displays a toast notification during SWR (Stale-While-Revalidate) background refreshes.
  static void notifySwrUse(BuildContext context) {
    showToast(
      message: 'Loading fresh data in background...',
      type: LikeToastType.info,
      context: context,
    );
  }
}
