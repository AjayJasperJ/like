import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/models/like_sync_task.dart';

class SimpleMockSyncTask extends LikeSyncTask {
  final String? _endpoint;
  final LikeSyncPriority _priority;
  bool runCalled = false;

  SimpleMockSyncTask({
    String? endpoint,
    LikeSyncPriority priority = LikeSyncPriority.normal,
  })  : _endpoint = endpoint,
        _priority = priority;

  @override
  String? get endpoint => _endpoint;

  @override
  LikeSyncPriority get priority => _priority;

  @override
  Future<void> run() async {
    runCalled = true;
  }
}

void main() {
  group('LikeSyncTask', () {
    test('default properties and id generation', () {
      final taskWithoutEndpoint = SimpleMockSyncTask();
      expect(taskWithoutEndpoint.endpoint, isNull);
      expect(taskWithoutEndpoint.id, equals('task_SimpleMockSyncTask'));
      expect(taskWithoutEndpoint.retryOnError, isTrue);
      expect(taskWithoutEndpoint.isRecovery, isFalse);

      final taskWithEndpoint = SimpleMockSyncTask(endpoint: 'user_profile');
      expect(taskWithEndpoint.endpoint, equals('user_profile'));
      expect(taskWithEndpoint.id, equals('sync_user_profile'));
    });

    test('equality and hashCode', () {
      final task1 = SimpleMockSyncTask(endpoint: 'endpoint1');
      final task2 = SimpleMockSyncTask(endpoint: 'endpoint1');
      final task3 = SimpleMockSyncTask(endpoint: 'endpoint2');

      expect(task1 == task2, isTrue);
      expect(task1 == task3, isFalse);
      expect(task1.hashCode, equals(task2.hashCode));
      expect(task1.hashCode, isNot(equals(task3.hashCode)));

      // Identical equality
      expect(task1 == task1, isTrue);

      // Null/Other type comparison
      expect(task1 == Object(), isFalse);
    });
  });

  group('LikeAdHocSyncTask', () {
    test('initializes and runs correctly', () async {
      bool actionCalled = false;
      final adhoc = LikeAdHocSyncTask(
        id: 'adhoc_task_1',
        priority: LikeSyncPriority.critical,
        endpoint: 'test_endpoint',
        retryOnError: false,
        isRecovery: true,
        action: () async {
          actionCalled = true;
        },
      );

      expect(adhoc.id, equals('adhoc_task_1'));
      expect(adhoc.priority, equals(LikeSyncPriority.critical));
      expect(adhoc.endpoint, equals('test_endpoint'));
      expect(adhoc.retryOnError, isFalse);
      expect(adhoc.isRecovery, isTrue);

      await adhoc.run();
      expect(actionCalled, isTrue);
    });
  });
}
