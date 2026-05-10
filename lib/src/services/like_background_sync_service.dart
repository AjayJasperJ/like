import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_logger.dart';

const String kLikeBackgroundSyncTask = 'com.like.backgroundSyncEnabled';
const String kLikePeriodicSyncReminderTask = 'com.like.periodicSyncReminder';
const String kLikeCacheMaintenanceTask = 'com.like.cacheMaintenance';

/// Callback dispatcher for Workmanager background tasks.
/// Must be a top-level function.
@pragma('vm:entry-point')
void likeCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await Hive.initFlutter();

      // Open necessary boxes for background processing
      await Hive.openBox(LikeConstants.boxApiCache);
      await Hive.openBox(LikeConstants.boxOfflineQueue);
      await Hive.openBox(LikeConstants.boxCacheMetadata);
      await Hive.openBox(LikeConstants.boxEtags);

      await LikeLogger.init();

      if (task == kLikeCacheMaintenanceTask) {
        // Cache pruning logic would go here
        return true;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final bool isAppInForeground =
          prefs.getBool('isAppInForeground') ?? false;

      if (task == kLikeBackgroundSyncTask) {
        await LikeLogger.log(
          level: LikeLogLevel.info,
          category: 'background_sync',
          message:
              'Starting sync task: $task | isInForeground: $isAppInForeground',
        );

        // Sync logic is handled by the host application's client
        // Host apps should listen for this event or use LikeSyncManager
      } else if (task == kLikePeriodicSyncReminderTask) {
        final results = await Connectivity().checkConnectivity();
        final isOnline = results.any((r) => r != ConnectivityResult.none);

        if (!isOnline && !isAppInForeground) {
          final queueBox = Hive.box(LikeConstants.boxOfflineQueue);
          if (queueBox.isNotEmpty) {
            await LikeLogger.log(
              level: LikeLogLevel.info,
              category: 'background_sync',
              message:
                  'Periodic reminder triggered: ${queueBox.length} items pending offline.',
            );
            // Notification logic should be implemented by host app via LikeNotificationDelegate
          }
        }
      }

      return true;
    } catch (e, stack) {
      await LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'background_sync',
        message: 'Critical Error: $e',
        details: {'stack': stack.toString()},
      );
      return false;
    }
  });
}

/// Service to manage background tasks using Workmanager.
/// Matches enterprise's BackgroundSyncService parity.
class LikeBackgroundSyncService {
  static final LikeBackgroundSyncService _instance =
      LikeBackgroundSyncService._internal();
  factory LikeBackgroundSyncService() => _instance;
  LikeBackgroundSyncService._internal();

  /// Initializes background task registration.
  Future<void> init() async {
    if (Platform.isLinux || !LikeConstants.backgroundSyncEnabled) {
      return;
    }

    await Workmanager().initialize(likeCallbackDispatcher);

    // Register periodic sync reminder (6 hours)
    await Workmanager().registerPeriodicTask(
      'like_periodic_sync_reminder',
      kLikePeriodicSyncReminderTask,
      frequency: const Duration(hours: 6),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        requiresBatteryNotLow: true,
        requiresDeviceIdle: true,
      ),
    );

    // Register periodic cache maintenance (12 hours)
    await Workmanager().registerPeriodicTask(
      'like_periodic_cache_maintenance',
      kLikeCacheMaintenanceTask,
      frequency: const Duration(hours: 12),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        requiresBatteryNotLow: true,
        requiresDeviceIdle: true,
      ),
    );
  }

  /// Schedules a one-off sync task when connection is restored.
  void scheduleSyncTask() {
    if (Platform.isLinux || !LikeConstants.backgroundSyncEnabled) return;
    Workmanager().registerOneOffTask(
      'like_bg_sync_unique',
      kLikeBackgroundSyncTask,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 10),
    );
  }
}
