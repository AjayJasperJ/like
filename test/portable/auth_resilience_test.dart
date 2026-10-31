import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

class _AuthAdapter implements HttpClientAdapter {
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<dynamic>? cancel) async {
    calls++;
    return ResponseBody.fromString('{}', options.headers['Authorization'] == 'Bearer fresh' ? 200 : 401);
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() => LikeConstants.apply(LikeConfig(projectName: 'auth-fixture', disableFileLogging: true)));
  tearDown(LikeConstants.reset);

  test('concurrent unauthorized requests join one refresh and both settle', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://auth.example'))..httpClientAdapter = _AuthAdapter();
    var refreshes = 0;
    dio.interceptors.add(LikeAuthInterceptor(dio: dio, authConfig: LikeAuthConfig(
      getToken: () => 'old', refreshToken: () async {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return 'fresh';
      })));
    final results = await Future.wait([dio.get<dynamic>('/one'), dio.get<dynamic>('/two')])
        .timeout(const Duration(seconds: 2));
    expect(results.every((result) => result.statusCode == 200), isTrue);
    expect(refreshes, 1);
    dio.close();
  });

  test('throwing logout and API-key hooks cannot hang the request', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://auth.example'))..httpClientAdapter = _AuthAdapter();
    dio.interceptors.add(LikeAuthInterceptor(dio: dio, authConfig: LikeAuthConfig(
      getToken: () => 'old', refreshToken: () => null,
      onLogout: ({int? statusCode, bool force = false}) => throw StateError('fixture'))));
    await expectLater(dio.get<dynamic>('/logout').timeout(const Duration(seconds: 2)),
      throwsA(isA<DioException>()));
    dio.interceptors.clear();
    dio.interceptors.add(LikeAuthInterceptor(dio: dio, authConfig: LikeAuthConfig(
      getToken: () => 'old', refreshToken: () => 'fresh',
      getApiKey: () => throw StateError('fixture'))));
    await expectLater(dio.get<dynamic>('/key').timeout(const Duration(seconds: 2)),
      throwsA(isA<DioException>()));
    dio.close();
  });
}
