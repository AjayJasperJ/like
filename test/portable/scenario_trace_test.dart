import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/testing.dart';

class _NeverNetwork implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<dynamic>? cancel) =>
      throw StateError('Scenario reached the real network');
  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    LikeConstants.apply(LikeConfig(projectName: 'scenario-fixture', mockEnabled: true,
      disableFileLogging: true, silentConsole: true));
    MockController().reset();
    LikeConnectivityManager().debugSetStatus(internet: true, server: true);
  });
  tearDown(() async { LikeConstants.reset(); MockController().reset(); await LikeConnectivityManager().reset(); });

  test('a persisted-style 429 scenario recovers and emits payload-free diagnostics', () async {
    MockController().rules.value = [
      MockRule(id: 'limit', pathPattern: '/items', method: 'GET', maxUses: 1,
        statusCode: 429, responseHeaders: {'retry-after': '0'}, responseBody: '{}'),
      MockRule(id: 'success', pathPattern: '/items', method: 'GET',
        responseBody: '{"token":"fixture-private","count":1}'),
    ];
    final dio = Dio(BaseOptions(baseUrl: 'https://scenario.example'))..httpClientAdapter = _NeverNetwork();
    dio.interceptors.addAll([LikeTraceCaptureInterceptor(), LikeMockInterceptor(),
      LikeAuthInterceptor(dio: dio, retryPolicy: LikeRetryPolicy(random: () => 0))]);
    final client = LikeClient(dio: dio);
    addTearDown(client.dispose);
    final trace = LikeDiagnostics.shared.stream.firstWhere((event) => event.phase == LikeTracePhase.completed);
    final result = await client.get('/items?private=query-secret', disableCache: true);
    expect(result.data!.data['token'], 'fixture-private');
    final event = await trace;
    expect(event.source, LikeResponseSource.mocked);
    expect(event.rateLimitRetries, 1);
    expect(jsonEncode(event.toLog()), isNot(contains('fixture-private')));
    expect(jsonEncode(event.toLog()), isNot(contains('query-secret')));
  });

  test('safe scenario exports strip credential matchers and response secrets', () {
    final scenario = LikeMockScenario(name: 'Fixture', rules: [MockRule(id: 'fixture',
      pathPattern: '/items?token=private', method: 'GET', headersPattern: 'private-header',
      responseBody: '{"token":"private-body"}', responseHeaders: {'Authorization': 'private-header'})]);
    final encoded = scenario.exportSafe();
    expect(encoded, isNot(contains('private-header')));
    expect(encoded, isNot(contains('private-body')));
    expect(encoded, isNot(contains('token=private')));
    final restored = LikeMockScenario.fromJson(encoded);
    expect(restored.rules.single.statusCode, 200);
  });

  test('synthetic transport failures and cancellation never reach the adapter', () async {
    MockController().rules.value = [MockRule(id: 'offline', pathPattern: '/', method: 'GET',
      failure: LikeMockFailure.offline, responseBody: '{}')];
    final dio = Dio(BaseOptions(baseUrl: 'https://scenario.example'))..httpClientAdapter = _NeverNetwork();
    dio.interceptors.add(LikeMockInterceptor());
    await expectLater(dio.get<dynamic>('/offline'), throwsA(isA<DioException>()
      .having((error) => error.type, 'type', DioExceptionType.connectionError)));
    MockController().rules.value = [MockRule(id: 'slow', pathPattern: '/', method: 'GET',
      delayMs: 1000, responseBody: '{}')];
    final token = CancelToken();
    final request = dio.get<dynamic>('/slow', cancelToken: token);
    token.cancel('fixture');
    await expectLater(request, throwsA(isA<DioException>()
      .having((error) => error.type, 'type', DioExceptionType.cancel)));
    dio.close();
  });
}
