import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/like.dart';

void main() {
  late Directory tempDirectory;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDirectory = Directory.systemTemp.createTempSync('like_root_test_');
    Hive.init(tempDirectory.path);
  });

  setUp(LikeConstants.reset);

  tearDown(LikeConstants.reset);

  tearDownAll(() async {
    await Hive.close();
    if (tempDirectory.existsSync()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  group('Like root widget', () {
    testWidgets('renders its child without a dev tool wrapper', (tester) async {
      await tester.pumpWidget(
        const Like(
          showConnectivityToasts: false,
          child: MaterialApp(home: Text('child')),
        ),
      );
      await tester.pump();

      expect(find.text('child'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wraps its child with devTool', (tester) async {
      await tester.pumpWidget(
        Like(
          showConnectivityToasts: false,
          devTool: (child) => Directionality(
            textDirection: TextDirection.ltr,
            child: Column(
              children: <Widget>[const Text('developer overlay'), child],
            ),
          ),
          child: const Text('child'),
        ),
      );
      await tester.pump();

      expect(find.text('developer overlay'), findsOneWidget);
      expect(find.text('child'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('applies toast and authentication configuration', (
      tester,
    ) async {
      Future<String?> getToken() async => 'token';
      Future<String?> refreshToken() async => 'refreshed';
      Future<String?> getApiKey() async => 'key';
      Future<void> onLogout({int? statusCode, bool force = false}) async {}
      final toastConfig = LikeToastConfig(
        connected: (_) {},
        disconnected: (_) {},
      );
      final authConfig = LikeAuthConfig(
        getToken: getToken,
        refreshToken: refreshToken,
        getApiKey: getApiKey,
        onLogout: onLogout,
      );

      await tester.pumpWidget(
        Like(
          showConnectivityToasts: false,
          toastConfig: toastConfig,
          authConfig: authConfig,
          child: const MaterialApp(home: Text('configured')),
        ),
      );
      await tester.pump();

      expect(find.text('configured'), findsOneWidget);
      expect(LikeConstants.current.toastConfig, same(toastConfig));
      expect(LikeConstants.current.authConfig, same(authConfig));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'slow hook deduplicates, rearms, isolates origins and disposes',
      (tester) async {
        final messages = <String>[];
        await tester.pumpWidget(
          Like(
            showConnectivityToasts: false,
            toastConfig: LikeToastConfig(slowInternet: messages.add),
            child: const MaterialApp(home: Scaffold()),
          ),
        );
        final monitor = LikeNetworkQualityMonitor.shared;
        final first = Uri.parse('https://slow-hook-one.example');
        final second = Uri.parse('https://slow-hook-two.example');
        void slow(Uri uri) {
          monitor.record(uri: uri, elapsed: const Duration(seconds: 3));
        }

        slow(first);
        await tester.pump();
        expect(messages, isEmpty);
        slow(first);
        slow(first);
        slow(second);
        slow(second);
        await tester.pump();
        expect(messages, [
          'Slow Internet Connection',
          'Slow Internet Connection',
        ]);
        expect(find.byType(SnackBar), findsNothing);
        monitor.record(uri: first, elapsed: const Duration(milliseconds: 10));
        slow(first);
        slow(first);
        await tester.pump();
        expect(messages, hasLength(3));
        await tester.pumpWidget(const SizedBox());
        monitor.record(uri: first, elapsed: const Duration(milliseconds: 10));
        slow(first);
        slow(first);
        await tester.pump();
        expect(messages, hasLength(3));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('slow notifications can be disabled independently', (
      tester,
    ) async {
      final messages = <String>[];
      await tester.pumpWidget(
        Like(
          showConnectivityToasts: false,
          showSlowInternetToasts: false,
          toastConfig: LikeToastConfig(slowInternet: messages.add),
          child: const MaterialApp(home: Scaffold()),
        ),
      );
      final uri = Uri.parse('https://disabled-slow-hook.example');
      for (var i = 0; i < 3; i++) {
        LikeNetworkQualityMonitor.shared.record(
          uri: uri,
          elapsed: const Duration(seconds: 3),
        );
      }
      await tester.pump();
      expect(messages, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('slow notifications use the default snackbar without a hook', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Like(showConnectivityToasts: false, child: SizedBox()),
          ),
        ),
      );
      final uri = Uri.parse('https://default-slow-hook.example');
      for (var i = 0; i < 2; i++) {
        LikeNetworkQualityMonitor.shared.record(
          uri: uri,
          elapsed: const Duration(seconds: 3),
        );
      }
      await tester.pump();
      expect(find.text('Slow Internet Connection'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposes safely after initialization', (tester) async {
      await tester.pumpWidget(
        const Like(
          showConnectivityToasts: false,
          child: MaterialApp(home: Text('mounted')),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(find.text('mounted'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
