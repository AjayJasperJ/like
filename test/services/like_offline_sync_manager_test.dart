import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/like.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_offline_sync_manager.dart';
import '../mocks/mocks.dart';

void main() {
  setUpAll(() async {
    setupMocks();
    await initTestHive();
  });

  group('LikeOfflineSyncManager', () {
    late LikeConnectivityManager connectivityManager;
    late LikeOfflineSyncManager syncManager;

    setUp(() async {
      await Hive.openBox(LikeConstants.boxApiCache);
      await Hive.openBox(LikeConstants.boxCacheMetadata);
      await Hive.openBox(LikeConstants.boxEtags);
      await Hive.openBox(LikeConstants.boxOfflineQueue);

      LikeClient.reset();
      LikeClient(baseUrl: 'https://test-api.com');
      connectivityManager = LikeConnectivityManager();
      syncManager = LikeOfflineSyncManager();
    });

    tearDown(() async {
      syncManager.dispose();
      LikeClient().dispose();
      await Hive.deleteFromDisk();
    });

    test('should trigger sync immediately on init if online', () async {
      // Set connection status to online
      connectivityManager.debugSetStatus(internet: true, server: true);

      final streamFuture = LikeClient().refreshStream.first;

      // Initialize
      syncManager.init();

      final refreshVal = await streamFuture;
      expect(refreshVal, equals('reconnected'));
    });

    test('should trigger sync when connection changes from offline to online', () async {
      // Start offline (internet true, server false -> hasConnection false)
      connectivityManager.debugSetStatus(internet: true, server: false);

      // Initialize
      syncManager.init();

      final streamFuture = LikeClient().refreshStream.first;

      // Bring connection back online (server becomes available)
      connectivityManager.markServerAvailable();

      final refreshVal = await streamFuture;
      expect(refreshVal, equals('reconnected'));
    });

    test('should not trigger sync after dispose', () async {
      connectivityManager.debugSetStatus(internet: false, server: false);
      syncManager.init();
      syncManager.dispose();

      bool triggered = false;
      final subscription = LikeClient().refreshStream.listen((event) {
        triggered = true;
      });

      // Bring connection back online
      connectivityManager.debugSetStatus(internet: true, server: true);
      connectivityManager.markServerAvailable();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(triggered, isFalse);
      await subscription.cancel();
    });
  });
}
