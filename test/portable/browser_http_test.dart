@TestOn('browser')
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/testing.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  const base = 'http://127.0.0.1:8765';
  late Dio dio;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: base));
  });
  tearDown(() => dio.close(force: true));

  test('browser HTTP adapter handles CORS preflight and JSON bodies', () async {
    final response = await dio.post<dynamic>('/ok',
        data: {'value': 1},
        options: Options(
            headers: {'x-test': 'fixture', 'Authorization': 'Bearer fixture'}));
    expect(response.data['ok'], isTrue);
  });

  test('browser HTTP errors retain status and payload', () async {
    await expectLater(
        dio.get<dynamic>('/error'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 503)));
  });

  test('browser cancellation aborts a slow request', () async {
    final token = CancelToken();
    final future = dio.get<dynamic>('/slow', cancelToken: token);
    token.cancel('test cancellation');
    await expectLater(
        future,
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
  });

  test('browser receive timeout is observable', () async {
    await expectLater(
        dio.get<dynamic>('/slow',
            options: Options(receiveTimeout: const Duration(milliseconds: 50))),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.receiveTimeout)));
  });

  test('browser Hive cache and ETags revalidate without cross-origin leakage',
      () async {
    LikeConstants.apply(LikeConfig(projectName: 'browser-etag-fixture'));
    await Hive.initFlutter('browser-etag-fixture');
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
    await Hive.openBox(LikeConstants.boxEtags);
    addTearDown(() async {
      await Hive.deleteFromDisk();
      LikeConstants.reset();
    });
    dio.interceptors.addAll([LikeEtagInterceptor(), LikeCacheInterceptor()]);
    final first = await dio.get<dynamic>('/ok');
    expect(first.data['ok'], isTrue);
    expect(LikeService.getEtag('$base/ok'), '"fixture-v1"');
    expect(LikeService.getEtag('http://localhost:8765/ok'), isNull);
    final second = await dio.get<dynamic>('/ok');
    expect(second.extra['isFrom304'], isTrue);
    expect(second.data['ok'], isTrue);
    final other = await dio.get<dynamic>('http://localhost:8765/ok');
    expect(other.extra['isFrom304'], isNot(isTrue));
  });

  test('LIKE uses the real browser adapter and leaves application data intact',
      () async {
    LikeConstants.apply(LikeConfig(
        projectName: 'portable-tests',
        disableFileLogging: true,
        silentConsole: true));
    final client = LikeClient(baseUrl: base, dio: dio);
    addTearDown(() {
      client.dispose();
      LikeConstants.reset();
    });
    final result = await client.get('/ok', disableCache: true);
    expect(result.isSuccess, isTrue);
    expect(result.data!.data['token'], 'fixture-secret');
  });
}
