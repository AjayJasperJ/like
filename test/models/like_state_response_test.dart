import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

class ModelWithMessage {
  final String message;
  ModelWithMessage(this.message);
}

void main() {
  group('LikeStateResponse', () {
    test('factory constructors initialize correctly', () {
      final idle = LikeStateResponse<String>.idle(message: 'custom idle');
      expect(idle.state, equals(LikeState.idle));
      expect(idle.message, equals('custom idle'));
      expect(idle.isIdle, isTrue);

      final idleDefault = LikeStateResponse<String>.idle();
      expect(idleDefault.message, equals('Idle'));

      final loading = LikeStateResponse<String>.loading(message: 'custom loading');
      expect(loading.state, equals(LikeState.loading));
      expect(loading.message, equals('custom loading'));
      expect(loading.isLoading, isTrue);

      final loadingDefault = LikeStateResponse<String>.loading();
      expect(loadingDefault.message, equals('Loading...'));

      final success = LikeStateResponse<String>.success('data_payload', message: 'custom success');
      expect(success.state, equals(LikeState.success));
      expect(success.data, equals('data_payload'));
      expect(success.message, equals('custom success'));
      expect(success.isSuccess, isTrue);

      final successDefault = LikeStateResponse<String>.success('data_payload');
      expect(successDefault.message, equals('Success'));

      final swr = LikeStateResponse<String>.staleWhileRevalidate('stale_data', message: 'custom swr');
      expect(swr.state, equals(LikeState.staleWhileRevalidate));
      expect(swr.data, equals('stale_data'));
      expect(swr.message, equals('custom swr'));
      expect(swr.isStaleWhileRevalidate, isTrue);
      expect(swr.isFromCache, isTrue);
      expect(swr.isFromStaleWhileRevalidate, isTrue);

      final swrDefault = LikeStateResponse<String>.staleWhileRevalidate('stale_data');
      expect(swrDefault.message, equals('Serving from cache...'));

      final refreshing = LikeStateResponse<String>.refreshing('refresh_data', message: 'custom ref', isFromCache: true);
      expect(refreshing.state, equals(LikeState.refreshing));
      expect(refreshing.data, equals('refresh_data'));
      expect(refreshing.message, equals('custom ref'));
      expect(refreshing.isRefreshing, isTrue);
      expect(refreshing.isFromCache, isTrue);

      final refreshingDefault = LikeStateResponse<String>.refreshing('refresh_data');
      expect(refreshingDefault.message, equals('Refreshing...'));

      final errObject = LikeError(message: 'error msg', type: LikeApiErrorType.server, code: 500);
      final error = LikeStateResponse<String>.error(errObject, data: 'err_data');
      expect(error.state, equals(LikeState.error));
      expect(error.error, equals(errObject));
      expect(error.data, equals('err_data'));
      expect(error.message, equals('error msg'));
      expect(error.isError, isTrue);

      final exception = LikeStateResponse<String>.exception('ex_msg', data: 'ex_data');
      expect(exception.state, equals(LikeState.exception));
      expect(exception.message, equals('ex_msg'));
      expect(exception.data, equals('ex_data'));
      expect(exception.isException, isTrue);

      final unknown = LikeStateResponse<String>.unknown();
      expect(unknown.state, equals(LikeState.exception));
      expect(unknown.message, contains('Something went wrong'));

      final missing = LikeStateResponse<String>.missingData('no data found');
      expect(missing.state, equals(LikeState.error));
      expect(missing.message, equals('no data found'));
    });

    test('error factory extracts rawResponse data if compatible', () {
      final errWithData = LikeError(
        message: 'Fail',
        type: LikeApiErrorType.badRequest,
        rawResponse: 'compatible_string',
      );
      final response = LikeStateResponse<String>.error(errWithData);
      expect(response.data, equals('compatible_string'));

      final errWithIncompatibleData = LikeError(
        message: 'Fail',
        type: LikeApiErrorType.badRequest,
        rawResponse: 12345,
      );
      final response2 = LikeStateResponse<String>.error(errWithIncompatibleData);
      expect(response2.data, isNull);
    });

    test('fromResult creates correct state response', () {
      final successResult = LikeApiResult.success('result_data', isFromCache: true);
      final successResponse = LikeStateResponse<String>.fromResult(successResult);
      expect(successResponse.isSuccess, isTrue);
      expect(successResponse.data, equals('result_data'));
      expect(successResponse.isFromCache, isTrue);

      final errorResult = LikeApiResult<String>.error(
        LikeError(message: 'result_err', type: LikeApiErrorType.notFound),
        isResiliencyFallback: true,
      );
      final errorResponse = LikeStateResponse<String>.fromResult(errorResult);
      expect(errorResponse.isError, isTrue);
      expect(errorResponse.error?.message, equals('result_err'));
      expect(errorResponse.isResiliencyFallback, isTrue);
    });

    test('resolvedMessage extracts message from data if needed', () {
      // 1. Success, custom/empty message, data has map 'message'
      final mapDataResponse = LikeStateResponse.success(
        {'message': 'Extracted Map Message'},
        message: 'Success',
      );
      expect(mapDataResponse.resolvedMessage, equals('Extracted Map Message'));

      // 2. Success, custom/empty message, data has object message getter
      final objDataResponse = LikeStateResponse.success(
        ModelWithMessage('Extracted Object Message'),
        message: '',
      );
      expect(objDataResponse.resolvedMessage, equals('Extracted Object Message'));

      // 3. Success, custom/empty message, data has nothing
      final emptyDataResponse = LikeStateResponse.success(
        123,
        message: 'Success',
      );
      expect(emptyDataResponse.resolvedMessage, equals('Success'));

      // 4. Not success state
      final loadingResponse = LikeStateResponse.loading(message: 'Loading status');
      expect(loadingResponse.resolvedMessage, equals('Loading status'));
    });

    test('copyWith works correctly', () {
      final base = LikeStateResponse<String>(
        state: LikeState.idle,
        message: 'base_msg',
        data: 'base_data',
        isFrom304: true,
      );

      final updated = base.copyWith(
        state: LikeState.success,
        message: 'new_msg',
        data: 'new_data',
        error: LikeError(message: 'new_err', type: LikeApiErrorType.unknown),
        errorType: LikeApiErrorType.unknown,
        code: 200,
        isFromCache: true,
        isFromStaleWhileRevalidate: true,
        isResiliencyFallback: true,
        isFrom304: false,
      );

      expect(updated.state, equals(LikeState.success));
      expect(updated.message, equals('new_msg'));
      expect(updated.data, equals('new_data'));
      expect(updated.error?.message, equals('new_err'));
      expect(updated.errorType, equals(LikeApiErrorType.unknown));
      expect(updated.code, equals(200));
      expect(updated.isFromCache, isTrue);
      expect(updated.isFromStaleWhileRevalidate, isTrue);
      expect(updated.isResiliencyFallback, isTrue);
      expect(updated.isFrom304, isFalse);

      // Copy with nothing updates nothing
      final emptyCopy = base.copyWith();
      expect(emptyCopy, equals(base));
    });

    test('equality and hashCode work correctly', () {
      final response1 = LikeStateResponse<String>(
        state: LikeState.success,
        message: 'msg',
        data: 'data',
        isFrom304: true,
      );

      final response2 = LikeStateResponse<String>(
        state: LikeState.success,
        message: 'msg',
        data: 'data',
        isFrom304: true,
      );

      final responseDiff = LikeStateResponse<String>(
        state: LikeState.success,
        message: 'msg2',
        data: 'data',
        isFrom304: true,
      );

      expect(response1 == response2, isTrue);
      expect(response1 == responseDiff, isFalse);
      expect(response1.hashCode, equals(response2.hashCode));
      expect(response1.hashCode, isNot(equals(responseDiff.hashCode)));

      // Identical
      expect(response1 == response1, isTrue);

      // Other type comparison
      expect(response1 == Object(), isFalse);
    });

    test('when extension maps correctly', () {
      // 1. Idle state
      final idle = LikeStateResponse<String>.idle();
      expect(
        idle.when(
          onSuccess: (data, ref, swr, fall) => 'success',
          onIdle: () => 'idle',
          orElse: () => 'else',
        ),
        equals('idle'),
      );

      // 2. Loading state
      final loading = LikeStateResponse<String>.loading();
      expect(
        loading.when(
          onSuccess: (data, ref, swr, fall) => 'success',
          onLoading: () => 'loading',
          orElse: () => 'else',
        ),
        equals('loading'),
      );

      // 3. Error state
      final error = LikeStateResponse<String>.error(LikeError(message: 'err', type: LikeApiErrorType.unknown));
      expect(
        error.when(
          onSuccess: (data, ref, swr, fall) => 'success',
          onError: (err) => 'error: ${err.message}',
          orElse: () => 'else',
        ),
        equals('error: err'),
      );

      // 4. Exception state
      final exception = LikeStateResponse<String>.exception('ex');
      expect(
        exception.when(
          onSuccess: (data, ref, swr, fall) => 'success',
          onException: (msg) => 'exception: $msg',
          orElse: () => 'else',
        ),
        equals('exception: ex'),
      );

      // 5. Success state
      final success = LikeStateResponse<String>.success('data');
      expect(
        success.when(
          onSuccess: (data, ref, swr, fall) => 'success_$data',
          orElse: () => 'else',
        ),
        equals('success_data'),
      );

      // 6. Success state but null data returns orElse
      final successNull = LikeStateResponse<String>(state: LikeState.success, message: 'msg');
      expect(
        successNull.when(
          onSuccess: (data, ref, swr, fall) => 'success',
          orElse: () => 'else_null',
        ),
        equals('else_null'),
      );
    });

    test('whenSliver extension maps correctly', () {
      final success = LikeStateResponse<String>.success('data');
      final slivers = success.whenSliver(
        onSuccess: (data, ref, swr, fall) => [const Text('success')],
      );
      expect(slivers.length, equals(1));

      final loading = LikeStateResponse<String>.loading();
      final emptySlivers = loading.whenSliver(
        onSuccess: (data, ref, swr, fall) => [const Text('success')],
      );
      expect(emptySlivers, isEmpty);
    });
  });
}
