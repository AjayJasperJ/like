import 'package:flutter/material.dart';
import 'package:like/src/services/like_toast_delegate.dart';
import 'package:like/src/services/like_toast_manager.dart';

/// Enum for standardized LIKE toast styles.
enum LikeToastStyle { success, info, warning, error }

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
    required LikeToastStyle type,
    BuildContext? context,
  }) {
    LikeToastManager.showToast(
      context: context,
      message: message,
      submessage: submessage,
      type: _mapType(type),
    );
  }

  static LikeToastMessageType _mapType(LikeToastStyle type) {
    switch (type) {
      case LikeToastStyle.success:
        return LikeToastMessageType.success;
      case LikeToastStyle.info:
        return LikeToastMessageType.info;
      case LikeToastStyle.warning:
        return LikeToastMessageType.warning;
      case LikeToastStyle.error:
        return LikeToastMessageType.error;
    }
  }

  /// Displays a toast notification when data is served from L2/L3 cache while offline.
  static void notifyCacheUse(BuildContext context) {
    showToast(
      message: 'You are viewing offline data',
      type: LikeToastStyle.info,
      context: context,
    );
  }

  /// Displays a toast notification during SWR (Stale-While-Revalidate) background refreshes.
  static void notifySwrUse(BuildContext context) {
    showToast(
      message: 'Loading fresh data in background...',
      type: LikeToastStyle.info,
      context: context,
    );
  }
}
