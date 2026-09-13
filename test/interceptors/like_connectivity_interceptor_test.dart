import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/src/dio_mixin.dart'
    show InterceptorResultType, InterceptorState;
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:universal_io/io.dart';

class _AlwaysFailingAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    throw DioException.connectionTimeout(
      timeout: const Duration(milliseconds: 1),
      requestOptions: options,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = LikeConnectivityManager();
  final interceptor = LikeConnectivityInterceptor();
  var serverChecks = 0;

  setUp(() async {
    LikeConstants.reset();
    await manager.reset();
    serverChecks = 0;
    manager.debugConfigure(
      interfaceCheck: () async => <ConnectivityResult>[ConnectivityResult.wifi],
      internetCheck: (_, __) async => true,
      serverCheck: (_, __, ___) async {
        serverChecks++;
        return false;
      },
      isWeb: false,
    );
  });

  tearDown(() async {
    LikeConstants.reset();
    await manager.reset();
  });

  Future<DioException> observe(DioException error) async {
    final handler = ErrorInterceptorHandler();
    interceptor.onError(error, handler);
    try {
      // Dio exposes handler completion only through this protected test seam.
      // ignore: invalid_use_of_protected_member
      await handler.future;
      fail('Expected the handler to forward an error.');
    } on InterceptorState<DioException> catch (state) {
      expect(state.type, InterceptorResultType.next);
      return state.data;
    }
  }

  DioException errorOf(
    DioExceptionType type, {
    Object? error,
    Response<dynamic>? response,
  }) {
    return DioException(
      requestOptions: RequestOptions(
        path: '/resource',
        baseUrl: 'https://api.example.com',
      ),
      type: type,
      error: error,
      response: response,
    );
  }

  test('eligible terminal failure is forwarded immediately with same identity',
      () async {
    final probe = Completer<bool?>();
    manager.debugConfigure(
      interfaceCheck: () async => <ConnectivityResult>[ConnectivityResult.wifi],
      internetCheck: (_, __) async => true,
      serverCheck: (_, __, ___) {
        serverChecks++;
        return probe.future;
      },
      isWeb: false,
    );
    final original = errorOf(DioExceptionType.connectionError);

    final forwarded =
        await observe(original).timeout(const Duration(seconds: 1));
    expect(identical(forwarded, original), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(serverChecks, 1);
    expect(probe.isCompleted, isFalse);
    probe.complete(false);
  });

  test('eligible timeout and socket-backed unknown failures trigger checks',
      () async {
    final errors = <DioException>[
      errorOf(DioExceptionType.connectionTimeout),
      errorOf(DioExceptionType.sendTimeout),
      errorOf(DioExceptionType.receiveTimeout),
      errorOf(
        DioExceptionType.unknown,
        error: const SocketException('socket failed'),
      ),
    ];

    for (var index = 0; index < errors.length; index++) {
      // Different origins avoid the intentional per-origin cooldown.
      errors[index].requestOptions.baseUrl = 'https://api$index.example.com';
      await observe(errors[index]);
    }
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(serverChecks, errors.length);
  });

  test('retry chain causes only one terminal automatic check', () async {
    LikeConstants.apply(
      LikeConfig(
        projectName: 'test',
        maxAutoRetries: 1,
        retryDelays: const <int>[0],
      ),
    );
    final dio = Dio();
    final adapter = _AlwaysFailingAdapter();
    dio.httpClientAdapter = adapter;
    dio.interceptors.addAll(<Interceptor>[
      LikeConnectivityInterceptor(),
      LikeRetryInterceptor(dio: dio),
    ]);

    await expectLater(
      dio.get<void>('https://retry.example/resource'),
      throwsA(isA<DioException>()),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(adapter.calls, 2);
    expect(serverChecks, 1);
    dio.close(force: true);
  });

  test('HTTP response is reachability evidence and never triggers a check',
      () async {
    manager.markServerUnavailable(serverUrl: 'https://api.example.com');
    final options = RequestOptions(
      path: '/resource',
      baseUrl: 'https://api.example.com',
    );
    final original = DioException(
      requestOptions: options,
      type: DioExceptionType.badResponse,
      response: Response<dynamic>(requestOptions: options, statusCode: 503),
    );

    expect(identical(await observe(original), original), isTrue);
    expect(serverChecks, 0);
    expect(manager.serverAvailabilityFor('https://api.example.com'), isTrue);
  });

  test(
      'cancellation, local unknown, bad certificate, and queued result skip checks',
      () async {
    final skipped = <DioException>[
      errorOf(DioExceptionType.cancel),
      errorOf(DioExceptionType.badCertificate),
      errorOf(DioExceptionType.unknown, error: const FormatException('bad')),
      errorOf(DioExceptionType.unknown, error: 'OFFLINE_QUEUED'),
    ];

    for (final error in skipped) {
      expect(identical(await observe(error), error), isTrue);
    }
    await Future<void>.delayed(Duration.zero);
    expect(serverChecks, 0);
  });

  test('successful response marks only its own origin available', () async {
    manager.markServerUnavailable(serverUrl: 'https://primary.example');
    manager.markServerUnavailable(serverUrl: 'https://scoped.example');
    final options = RequestOptions(
      path: '/ok',
      baseUrl: 'https://scoped.example',
    );
    final handler = ResponseInterceptorHandler();
    final response =
        Response<dynamic>(requestOptions: options, statusCode: 204);

    interceptor.onResponse(response, handler);
    // Dio exposes handler completion only through this protected test seam.
    // ignore: invalid_use_of_protected_member
    final state = await handler.future;
    expect(state.type, InterceptorResultType.next);
    expect(state.data, same(response));
    expect(manager.serverAvailabilityFor('https://scoped.example'), isTrue);
    expect(manager.serverAvailabilityFor('https://primary.example'), isFalse);
  });
}
