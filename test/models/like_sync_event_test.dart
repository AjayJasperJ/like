import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/models/like_sync_event.dart';

void main() {
  group('LikeSyncEvent', () {
    test('should hold fields correctly and serialize to string', () {
      const event = LikeSyncEvent(
        path: '/users/update',
        payload: {'id': 123, 'name': 'John'},
      );

      expect(event.path, equals('/users/update'));
      expect(event.payload, equals({'id': 123, 'name': 'John'}));
      expect(
        event.toString(),
        equals(
            'LikeSyncEvent(path: /users/update, payload: {id: 123, name: John})'),
      );
    });
  });
}
