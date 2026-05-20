import 'dart:async';
import 'package:like/src/client/like_client.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_logger.dart';

/// Orchestrates synchronization when connectivity is restored.
/// Bridge between [LikeConnectivityManager] and [LikeClient].
class LikeOfflineSyncManager {
  static final LikeOfflineSyncManager _instance =
      LikeOfflineSyncManager._internal();
  factory LikeOfflineSyncManager() => _instance;

  StreamSubscription? _connectivitySubscription;
  bool _isInitialized = false;

  LikeOfflineSyncManager._internal();

  /// Initializes the sync orchestrator.
  /// Should be called during app bootstrap after LikeClient is ready.
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;

    _connectivitySubscription?.cancel();
    _connectivitySubscription = LikeConnectivityManager().connectionChange
        .listen((isConnected) {
          if (isConnected) {
            _triggerSync();
          }
        });

    // Check initial state
    if (LikeConnectivityManager().hasConnection) {
      _triggerSync();
    }
  }

  void _triggerSync() {
    LikeLogger.log(
      level: LikeLogLevel.info,
      category: 'sync',
      message: 'Connectivity restored. Initiating sync orchestration...',
    );

    final client = LikeClient();
    client.syncOfflineData();
    client.triggerReconnectionSync();
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _isInitialized = false;
  }
}
