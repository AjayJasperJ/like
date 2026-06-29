import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/core/like_data_unpacker.dart';

void main() {
  group('DefaultLikeUnpacker', () {
    const unpacker = DefaultLikeUnpacker();

    test('unpack should handle non-map input by returning data as is', () {
      final unpacked = unpacker.unpack('plain text');
      expect(unpacked.data, equals('plain text'));
      expect(unpacked.isSuccess, isTrue);
    });

    test('unpack should extract data key correctly when it exists', () {
      final json = {'data': 'hello', 'status': 'success'};
      final unpacked = unpacker.unpack(json);
      expect(unpacked.data, equals('hello'));
      expect(unpacked.isSuccess, isTrue);
    });

    test('unpack should return null for data when data key is explicitly null',
        () {
      final json = {'data': null, 'status': 'success'};
      final unpacked = unpacker.unpack(json);
      expect(unpacked.data, isNull);
      expect(unpacked.isSuccess, isTrue);
    });

    test('unpack should fallback to full json when data key is absent', () {
      final json = {'username': 'john', 'email': 'john@example.com'};
      final unpacked = unpacker.unpack(json);
      expect(unpacked.data, equals(json));
      expect(unpacked.isSuccess, isTrue);
    });

    test('unpack should prioritize success boolean when present', () {
      final successTrue = {'success': true, 'message': 'Everything OK'};
      expect(unpacker.unpack(successTrue).isSuccess, isTrue);

      final successFalse = {'success': false, 'message': 'Validation error'};
      expect(unpacker.unpack(successFalse).isSuccess, isFalse);
    });

    test('unpack should parse success string cases', () {
      final json = {'success': 'SUCCESS'};
      expect(unpacker.unpack(json).isSuccess, isTrue);

      final json2 = {'success': 'ok'};
      expect(unpacker.unpack(json2).isSuccess, isTrue);

      final json3 = {'success': 'false'};
      expect(unpacker.unpack(json3).isSuccess, isFalse);
    });

    test('unpack should fall back to status key if success key is absent', () {
      final statusOk = {'status': 'ok'};
      expect(unpacker.unpack(statusOk).isSuccess, isTrue);

      final statusFail = {'status': 'failed'};
      expect(unpacker.unpack(statusFail).isSuccess, isFalse);
    });

    test(
        'unpack should default to true when neither success nor status keys exist',
        () {
      final flatJson = {'id': 1, 'name': 'Item 1'};
      expect(unpacker.unpack(flatJson).isSuccess, isTrue);
    });

    test('unpack should extract errors map correctly', () {
      final json = {
        'status': 'error',
        'errors': {'email': 'Email is invalid'}
      };
      final unpacked = unpacker.unpack(json);
      expect(unpacked.errors, equals({'email': 'Email is invalid'}));
    });
  });
}
