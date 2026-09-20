import 'package:flutter/material.dart';
import 'package:like/src/core/like_constants.dart';

/// Enum for standardized LIKE toast styles.
enum LikeToastStyle { success, info, warning, error }

/// Internal utilities for the LIKE networking engine.
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

  /// Displays a notification message. If a custom toastConfig callback is set for the event,
  /// it is invoked instead of showing the default ScaffoldMessenger message.
  static void showToast({
    required String message,
    String? submessage,
    required LikeToastStyle type,
    BuildContext? context,
  }) {
    final fullMessage = submessage != null && submessage.isNotEmpty
        ? '$message: $submessage'
        : message;

    final config = LikeConstants.current.toastConfig;
    if (config != null) {
      if (type == LikeToastStyle.info && message.contains('offline') && config.cacheUse != null) {
        config.cacheUse!(fullMessage);
        return;
      }
    }

    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fullMessage),
        ),
      );
    }
  }

  /// Displays a toast notification when data is served from L2/L3 cache while offline.
  static void notifyCacheUse(BuildContext context) {
    const msg = 'You are viewing offline data';
    final customCb = LikeConstants.current.toastConfig?.cacheUse;
    if (customCb != null) {
      customCb(msg);
      return;
    }
    showToast(
      message: msg,
      type: LikeToastStyle.info,
      context: context,
    );
  }

  /// Displays a toast notification during SWR (Stale-While-Revalidate) background refreshes.
  static void notifySwrUse(BuildContext context) {
    const msg = 'Loading fresh data in background...';
    final customCb = LikeConstants.current.toastConfig?.swrUse;
    if (customCb != null) {
      customCb(msg);
      return;
    }
    showToast(
      message: msg,
      type: LikeToastStyle.info,
      context: context,
    );
  }
}
