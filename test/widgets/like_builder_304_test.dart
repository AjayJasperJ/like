import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/like.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

import '../mocks/mocks.dart';

class _Profile {
  const _Profile(this.name);

  final String name;
}

class _NotModifiedAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requests.length == 1) {
      return ResponseBody.fromString(
        jsonEncode(<String, Object?>{'name': 'production user'}),
        200,
        headers: <String, List<String>>{
          Headers.contentTypeHeader: <String>['application/json'],
          'etag': <String>['"profile-v1"'],
        },
      );
    }

    return ResponseBody.fromString('', 304);
  }

  @override
  void close({bool force = false}) {}
}

class _ProfileController {
  _ProfileController(this.client);

  final LikeClient client;
  final LikeEngine engine = LikeEngine();
  final LikeNotifierState<_Profile> state = LikeNotifierState<_Profile>();
  bool capitalizeModel = false;

  Future<void> load() {
    return engine.fetch<_Profile>(
      state: state,
      action: () async {
        final result = await client.get('/profile').mapSync<_Profile>((json) {
          final map = json as Map<String, dynamic>;
          final rawName = map['name'] as String;
          return _Profile(capitalizeModel ? rawName.toUpperCase() : rawName);
        });
        return result.toStateResponse();
      },
    );
  }

  void dispose() {
    state.dispose();
    engine.dispose();
    client.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestHive();
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
    await Hive.openBox(LikeConstants.boxEtags);
    await Hive.openBox(LikeConstants.boxOfflineQueue);
  });

  setUp(() async {
    LikeConstants.apply(
      LikeConstants.current.copyWith(offlineSyncEnabled: false),
    );
    await LikeService.cacheBox.clear();
    await LikeService.etagBox.clear();
    await Hive.box(LikeConstants.boxCacheMetadata).clear();
    await LikeConnectivityManager().reset();
    LikeConnectivityManager().debugSetStatus(internet: true, server: true);
  });

  tearDown(() async {
    LikeConstants.reset();
    await LikeConnectivityManager().reset();
  });

  testWidgets(
    '304 injects cached payload, remaps model, and rebuilds LikeBuilder',
    (tester) async {
      final adapter = _NotModifiedAdapter();
      final client = LikeClient.scoped(
        const LikeClientConfig(baseUrl: 'https://api.example.com'),
      );
      client.dio.httpClientAdapter = adapter;
      final controller = _ProfileController(client);
      addTearDown(controller.dispose);

      var successBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LikeBuilder<_Profile>(
              observe: () => controller.state,
              onSuccess: (profile, _, _) {
                successBuilds++;
                return Text(profile.name);
              },
            ),
          ),
        ),
      );

      await tester.runAsync(
        () => controller.load().timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw StateError('initial 200 request did not complete'),
        ),
      );
      expect(controller.state.value.data?.name, 'production user');
      await tester.pumpAndSettle();

      expect(find.text('production user'), findsOneWidget);
      expect(controller.state.value.isFromCache, isFalse);
      expect(controller.state.value.isFrom304, isFalse);
      expect(successBuilds, 1);

      // Simulates shipping updated model parsing while the server correctly
      // responds 304. The cached raw JSON must still pass through the mapper.
      controller.capitalizeModel = true;
      await tester.runAsync(
        () => controller.load().timeout(
          const Duration(seconds: 5),
          onTimeout: () =>
              throw StateError('follow-up 304 request did not complete'),
        ),
      );
      await tester.pumpAndSettle();

      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.headers['If-None-Match'], '"profile-v1"');
      expect(find.text('PRODUCTION USER'), findsOneWidget);
      expect(controller.state.value.data?.name, 'PRODUCTION USER');
      expect(controller.state.value.isFromCache, isTrue);
      expect(controller.state.value.isFrom304, isTrue);
      expect(successBuilds, 2);
    },
  );
}
