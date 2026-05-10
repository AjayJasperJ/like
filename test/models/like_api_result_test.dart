import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  group('LikeApiResult', () {
    test('success should create a success result', () {
      final result = LikeApiResult.success('data');
      expect(result.isSuccess, isTrue);
      expect(result.isError, isFalse);
      expect(result.data, equals('data'));
      expect(result.error, isNull);
    });

    test('error should create an error result', () {
      final error = LikeError(message: 'Error', type: LikeApiErrorType.unknown);
      final result = LikeApiResult<String>.error(error);
      expect(result.isSuccess, isFalse);
      expect(result.isError, isTrue);
      expect(result.data, isNull);
      expect(result.error, equals(error));
    });

    test('when should call correct callback', () {
      final success = LikeApiResult.success('data');
      final error = LikeApiResult<String>.error(
        LikeError(message: 'err', type: LikeApiErrorType.unknown),
      );

      expect(
        success.when(
          onSuccess: (data) => 'got $data',
          onError: (err) => 'fail',
        ),
        'got data',
      );

      expect(
        error.when(onSuccess: (data) => 'got $data', onError: (err) => 'fail'),
        'fail',
      );
    });
  });
}
