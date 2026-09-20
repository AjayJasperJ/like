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
              children: <Widget>[
                const Text('developer overlay'),
                child,
              ],
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

    testWidgets('applies toast and authentication configuration',
        (tester) async {
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
