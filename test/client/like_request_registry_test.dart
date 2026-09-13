import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:like/src/client/like_request_registry.dart';

void main() {
  late LikeRequestRegistry registry;

  setUp(() {
    registry = LikeRequestRegistry();
  });

  group('LikeRequestRegistry', () {
    test('addSessionKey should store key and data', () {
      final response = Response(requestOptions: RequestOptions(path: '/test'));
      registry.addSessionKey('key1', response: response);

      expect(registry.isSessionStale('key1'), isTrue);
      expect(registry.getSessionData('key1'), equals(response));
    });

    test('addInFlight should track requests', () {
      final future = Future.value(
        Response(requestOptions: RequestOptions(path: '/test')),
      );
      final cancelToken = CancelToken();

      registry.addInFlight('key1', (future, cancelToken));

      final inFlight = registry.getInFlight('key1');
      expect(inFlight, isNotNull);
      expect(inFlight!.$1, equals(future));
      expect(inFlight.$2, equals(cancelToken));
    });

    test('removeInFlight should remove requests owned by the future', () {
      final future = Future.value(
        Response(requestOptions: RequestOptions(path: '/test')),
      );
      registry.addInFlight('key1', (future, null));

      expect(registry.removeInFlight('key1', future), isTrue);
      expect(registry.getInFlight('key1'), isNull);
    });

    test('resetSessionStale should clear data', () {
      registry.addSessionKey('key1');
      registry.resetSessionStale();

      expect(registry.isSessionStale('key1'), isFalse);
    });

    test('resetSessionStale with path should clear matching keys', () {
      registry.addSessionKey('https://api.com/users/1');
      registry.addSessionKey('https://api.com/posts/1');

      registry.resetSessionStale(path: '/users');

      expect(registry.isSessionStale('https://api.com/users/1'), isFalse);
      expect(registry.isSessionStale('https://api.com/posts/1'), isTrue);
    });
  });
}
