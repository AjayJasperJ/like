import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/core/like_helpers.dart';

void main() {
  group('LikeHelpers', () {
    test('query delimiters cannot collide with separate parameters', () {
      expect(
        LikeHelpers.generateRequestKey('/items', {'a': '1&b=2'}),
        isNot(LikeHelpers.generateRequestKey('/items', {'a': '1', 'b': '2'})),
      );
    });

    test('query values retain their types and key ordering is stable', () {
      expect(
        LikeHelpers.generateRequestKey('/items', {'a': 1}),
        isNot(LikeHelpers.generateRequestKey('/items', {'a': '1'})),
      );
      expect(
        LikeHelpers.generateRequestKey('/items', {'b': 2, 'a': 1}),
        LikeHelpers.generateRequestKey('/items', {'a': 1, 'b': 2}),
      );
    });

    test('generateRequestKey should generate consistent keys', () {
      const path = '/users';
      final query = {'id': '123'};

      final key1 = LikeHelpers.generateRequestKey(path, query);
      final key2 = LikeHelpers.generateRequestKey(path, query);

      expect(key1, equals(key2));
    });

    test(
      'generateRequestKey should generate different keys for different query params',
      () {
        const path = '/users';
        final key1 = LikeHelpers.generateRequestKey(path, {'id': '123'});
        final key2 = LikeHelpers.generateRequestKey(path, {'id': '456'});

        expect(key1, isNot(equals(key2)));
      },
    );

    test('normalizeBaseUrl should remove trailing slash if present', () {
      expect(
        LikeHelpers.normalizeBaseUrl('https://api.example.com/'),
        'https://api.example.com',
      );
    });

    test('normalizeBaseUrl should return as is if no trailing slash', () {
      expect(
        LikeHelpers.normalizeBaseUrl('https://api.example.com'),
        'https://api.example.com',
      );
    });
  });
}
