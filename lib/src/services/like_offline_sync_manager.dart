import 'dart:async';
import 'package:like/src/client/like_client.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/models/like_connectivity_transition.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_logger.dart';

/// Orchestrates synchronization when connectivity is restored.
/// Bridge between [LikeConnectivityManager] and [LikeClient].
class LikeOfflineSyncManager {
  static final LikeOfflineSyncManager _instance =
      LikeOfflineSyncManager._internal();
  factory LikeOfflineSyncManager() => _instance;

  StreamSubscription<LikeConnectivityTransition>? _connectivitySubscription;
  bool _isInitialized = false;

  LikeOfflineSyncManager._internal();

  /// Initializes the sync orchestrator.
  /// Should be called during app bootstrap after LikeClient is ready.
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    _connectivitySubscription?.cancel();
    _connectivitySubscription = LikeConnectivityManager()
        .originRestorations
        .listen((event) => _triggerSync(event.origin));

    // Preserve the existing background-sync default for startup drains. Unlike
    // restoration drains, this manually scans all currently eligible origins.
    if (LikeConstants.backgroundSyncEnabled &&
        LikeConnectivityManager().hasConnection) {
      _triggerSync(null);
    }
  }

  void _triggerSync(String? origin) {
    if (!LikeConstants.backgroundSyncEnabled) return;
    LikeLogger.log(
      level: LikeLogLevel.info,
      category: 'sync',
      message: origin == null
          ? 'Initiating eligible durable sync.'
          : 'Origin restored. Initiating matching durable sync: $origin',
    );

    LikeClient().triggerReconnectionSync();

    unawaited(LikeClient().syncOfflineData(origin: origin).catchError((error) {
      LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'sync',
        message: 'Durable sync failed: $error',
      );
    }));
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _isInitialized = false;
  }
}
