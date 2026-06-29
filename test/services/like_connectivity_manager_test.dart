import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
  final List<MethodCall> log = <MethodCall>[];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      if (methodCall.method == 'check') {
        return <Object?>['none']; // returns no connectivity
      }
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  setUp(() {
    log.clear();
  });

  group('LikeConnectivityManager', () {
    test('singleton returns the same instance', () {
      final manager1 = LikeConnectivityManager();
      final manager2 = LikeConnectivityManager();
      expect(identical(manager1, manager2), isTrue);
    });

    test('initial values and manual status overrides', () {
      final manager = LikeConnectivityManager();

      // Check initial default getters
      expect(manager.isInternetConnectedListenable, isNotNull);
      expect(manager.isServerAvailableListenable, isNotNull);
      expect(manager.connectionChange, isNotNull);
      expect(manager.statusStream, isNotNull);

      // Verify manual override
      manager.debugSetStatus(internet: false, server: false);
      expect(manager.isInternetConnected, isFalse);
      expect(manager.isServerAvailable, isFalse);
      expect(manager.hasConnection, isFalse);
      expect(manager.isOnline, isFalse);

      manager.debugSetStatus(internet: true, server: false);
      expect(manager.isInternetConnected, isTrue);
      expect(manager.isServerAvailable, isFalse);
      expect(manager.hasConnection, isFalse);

      manager.debugSetStatus(internet: true, server: true);
      expect(manager.isInternetConnected, isTrue);
      expect(manager.isServerAvailable, isTrue);
      expect(manager.hasConnection, isTrue);
      expect(manager.isOnline, isTrue);
    });

    test('markServerAvailable and markServerUnavailable work correctly',
        () async {
      final manager = LikeConnectivityManager();
      manager.debugSetStatus(internet: true, server: true);

      // Verify stream emits false when server goes down
      final streamFuture = manager.connectionChange.first;
      manager.markServerUnavailable();
      expect(manager.isServerAvailable, isFalse);
      expect(manager.hasConnection, isFalse);

      final bool streamValue = await streamFuture;
      expect(streamValue, isFalse);

      // Verify stream emits true when server goes up
      final streamFuture2 = manager.connectionChange.first;
      manager.markServerAvailable();
      expect(manager.isServerAvailable, isTrue);
      expect(manager.hasConnection, isTrue);

      final bool streamValue2 = await streamFuture2;
      expect(streamValue2, isTrue);
    });

    test('init and forceCheck process channel responses', () async {
      final manager = LikeConnectivityManager();

      // Perform init
      await manager.init(serverUrl: 'https://test-server.com');
      expect(log.length, greaterThanOrEqualTo(1));
      expect(log[0].method, equals('check'));

      // Since the mock channel returns 'none', isInternetConnected should be false
      expect(manager.isInternetConnected, isFalse);
      expect(manager.isServerAvailable, isFalse);

      // Test forceCheck
      log.clear();
      await manager.forceCheck();
      expect(log.length, equals(1));
      expect(log[0].method, equals('check'));
      expect(manager.isInternetConnected, isFalse);
    });

    test('dispose shuts down listeners and controller', () {
      final manager = LikeConnectivityManager();
      // Verify dispose can be called without crashing
      manager.dispose();
    });
  });
}
