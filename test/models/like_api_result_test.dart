import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
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

    test('maybeWhen should call correct callback or fallback', () {
      final success = LikeApiResult.success('data');
      final error = LikeApiResult<String>.error(
        LikeError(message: 'err', type: LikeApiErrorType.unknown),
      );

      // success branch
      expect(
        success.maybeWhen(
          onSuccess: (data) => 'got $data',
          orElse: () => 'fallback',
        ),
        'got data',
      );

      // success fallback
      expect(
        success.maybeWhen(
          onError: (err) => 'fail',
          orElse: () => 'fallback',
        ),
        'fallback',
      );

      // error branch
      expect(
        error.maybeWhen(
          onError: (err) => 'fail',
          orElse: () => 'fallback',
        ),
        'fail',
      );

      // error fallback
      expect(
        error.maybeWhen(
          onSuccess: (data) => 'got $data',
          orElse: () => 'fallback',
        ),
        'fallback',
      );
    });

    test('mapSuccess should transform data correctly', () {
      final success = LikeApiResult.success(10);
      final mapped = success.mapSuccess((val) => val * 2);
      expect(mapped.isSuccess, isTrue);
      expect(mapped.data, equals(20));

      // Mapper fails
      final failedMap = success.mapSuccess((val) => throw Exception('map fail'));
      expect(failedMap.isSuccess, isFalse);
      expect(failedMap.error?.message, contains('Mapping failed'));

      // Already error result should return error unchanged
      final error = LikeApiResult<int>.error(
        LikeError(message: 'err', type: LikeApiErrorType.unknown),
      );
      final mappedError = error.mapSuccess((val) => val * 2);
      expect(mappedError.isSuccess, isFalse);
      expect(mappedError.error?.message, equals('err'));
    });

    test('mapSuccessAsync should transform data on compute or catch exception', () async {
      final success = LikeApiResult.success('{"value": 42}');
      final mapped = await success.mapSuccessAsync((data) => 42);
      expect(mapped.isSuccess, isTrue);
      expect(mapped.data, equals(42));

      // With Response data extraction
      final successResponse = LikeApiResult.success(
        Response(requestOptions: RequestOptions(), data: '{"value": 100}'),
      );
      final mappedResponse = await successResponse.mapSuccessAsync((data) => 100);
      expect(mappedResponse.isSuccess, isTrue);
      expect(mappedResponse.data, equals(100));

      // Mapper fails
      final failedMap = await success.mapSuccessAsync((data) => throw Exception('async map fail'));
      expect(failedMap.isSuccess, isFalse);
      expect(failedMap.error?.message, contains('Async mapping failed'));

      // Already error result
      final error = LikeApiResult<String>.error(
        LikeError(message: 'err', type: LikeApiErrorType.unknown),
      );
      final mappedError = await error.mapSuccessAsync((data) => 100);
      expect(mappedError.isSuccess, isFalse);
      expect(mappedError.error?.message, equals('err'));
    });

    test('toStateResponse should convert to state response properly', () {
      final success = LikeApiResult.success('data', isFromCache: true);
      final state1 = success.toStateResponse();
      expect(state1.state, equals(LikeState.success));
      expect(state1.data, equals('data'));
      expect(state1.isFromCache, isTrue);

      final stale = LikeApiResult.success(
        'data',
        isFromStaleWhileRevalidate: true,
      );
      final stateStale = stale.toStateResponse();
      expect(stateStale.state, equals(LikeState.staleWhileRevalidate));
      expect(stateStale.data, equals('data'));

      final error = LikeApiResult<String>.error(
        LikeError(message: 'err', type: LikeApiErrorType.unknown),
      );
      final stateError = error.toStateResponse();
      expect(stateError.state, equals(LikeState.error));
      expect(stateError.error?.message, equals('err'));

      // If error is null, it should fallback
      final nullErrorResult = LikeApiResult<String>.error(null);
      final stateNullError = nullErrorResult.toStateResponse();
      expect(stateNullError.state, equals(LikeState.error));
      expect(stateNullError.error?.message, equals('Unknown error'));
    });

    test('LikeApiResultFutureX extension methods map properly', () async {
      final responseSuccess = LikeApiResult.success(
        Response(requestOptions: RequestOptions(), data: 'data'),
      );
      final Future<LikeApiResult<Response>> futureResult = Future.value(responseSuccess);

      final mappedSync = await futureResult.mapSync((data) => 'sync_$data');
      expect(mappedSync.isSuccess, isTrue);
      expect(mappedSync.data, equals('sync_data'));

      final mappedAsync = await Future.value(responseSuccess).mapAsync((data) => 'async_$data');
      expect(mappedAsync.isSuccess, isTrue);
      expect(mappedAsync.data, equals('async_data'));
    });
  });
}
