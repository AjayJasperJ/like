import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    LikeConstants.apply(
      LikeConfig(
        projectName: 'auth-config-test',
        offlineSyncEnabled: false,
      ),
    );
    await LikeConnectivityManager().reset();
    LikeConnectivityManager().debugSetStatus(internet: true, server: true);
    LikeAuthInterceptor.getToken = null;
    LikeAuthInterceptor.refreshToken = null;
    LikeAuthInterceptor.onLogout = null;
    LikeAuthInterceptor.getApiKey = null;
  });

  tearDown(() async {
    LikeConstants.reset();
    await LikeConnectivityManager().reset();
  });

  group('Multi-Client Auth Isolation Tests', () {
    test(
        'Client A and Client B use separate token getters without interference',
        () async {
      final clientA = LikeClient.scoped(
        LikeClientConfig(
          baseUrl: 'https://api-a.example.com',
          authConfig: LikeAuthConfig(
            getToken: () async => 'jwt_token_A',
          ),
        ),
      );

      final clientB = LikeClient.scoped(
        LikeClientConfig(
          baseUrl: 'https://api-b.example.com',
          authConfig: LikeAuthConfig(
            getToken: () async => 'jwt_token_B',
          ),
        ),
      );

      final adapterA = _MockAdapter((options) {
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {'header': options.headers['Authorization']},
        );
      });

      final adapterB = _MockAdapter((options) {
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {'header': options.headers['Authorization']},
        );
      });

      clientA.dio.httpClientAdapter = adapterA;
      clientB.dio.httpClientAdapter = adapterB;

      final resA = await clientA.get('/profile', withAuth: true);
      final resB = await clientB.get('/profile', withAuth: true);

      expect(((resA.data?.data as Map)['data'] as Map)['header'],
          equals('Bearer jwt_token_A'));
      expect(((resB.data?.data as Map)['data'] as Map)['header'],
          equals('Bearer jwt_token_B'));
    });

    test(
        'Client A and Client B handle simultaneous 401 token refresh in isolation',
        () async {
      int refreshCountA = 0;
      int refreshCountB = 0;

      final clientA = LikeClient.scoped(
        LikeClientConfig(
          baseUrl: 'https://api-a.example.com',
          authConfig: LikeAuthConfig(
            getToken: () async => 'expired_token_A',
            refreshToken: () async {
              refreshCountA++;
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return 'new_token_A';
            },
          ),
        ),
      );

      final clientB = LikeClient.scoped(
        LikeClientConfig(
          baseUrl: 'https://api-b.example.com',
          authConfig: LikeAuthConfig(
            getToken: () async => 'expired_token_B',
            refreshToken: () async {
              refreshCountB++;
              await Future<void>.delayed(const Duration(milliseconds: 50));
              return 'new_token_B';
            },
          ),
        ),
      );

      clientA.dio.httpClientAdapter = _MockAdapter((options) {
        if (options.headers['Authorization'] == 'Bearer new_token_A') {
          return Response(
              requestOptions: options, statusCode: 200, data: 'OK_A');
        }
        return Response(
            requestOptions: options, statusCode: 401, data: 'Unauthorized');
      });

      clientB.dio.httpClientAdapter = _MockAdapter((options) {
        if (options.headers['Authorization'] == 'Bearer new_token_B') {
          return Response(
              requestOptions: options, statusCode: 200, data: 'OK_B');
        }
        return Response(
            requestOptions: options, statusCode: 401, data: 'Unauthorized');
      });

      final results = await Future.wait([
        clientA.get('/resource', withAuth: true),
        clientB.get('/resource', withAuth: true),
      ]);

      expect((results[0].data?.data as Map)['data'], equals('OK_A'));
      expect((results[1].data?.data as Map)['data'], equals('OK_B'));
      expect(refreshCountA, equals(1));
      expect(refreshCountB, equals(1));
    });

    test('3-Tier fallback hierarchy prefers scoped > global > static',
        () async {
      LikeAuthInterceptor.getToken = () => 'static_token';

      LikeConstants.apply(
        LikeConfig(
          projectName: 'test',
          offlineSyncEnabled: false,
          authConfig: LikeAuthConfig(
            getToken: () => 'global_token',
          ),
        ),
      );

      final globalClient = LikeClient.scoped(const LikeClientConfig());
      final scopedClient = LikeClient.scoped(
        LikeClientConfig(
          authConfig: LikeAuthConfig(
            getToken: () => 'scoped_token',
          ),
        ),
      );

      globalClient.dio.httpClientAdapter = _MockAdapter((options) {
        return Response(
            requestOptions: options,
            statusCode: 200,
            data: options.headers['Authorization']);
      });

      scopedClient.dio.httpClientAdapter = _MockAdapter((options) {
        return Response(
            requestOptions: options,
            statusCode: 200,
            data: options.headers['Authorization']);
      });

      final resGlobal = await globalClient.get('/test', withAuth: true);
      final resScoped = await scopedClient.get('/test', withAuth: true);

      expect(
          (resGlobal.data?.data as Map)['data'], equals('Bearer global_token'));
      expect(
          (resScoped.data?.data as Map)['data'], equals('Bearer scoped_token'));
    });
  });
}

class _MockAdapter implements HttpClientAdapter {
  final Response Function(RequestOptions options) handler;
  _MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final res = handler(options);
    final String jsonPayload = jsonEncode({
      'status': (res.statusCode ?? 200) < 400 ? 'success' : 'error',
      'data': res.data,
    });

    return ResponseBody.fromString(
      jsonPayload,
      res.statusCode ?? 200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
