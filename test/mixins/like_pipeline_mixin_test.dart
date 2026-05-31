import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:like/src/mixins/like_pipeline_mixin.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class TestPipelineNotifier extends ChangeNotifier with LikePipelineMixin {
  final stringState = LikeNotifierState<String>(
    mapper: (json) => json['name'] as String,
  );

  void bindMyState() {
    bindPipeline<String>(stringState);
  }
}

void main() {
  group('LikePipelineMixin', () {
    late TestPipelineNotifier notifier;

    setUp(() {
      notifier = TestPipelineNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('bindPipeline should auto-update state when matching event is emitted', () async {
      notifier.stringState.endpointPath = '/users/profile';
      notifier.stringState.activeQuery = {'userId': '123'};
      notifier.bindMyState();

      var notified = false;
      notifier.addListener(() {
        notified = true;
      });

      // Emit matching event
      LikePipeline().emit(
        'GET:/users/profile',
        Response(
          requestOptions: RequestOptions(
            path: '/users/profile',
            queryParameters: {'userId': '123'},
          ),
          data: {'name': 'Alice'},
        ),
      );

      // Give stream event time to propagate
      await Future.delayed(Duration.zero);

      expect(notifier.stringState.isSuccess, true);
      expect(notifier.stringState.data, 'Alice');
      expect(notified, true);
    });

    test('bindPipeline should ignore event if path does not match', () async {
      notifier.stringState.endpointPath = '/users/profile';
      notifier.stringState.activeQuery = {'userId': '123'};
      notifier.bindMyState();

      LikePipeline().emit(
        'GET:/users/settings',
        Response(
          requestOptions: RequestOptions(
            path: '/users/settings',
            queryParameters: {'userId': '123'},
          ),
          data: {'name': 'Alice'},
        ),
      );

      await Future.delayed(Duration.zero);

      expect(notifier.stringState.isIdle, true);
      expect(notifier.stringState.data, isNull);
    });

    test('bindPipeline should ignore event if query mismatch', () async {
      notifier.stringState.endpointPath = '/users/profile';
      notifier.stringState.activeQuery = {'userId': '123'};
      notifier.bindMyState();

      LikePipeline().emit(
        'GET:/users/profile',
        Response(
          requestOptions: RequestOptions(
            path: '/users/profile',
            queryParameters: {'userId': '456'},
          ),
          data: {'name': 'Alice'},
        ),
      );

      await Future.delayed(Duration.zero);

      expect(notifier.stringState.isIdle, true);
      expect(notifier.stringState.data, isNull);
    });

    test('bindPipeline should ignore event if state is currently loading', () async {
      notifier.stringState.endpointPath = '/users/profile';
      notifier.stringState.activeQuery = {'userId': '123'};
      notifier.stringState.value = LikeStateResponse<String>.loading();
      notifier.bindMyState();

      LikePipeline().emit(
        'GET:/users/profile',
        Response(
          requestOptions: RequestOptions(
            path: '/users/profile',
            queryParameters: {'userId': '123'},
          ),
          data: {'name': 'Alice'},
        ),
      );

      await Future.delayed(Duration.zero);

      expect(notifier.stringState.isLoading, true);
      expect(notifier.stringState.data, isNull);
    });

    test('initPipeline should support manual/legacy registrations', () async {
      var manualCalled = false;
      var receivedData = '';

      notifier.initPipeline({
        '/users/notifications': (key, data, {isSyncing = false, timestamp}) {
          manualCalled = true;
          receivedData = data as String;
        }
      });

      LikePipeline().emit(
        'GET:/users/notifications',
        Response(
          requestOptions: RequestOptions(path: '/users/notifications'),
          data: 'alert_data',
        ),
      );

      await Future.delayed(Duration.zero);

      expect(manualCalled, true);
      expect(receivedData, 'alert_data');
    });

    test('registerPipelineListener and unregisterPipelineListener should work', () async {
      var manualCalledCount = 0;

      notifier.registerPipelineListener(
        '/users/alerts',
        (key, data, {isSyncing = false, timestamp}) {
          manualCalledCount++;
        },
      );

      LikePipeline().emit(
        'GET:/users/alerts',
        Response(
          requestOptions: RequestOptions(path: '/users/alerts'),
          data: 'alert1',
        ),
      );

      await Future.delayed(Duration.zero);
      expect(manualCalledCount, 1);

      // Unregister listener
      notifier.unregisterPipelineListener('/users/alerts');

      LikePipeline().emit(
        'GET:/users/alerts',
        Response(
          requestOptions: RequestOptions(path: '/users/alerts'),
          data: 'alert2',
        ),
      );

      await Future.delayed(Duration.zero);
      expect(manualCalledCount, 1); // Should still be 1
    });
  });
}
