import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

class _SessionAdapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body,
      Future<dynamic>? cancel) async {
    calls++;
    return ResponseBody.fromString('{"call":$calls}', 200,
        headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  test('session keys separate accounts and environments without exposing IDs', () {
    const a = LikeSessionScope(accountId: 'account-a');
    const b = LikeSessionScope(accountId: 'account-b');
    const staging = LikeSessionScope(accountId: 'account-a', environment: 'staging');
    expect(a.key, isNot(b.key));
    expect(a.key, isNot(staging.key));
    expect(a.key, isNot(contains('account-a')));
    final options = RequestOptions(path: 'https://api.example/items');
    options.extra[LikeSessionIdentity.scopeKey] = a.key;
    final first = LikeSessionIdentity.forRequest(options);
    options.extra[LikeSessionIdentity.scopeKey] = b.key;
    expect(LikeSessionIdentity.forRequest(options), isNot(first));
  });

  test('switching account clears L1 and never reuses another account result', () async {
    final adapter = _SessionAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = adapter;
    final client = LikeClient(dio: dio,
      sessionScope: const LikeSessionScope(accountId: 'a'));
    addTearDown(client.dispose);
    final first = await client.get('/items', sessionStale: true);
    client.setSessionScope(const LikeSessionScope(accountId: 'b'));
    final second = await client.get('/items', sessionStale: true);
    expect(first.data!.data['call'], 1);
    expect(second.data!.data['call'], 2);
    expect(adapter.calls, 2);
  });

  test('stale request is cancelled before credentials or adapter access', () async {
    var scope = const LikeSessionScope(accountId: 'a');
    final adapter = _SessionAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = adapter;
    dio.interceptors.add(LikeSessionInterceptor(() => scope));
    final captured = scope.key;
    scope = const LikeSessionScope(accountId: 'b');
    await expectLater(dio.get<dynamic>('/items', options: Options(extra: {
      LikeSessionIdentity.scopeKey: captured,
    })), throwsA(isA<DioException>()
      .having((e) => e.type, 'type', DioExceptionType.cancel)));
    expect(adapter.calls, 0);
    dio.close();
  });

  test('unscoped authenticated requests cannot persist private data', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example'))
      ..httpClientAdapter = _SessionAdapter();
    dio.interceptors.add(LikeSessionInterceptor(() => const LikeSessionScope()));
    final response = await dio.get<dynamic>('/items', options: Options(extra: {
      'withAuth': true, 'offlineSync': true,
    }));
    expect(response.requestOptions.extra['disableCache'], isTrue);
    expect(response.requestOptions.extra['offlineSync'], isFalse);
    dio.close();
  });
}
