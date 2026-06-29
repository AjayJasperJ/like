import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:like/src/client/like_error_handler.dart';
import 'package:like/src/models/like_error.dart';

void main() {
  group('LikeErrorHandler.parseResponse', () {
    test('handles 400 Bad Request', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 400,
        data: {'message': 'Custom error message'},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.badRequest);
      expect(error.code, 400);
      expect(error.message, 'Custom error message');
    });

    test('handles 405 Method Not Allowed', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 405,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.methodNotAllowed);
      expect(error.code, 405);
      expect(error.message, contains('Method Not Allowed'));
    });

    test('handles 406 Not Acceptable', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 406,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.badRequest);
      expect(error.code, 406);
      expect(error.message, contains('Not Acceptable'));
    });

    test('handles 409 Conflict', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 409,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.conflict);
      expect(error.code, 409);
      expect(error.message, contains('Conflict'));
    });

    test('handles 410 Gone', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 410,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.gone);
      expect(error.code, 410);
      expect(error.message, contains('Gone'));
    });

    test('handles 413 Payload Too Large', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 413,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.payloadTooLarge);
      expect(error.code, 413);
      expect(error.message, contains('Payload Too Large'));
    });

    test('handles 415 Unsupported Media Type', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 415,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.badRequest);
      expect(error.code, 415);
      expect(error.message, contains('Unsupported Media Type'));
    });

    test('handles 505 HTTP Version Not Supported', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 505,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.server);
      expect(error.code, 505);
      expect(error.message, contains('HTTP Version Not Supported'));
    });

    test('handles 301 Moved Permanently', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 301,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.badRequest);
      expect(error.code, 301);
      expect(error.message, contains('Moved Permanently'));
    });

    test('handles 402 Payment Required', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 402,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.forbidden);
      expect(error.code, 402);
      expect(error.message, contains('Payment Required'));
    });

    test('handles 418 I\'m a teapot', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 418,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.badRequest);
      expect(error.code, 418);
      expect(error.message, contains('teapot'));
    });

    test('handles 451 Unavailable For Legal Reasons', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 451,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.forbidden);
      expect(error.code, 451);
      expect(error.message, contains('Legal Reasons'));
    });

    test('handles 511 Network Authentication Required', () async {
      final res = Response(
        requestOptions: RequestOptions(path: '/test'),
        statusCode: 511,
        data: {},
      );
      final error = await LikeErrorHandler.parseResponse(res);
      expect(error.type, LikeApiErrorType.unauthorized);
      expect(error.code, 511);
      expect(error.message, contains('Network Authentication Required'));
    });
  });

  group('LikeErrorHandler.handle exceptions', () {
    test('handles FormatException', () async {
      final error = await LikeErrorHandler.handle(
          const FormatException('Malformed JSON'));
      expect(error.type, LikeApiErrorType.parsing);
      expect(error.message, 'Bad response format');
    });

    test('handles SocketException', () async {
      final error = await LikeErrorHandler.handle(
          const SocketException('Connection refused'));
      expect(error.type, LikeApiErrorType.network);
      expect(error.message, contains('connect'));
    });

    test('handles TimeoutException', () async {
      final error = await LikeErrorHandler.handle(
          TimeoutException('Task exceeded duration'));
      expect(error.type, LikeApiErrorType.timeout);
      expect(error.message, contains('timed out'));
    });

    test('handles HttpException', () async {
      final error = await LikeErrorHandler.handle(
          const HttpException('Invalid protocol headers'));
      expect(error.type, LikeApiErrorType.network);
      expect(error.message, contains('HTTP Protocol Error'));
    });

    test('handles TypeError', () async {
      // Create a function that triggers a TypeError dynamically
      dynamic value = 'String';
      TypeError? typeError;
      try {
        final int _ = value as int;
      } catch (e) {
        if (e is TypeError) {
          typeError = e;
        }
      }
      expect(typeError, isNotNull);
      final error = await LikeErrorHandler.handle(typeError);
      expect(error.type, LikeApiErrorType.parsing);
      expect(error.message, contains('Type Mismatch Error'));
    });

    test('handles AssertionError', () async {
      final error =
          await LikeErrorHandler.handle(AssertionError('Precondition fails'));
      expect(error.type, LikeApiErrorType.unknown);
      expect(error.message, contains('Assertion Failed'));
    });

    test('handles generic Unknown Exception', () async {
      final error =
          await LikeErrorHandler.handle(Exception('Something strange'));
      expect(error.type, LikeApiErrorType.unknown);
      expect(error.message, contains('Unexpected error'));
    });
  });
}
