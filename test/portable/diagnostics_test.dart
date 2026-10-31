import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

class _Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<dynamic>? cancelFuture) async {
    return ResponseBody.fromString('{"token":"server-secret","name":"Ajay"}', 200,
      headers: {Headers.contentTypeHeader: ['application/json']});
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  test('redaction is recursive, case insensitive, nonmutating and handles JSON', () {
    final original = {'Authorization': 'Bearer secret', 'rows': [
      {'refresh_token': 'private', 'EMAIL': 'private@example.com', 'count': 3}
    ], 'custom-secret': 'hidden'};
    final safe = jsonEncode(LikeRedaction.sanitize(original,
      sensitiveKeys: ['custom-secret']));
    expect(safe, isNot(contains('Bearer secret')));
    expect(safe, isNot(contains('private')));
    expect(safe, isNot(contains('hidden')));
    expect(safe, contains('REDACTED'));
    expect(original['Authorization'], 'Bearer secret');
    expect(jsonEncode(LikeRedaction.sanitize('{"password":"secret"}')),
      isNot(contains('secret')));
    expect(LikeRedaction.sanitize('opaque secret'), LikeRedaction.omitted);
  });

  test('release API bodies are omitted regardless of their fields', () {
    expect(LikeRedaction.apiPayload({'unknown': 123}, release: true),
      LikeRedaction.omitted);
    expect(LikeRedaction.apiPayload({'token': 'secret'}, release: false),
      {'token': LikeRedaction.masked});
  });

  test('endpoint diagnostics discard credentials, query and fragment', () {
    expect(LikeRedaction.endpoint('https://user:secret@api.example/items?token=secret#secret'),
      'https://api.example/items');
  });

  test('quality needs repeated slow samples, isolates origins and recovers', () async {
    final monitor = LikeNetworkQualityMonitor();
    addTearDown(monitor.dispose);
    final uri = Uri.parse('https://slow.example/items');
    monitor.record(uri: uri, elapsed: const Duration(seconds: 3));
    expect(monitor.latest(uri.origin)!.quality, LikeNetworkQuality.unknown);
    monitor.record(uri: uri, elapsed: const Duration(seconds: 3));
    expect(monitor.latest(uri.origin)!.quality, LikeNetworkQuality.slow);
    monitor.record(uri: Uri.parse('https://fast.example/items'),
      elapsed: const Duration(milliseconds: 100));
    expect(monitor.latest('https://fast.example')!.quality, LikeNetworkQuality.normal);
    monitor.record(uri: uri, elapsed: const Duration(milliseconds: 100));
    expect(monitor.latest(uri.origin)!.quality, LikeNetworkQuality.normal);
  });

  test('quality reports large-transfer estimates and ignores small samples', () async {
    final monitor = LikeNetworkQualityMonitor(samplesForSlow: 1);
    final uri = Uri.parse('https://transfer.example');
    monitor.record(uri: uri, elapsed: const Duration(seconds: 4), bytes: 65536);
    expect(monitor.latest(uri.origin)!.estimatedBytesPerSecond, 16384);
    monitor.record(uri: uri, elapsed: const Duration(milliseconds: 100), bytes: 1);
    expect(monitor.latest(uri.origin)!.estimatedBytesPerSecond, isNull);
    await monitor.dispose();
    monitor.record(uri: uri, elapsed: const Duration(seconds: 3));
    expect(monitor.latest(uri.origin), isNull);
  });

  test('logger sanitizes all sinks without modifying the Dio response', () async {
    LikeConstants.apply(LikeConfig(projectName: 'portable-tests', disableFileLogging: true, silentConsole: true));
    addTearDown(LikeConstants.reset);
    final entry = LikeLogger.logStream.first;
    final dio = Dio()..httpClientAdapter = _Adapter();
    addTearDown(dio.close);
    final response = await dio.get<dynamic>('https://api.example/items');
    await LikeLogger.logApi('https://api.example/items?token=url-secret',
      success: true, response: response.data,
      requestHeaders: {'Authorization': 'Bearer auth-secret'});
    final output = await entry;
    expect(output, isNot(contains('server-secret')));
    expect(output, isNot(contains('auth-secret')));
    expect(output, isNot(contains('url-secret')));
    expect(response.data['token'], 'server-secret');
  });
}
