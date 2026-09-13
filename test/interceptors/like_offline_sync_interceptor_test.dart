import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/src/interceptors/like_offline_sync_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mocks.dart';

void main() {
  late Box<dynamic> queue;
  late Dio dio;
  late MockHttpClientAdapter adapter;
  late LikeOfflineSyncInterceptor interceptor;
  late List<String> refreshNotifications;

  setUpAll(() async {
    setupMocks();
    await initTestHive();
  });

  setUp(() async {
    queue = await Hive.openBox<dynamic>('offline_interceptor_test');
    await queue.clear();
    await LikeConnectivityManager().reset();
    LikeConnectivityManager().debugSetStatus(internet: true, server: true);

    dio = Dio(BaseOptions(baseUrl: 'https://current.example/api/'));
    adapter = MockHttpClientAdapter();
    dio.httpClientAdapter = adapter;
    refreshNotifications = <String>[];
    interceptor = LikeOfflineSyncInterceptor(
      dio: dio,
      queueBox: queue,
      notifyRefresh: refreshNotifications.add,
    );
    dio.interceptors.add(interceptor);
  });

  tearDown(() async {
    dio.close(force: true);
    await queue.close();
    await Hive.deleteBoxFromDisk('offline_interceptor_test');
    await LikeConnectivityManager().reset();
  });

  test('queues only explicitly eligible mutation network failures', () async {
    when(() => adapter.fetch(any(), any(), any()))
        .thenAnswer((invocation) async {
      final options = invocation.positionalArguments.first as RequestOptions;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    });

    await expectLater(
      dio.post<void>(
        'clients',
        data: <String, Object>{'name': 'Queued client'},
        options: Options(extra: <String, Object>{'offlineSync': true}),
      ),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      dio.post<void>(
        'clients',
        options: Options(extra: <String, Object>{'offlineSync': false}),
      ),
      throwsA(isA<DioException>()),
    );
    await expectLater(
      dio.get<void>(
        'clients',
        options: Options(extra: <String, Object>{'offlineSync': true}),
      ),
      throwsA(isA<DioException>()),
    );

    expect(queue.length, 1);
    final task = Map<String, dynamic>.from(queue.values.single as Map);
    expect(task['origin'], 'https://current.example:443');
    expect(task['url'], 'https://current.example:443/api/clients');
    expect(task['method'], 'POST');
  });

  test('deduplicates equivalent durable mutations', () async {
    when(() => adapter.fetch(any(), any(), any()))
        .thenAnswer((invocation) async {
      final options = invocation.positionalArguments.first as RequestOptions;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
    });

    Future<void> queueRequest() async {
      try {
        await dio.post<void>(
          'clients',
          data: <String, Object>{'name': 'Same client'},
          options: Options(extra: <String, Object>{'offlineSync': true}),
        );
      } on DioException {
        // Expected: the caller is informed that its mutation was queued.
      }
    }

    await queueRequest();
    await queueRequest();

    expect(queue.length, 1);
  });

  test('replays through the persisted absolute origin and cannot requeue',
      () async {
    await queue.add(_task(
      origin: 'https://queued.example:443',
      path: '/api/v1/clients',
      url: 'https://queued.example:443/api/v1/clients',
    ));
    RequestOptions? replayOptions;
    when(() => adapter.fetch(any(), any(), any()))
        .thenAnswer((invocation) async {
      replayOptions = invocation.positionalArguments.first as RequestOptions;
      return ResponseBody.fromString('{}', 201, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      });
    });

    await interceptor.syncQueue(origin: 'https://queued.example');

    expect(replayOptions?.uri.origin, 'https://queued.example');
    expect(replayOptions?.uri.path, '/api/v1/clients');
    expect(replayOptions?.extra['isSyncRequest'], isTrue);
    expect(replayOptions?.extra['offlineSync'], isFalse);
    expect(queue, isEmpty);
  });

  test('deletes and rejects a queue entry whose replay URL changes origin',
      () async {
    final key = await queue.add(_task(
      origin: 'https://queued.example:443',
      path: '/api/v1/clients',
      url: 'https://attacker.example/api/v1/clients',
    ));

    await expectLater(
      interceptor.syncSingle(key),
      throwsA(isA<StateError>()),
    );
    expect(queue.get(key), isNull);
    verifyNever(() => adapter.fetch(any(), any(), any()));
  });

  test('coalesces equal drains and serializes different drain scopes',
      () async {
    await queue.add(_task(
      origin: 'https://one.example:443',
      path: '/one',
      url: 'https://one.example:443/one',
    ));
    await queue.add(_task(
      origin: 'https://two.example:443',
      path: '/two',
      url: 'https://two.example:443/two',
    ));

    var active = 0;
    var maximumActive = 0;
    final releases = <Completer<void>>[];
    when(() => adapter.fetch(any(), any(), any())).thenAnswer((_) async {
      active++;
      if (active > maximumActive) maximumActive = active;
      final release = Completer<void>();
      releases.add(release);
      await release.future;
      active--;
      return ResponseBody.fromString('{}', 200, headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      });
    });

    final first = interceptor.syncQueue(origin: 'https://one.example');
    final joined = interceptor.syncQueue(origin: 'https://one.example');
    final second = interceptor.syncQueue(origin: 'https://two.example');
    expect(identical(first, joined), isTrue);

    while (releases.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(releases.length, 1);
    releases.first.complete();
    while (releases.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(maximumActive, 1);
    releases[1].complete();

    await Future.wait<void>(<Future<void>>[first, joined, second]);
    expect(queue, isEmpty);
  });

  test('migrates a legacy entry without a persisted URL to its stored origin',
      () async {
    final legacy = _task(
      origin: 'https://legacy.example:443',
      path: '/api/v1/clients',
      url: 'unused',
    )..remove('url');
    await queue.add(legacy);
    RequestOptions? replayOptions;
    when(() => adapter.fetch(any(), any(), any()))
        .thenAnswer((invocation) async {
      replayOptions = invocation.positionalArguments.first as RequestOptions;
      return ResponseBody.fromString('{}', 200);
    });

    await interceptor.syncQueue(origin: 'https://legacy.example');

    expect(replayOptions?.uri.origin, 'https://legacy.example');
    expect(replayOptions?.uri.path, '/api/v1/clients');
    expect(queue, isEmpty);
  });

  test('terminal client errors delete durable work and remain observable',
      () async {
    await queue.add(_task(
      origin: 'https://queued.example:443',
      path: '/api/v1/clients',
      url: 'https://queued.example:443/api/v1/clients',
    ));
    when(() => adapter.fetch(any(), any(), any()))
        .thenAnswer((_) async => ResponseBody.fromString('{}', 422));

    await expectLater(
      interceptor.syncQueue(origin: 'https://queued.example'),
      throwsA(
        isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status code',
          422,
        ),
      ),
    );
    expect(queue, isEmpty);
  });

  test('retryable failures update attempts and next attempt time', () async {
    final before = DateTime.now();
    await queue.add(_task(
      origin: 'https://queued.example:443',
      path: '/api/v1/clients',
      url: 'https://queued.example:443/api/v1/clients',
    ));
    when(() => adapter.fetch(any(), any(), any()))
        .thenAnswer((_) async => ResponseBody.fromString('{}', 429));

    await expectLater(
      interceptor.syncQueue(origin: 'https://queued.example'),
      throwsA(isA<DioException>()),
    );

    final task = Map<String, dynamic>.from(queue.values.single as Map);
    expect(task['attempts'], 1);
    expect(DateTime.parse(task['nextAttemptAt'] as String).isAfter(before),
        isTrue);
    expect(task['lastFailure'], isNotNull);
  });

  test('skips exhausted and not-yet-due durable work', () async {
    final exhausted = _task(
      origin: 'https://queued.example:443',
      path: '/exhausted',
      url: 'https://queued.example:443/exhausted',
    )
      ..['attempts'] = 3
      ..['maxAttempts'] = 3;
    final delayed = _task(
      origin: 'https://queued.example:443',
      path: '/delayed',
      url: 'https://queued.example:443/delayed',
    )..['nextAttemptAt'] =
        DateTime.now().add(const Duration(hours: 1)).toIso8601String();
    await queue.addAll(<Map<String, dynamic>>[exhausted, delayed]);

    await interceptor.syncQueue(origin: 'https://queued.example');

    verifyNever(() => adapter.fetch(any(), any(), any()));
    expect(queue.length, 2);
  });

  test('refresh notification failure cannot fail acknowledged replay',
      () async {
    dio.interceptors.clear();
    interceptor = LikeOfflineSyncInterceptor(
      dio: dio,
      queueBox: queue,
      notifyRefresh: (_) => throw StateError('listener failed'),
    );
    dio.interceptors.add(interceptor);
    await queue.add(_task(
      origin: 'https://queued.example:443',
      path: '/api/v1/clients',
      url: 'https://queued.example:443/api/v1/clients',
    ));
    when(() => adapter.fetch(any(), any(), any()))
        .thenAnswer((_) async => ResponseBody.fromString('{}', 200));

    await interceptor.syncQueue(origin: 'https://queued.example');

    expect(queue, isEmpty);
  });

  test('manual cancellation keeps the durable entry pending', () async {
    await queue.add(_task(
      origin: 'https://queued.example:443',
      path: '/api/v1/clients',
      url: 'https://queued.example:443/api/v1/clients',
    ));
    final started = Completer<void>();
    when(() => adapter.fetch(any(), any(), any()))
        .thenAnswer((invocation) async {
      started.complete();
      final cancelFuture =
          invocation.positionalArguments[2] as Future<dynamic>?;
      await cancelFuture;
      throw DioException(
        requestOptions: invocation.positionalArguments.first as RequestOptions,
        type: DioExceptionType.cancel,
      );
    });

    final drain = interceptor.syncQueue(origin: 'https://queued.example');
    await started.future;
    interceptor.cancelSync(origin: 'https://queued.example');
    await drain;

    expect(queue.length, 1);
    final task = Map<String, dynamic>.from(queue.values.single as Map);
    expect(task['attempts'], 0);
  });
}

Map<String, dynamic> _task({
  required String origin,
  required String path,
  required String url,
}) {
  final now = DateTime.now().subtract(const Duration(seconds: 1));
  return <String, dynamic>{
    'version': LikeOfflineSyncInterceptor.queueSchemaVersion,
    'id': '$origin|$path',
    'origin': origin,
    'eligible': true,
    'path': path,
    'url': url,
    'method': 'POST',
    'data': <String, Object>{'name': 'Test'},
    'query': <String, Object>{},
    'headers': <String, Object>{},
    'contentType': Headers.jsonContentType,
    'createdAt': now.toIso8601String(),
    'timestamp': now.toIso8601String(),
    'attempts': 0,
    'maxAttempts': 3,
    'nextAttemptAt': now.toIso8601String(),
    'lastFailure': null,
  };
}
