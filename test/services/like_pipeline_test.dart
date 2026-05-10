import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/models/like_event.dart';
import 'package:like/src/services/like_pipeline.dart';
import '../mocks/mocks.dart';

void main() {
  late LikePipeline pipeline;

  setUp(() {
    setupMocks();
    pipeline = LikePipeline();
  });

  group('LikePipeline', () {
    test('emit should add event to stream', () async {
      const key = 'test-key';
      final response = Response(
        requestOptions: RequestOptions(path: 'test'),
        data: 'test-data',
        statusCode: 200,
      );

      final events = <LikeEvent>[];
      final subscription = pipeline.stream.listen((event) {
        events.add(event);
      });

      pipeline.emit(key, response);

      // Wait for stream event
      await Future.delayed(Duration.zero);

      expect(events.length, 1);
      expect(events.first.key, equals(key));
      expect(events.first.response.data, equals('test-data'));

      await subscription.cancel();
    });

    test('emit should respect isSyncing flag', () async {
      const key = 'sync-key';
      final response = Response(
        requestOptions: RequestOptions(path: 'test'),
        statusCode: 200,
      );

      final events = <LikeEvent>[];
      final subscription = pipeline.stream.listen((event) {
        events.add(event);
      });

      pipeline.emit(key, response, isSyncing: true);

      await Future.delayed(Duration.zero);

      expect(events.first.isSyncing, isTrue);

      await subscription.cancel();
    });
  });
}
