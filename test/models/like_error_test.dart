import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  group('LikeError', () {
    test('should hold fields correctly', () {
      final error = LikeError(
        message: 'Network timed out',
        code: 408,
        type: LikeApiErrorType.timeout,
        rawResponse: 'Raw data',
      );

      expect(error.message, equals('Network timed out'));
      expect(error.code, equals(408));
      expect(error.type, equals(LikeApiErrorType.timeout));
      expect(error.rawResponse, equals('Raw data'));
    });

    test('errors getter should extract structured errors from map response', () {
      // 1. Success path: rawResponse has 'errors' as map
      final errorWithErrors = LikeError(
        message: 'Validation failed',
        type: LikeApiErrorType.badRequest,
        rawResponse: {
          'errors': {'email': 'Email is invalid'}
        },
      );
      expect(errorWithErrors.errors, equals({'email': 'Email is invalid'}));

      // 2. No 'errors' key
      final errorNoErrorsKey = LikeError(
        message: 'Fail',
        type: LikeApiErrorType.badRequest,
        rawResponse: {'status': 'fail'},
      );
      expect(errorNoErrorsKey.errors, isEmpty);

      // 3. 'errors' key is not a map
      final errorNonMapErrors = LikeError(
        message: 'Fail',
        type: LikeApiErrorType.badRequest,
        rawResponse: {'errors': 'Not a map'},
      );
      expect(errorNonMapErrors.errors, isEmpty);

      // 4. rawResponse is not a map
      final errorNonMapResponse = LikeError(
        message: 'Fail',
        type: LikeApiErrorType.badRequest,
        rawResponse: 'Simple string error',
      );
      expect(errorNonMapResponse.errors, isEmpty);
    });

    test('toString returns descriptive representation', () {
      final error = LikeError(
        message: 'Not Found',
        code: 404,
        type: LikeApiErrorType.notFound,
      );

      expect(
        error.toString(),
        equals('LikeError(message: Not Found, code: 404, type: LikeApiErrorType.notFound)'),
      );
    });
  });
}
