import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

class _OriginAdapter implements HttpClientAdapter {
  final started = StreamController<int>.broadcast();
  final requests = <RequestOptions>[];
  final pending = <Completer<ResponseBody>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? stream,
      Future<dynamic>? cancel) {
    requests.add(options);
    final response = Completer<ResponseBody>();
    pending.add(response);
    started.add(requests.length);
    return response.future;
  }

  Future<void> waitFor(int count) async {
    if (requests.length < count) {
      await started.stream.firstWhere((value) => value >= count);
    }
  }

  @override
  void close({bool force = false}) {
    started.close();
  }
}

void main() {
  test('request-level origins never deduplicate the same relative endpoint',
      () async {
    final adapter = _OriginAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://first.example'))
      ..httpClientAdapter = adapter;
    final client = LikeClient(dio: dio);
    addTearDown(client.dispose);
    final first = client.get('/items', disableCache: true);
    await adapter.waitFor(1);
    final second = client.get('/items',
        disableCache: true,
        requestConfig:
            const LikeRequestConfig(baseUrl: 'https://second.example'));
    await adapter.waitFor(2).timeout(const Duration(seconds: 2));
    expect(adapter.requests.map((r) => r.uri.host),
        ['first.example', 'second.example']);
    for (var i = 0; i < adapter.pending.length; i++) {
      adapter.pending[i]
          .complete(ResponseBody.fromString('{"origin":$i}', 200, headers: {
        Headers.contentTypeHeader: ['application/json']
      }));
    }
    expect((await first).data!.data['origin'], 0);
    expect((await second).data!.data['origin'], 1);
    expect(
        client.registry
            .getSessionData('https://first.example/items')!
            .data['origin'],
        0);
    expect(
        client.registry
            .getSessionData('https://second.example/items')!
            .data['origin'],
        1);
  });
}
