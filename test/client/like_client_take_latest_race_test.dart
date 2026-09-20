import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:like/src/interceptors/like_connectivity_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

class _ControlledAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = <RequestOptions>[];
  final List<Completer<ResponseBody>> responses = <Completer<ResponseBody>>[];
  final StreamController<int> _started = StreamController<int>.broadcast();

  Future<void> waitForExecution(int count) async {
    if (requests.length >= count) return;
    await _started.stream.firstWhere((started) => started >= count);
  }

  void complete(int index, String body) {
    responses[index].complete(
      ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
      ),
    );
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    final response = Completer<ResponseBody>();
    responses.add(response);
    _started.add(requests.length);

    if (cancelFuture == null) return response.future;

    return Future.any(<Future<ResponseBody>>[
      response.future,
      cancelFuture.then<ResponseBody>((_) {
        throw DioException.requestCancelled(
          requestOptions: options,
          reason: 'cancelled by take-latest',
        );
      }),
    ]);
  }

  @override
  void close({bool force = false}) {
    _started.close();
  }
}

void main() {
  test(
    'take-latest cancellation retains ownership and never probes connectivity',
    () async {
      final manager = LikeConnectivityManager();
      await manager.reset();
      var serverChecks = 0;
      manager.debugConfigure(
        interfaceCheck: () async => <ConnectivityResult>[
          ConnectivityResult.wifi,
        ],
        internetCheck: (_, __) async => true,
        serverCheck: (_, __, ___) async {
          serverChecks++;
          return true;
        },
        isWeb: false,
      );
      addTearDown(manager.reset);
      const path = '/take-latest-race';
      const requestKey = 'GET:$path';
      final adapter = _ControlledAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://www.google.com'));
      dio.httpClientAdapter = adapter;
      dio.interceptors.add(LikeConnectivityInterceptor());
      final client = LikeClient(dio: dio);
      addTearDown(client.dispose);

      final first = client.get(
        path,
        disableCache: true,
        sessionStale: false,
      );
      await adapter.waitForExecution(1);

      final firstEntry = client.registry.getInFlight(requestKey);
      expect(firstEntry, isNotNull);
      expect(firstEntry!.$2?.isCancelled, isFalse);

      final second = client.get(
        path,
        disableCache: true,
        sessionStale: false,
      );
      await adapter.waitForExecution(2);

      expect(adapter.requests, hasLength(2));
      expect(firstEntry.$2?.isCancelled, isTrue);

      final secondEntry = client.registry.getInFlight(requestKey);
      expect(secondEntry, isNotNull);
      expect(identical(secondEntry!.$1, firstEntry.$1), isFalse);
      expect(secondEntry.$2?.isCancelled, isFalse);

      final firstResult = await first;
      expect(firstResult.isError, isTrue);
      expect(firstResult.error?.type, LikeApiErrorType.cancelled);

      // The cancelled request's finally block runs before this assertion. It
      // must not remove the newer request that now owns the same registry key.
      final entryAfterFirstCleanup = client.registry.getInFlight(requestKey);
      expect(entryAfterFirstCleanup, isNotNull);
      expect(identical(entryAfterFirstCleanup!.$1, secondEntry.$1), isTrue);
      expect(entryAfterFirstCleanup.$2?.isCancelled, isFalse);

      adapter.complete(1, '{"request": 2}');
      final secondResult = await second;

      expect(secondResult.isSuccess, isTrue);
      expect(secondResult.data?.data, <String, dynamic>{'request': 2});
      expect(adapter.requests, hasLength(2));
      expect(client.registry.getInFlight(requestKey), isNull);
      expect(serverChecks, 0);
    },
  );
}
