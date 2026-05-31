import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../mocks/mocks.dart';

class TestNotifier extends ChangeNotifier with LikeAutoReconnectMixin {
  LikeStateResponse<String> state = LikeStateResponse<String>.idle();
  CancelToken? ct;

  Future<void> fetchData({LikeARS? ars}) async {
    await fetcher<String>(
      ars: ars,
      ct: ct,
      onRotate: (next) => ct = next,
      onUpdate: (newState) => state = newState,
      action: (token, ars) async {
        // Simulate API call
        await Future.delayed(const Duration(milliseconds: 10));
        if (token.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
          );
        }
        return LikeStateResponse<String>.success('data');
      },
    );
  }
}

class TestNotifierWithState extends ChangeNotifier with LikeAutoReconnectMixin {
  final stringState = LikeNotifierState<String>();

  Future<void> fetchData({LikeARS? ars, bool disableRequestCancellation = false}) async {
    await fetch<String>(
      state: stringState,
      ars: ars,
      disableRequestCancellation: disableRequestCancellation,
      action: (token, ars) async {
        // Simulate API call
        await Future.delayed(const Duration(milliseconds: 10));
        if (token.isCancelled) {
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
          );
        }
        return LikeStateResponse<String>.success('data');
      },
    );
  }
}

class TestNotifierWithMapper extends ChangeNotifier with LikeAutoReconnectMixin {
  final stringState = LikeNotifierState<String>(
    mapper: (json) => json['name'] as String,
  );

  Future<void> fetchData({LikeARS? ars}) async {
    await fetch<String>(
      state: stringState,
      ars: ars,
      action: (token, ars) async {
        return LikeStateResponse<String>.success('initial_name');
      },
    );
  }
}

void main() {
  group('LikeAutoReconnectMixin', () {
    late TestNotifier notifier;
    late TestNotifierWithState stateNotifier;

    setUpAll(() async {
      setupMocks();
      await initTestHive();
      await Hive.openBox(LikeConstants.boxApiCache);
      await Hive.openBox(LikeConstants.boxCacheMetadata);
      await Hive.openBox(LikeConstants.boxEtags);
      await Hive.openBox(LikeConstants.boxOfflineQueue);
    });

    setUp(() {
      notifier = TestNotifier();
      stateNotifier = TestNotifierWithState();
    });

    test('fetcher should handle success lifecycle', () async {
      final future = notifier.fetchData();

      expect(notifier.state.isLoading, true);

      await future;

      expect(notifier.state.isSuccess, true);
      expect(notifier.state.data, 'data');
    });

    test('fetcher should rotate and cancel old token', () async {
      final future1 = notifier.fetchData();
      final token1 = notifier.ct;

      final future2 = notifier.fetchData();
      final token2 = notifier.ct;

      expect(token1, isNotNull);
      expect(token2, isNotNull);
      expect(token1 != token2, true);
      expect(token1!.isCancelled, true);

      await future1; // Should complete silently or with idle
      await future2;

      expect(notifier.state.isSuccess, true);
      expect(notifier.state.data, 'data');
    });

    test('fetcher should show loading only if not refreshing', () async {
      // 1. Initial load
      await notifier.fetchData();
      expect(notifier.state.isSuccess, true);

      // 2. Refresh load
      final future = notifier.fetchData(ars: const ARS(refresh: true));

      // Should NOT be loading because it's a refresh
      expect(notifier.state.isLoading, false);
      expect(notifier.state.isSuccess, true); // Still shows old data

      await future;
      expect(notifier.state.isSuccess, true);
    });

    test('newCT should cancel old token and return new one', () {
      final oldToken = CancelToken();
      final newToken = notifier.newCT(oldToken);

      expect(oldToken.isCancelled, true);
      expect(newToken.isCancelled, false);
      expect(oldToken != newToken, true);
    });

    test('cancelTokenNow should cancel token if not already cancelled', () {
      final token = CancelToken();
      notifier.cancelTokenNow(token, 'test');
      expect(token.isCancelled, true);
    });

    group('LikeNotifierState & fetch', () {
      test('should handle success lifecycle using fetch', () async {
        final future = stateNotifier.fetchData();

        expect(stateNotifier.stringState.isLoading, true);
        expect(stateNotifier.stringState.value.isLoading, true);

        await future;

        expect(stateNotifier.stringState.isSuccess, true);
        expect(stateNotifier.stringState.data, 'data');
        expect(stateNotifier.stringState.message, 'Success');
      });

      test('should automatically cancel active request on dispose', () async {
        final future = stateNotifier.fetchData();
        final token = stateNotifier.stringState.ct;

        expect(token, isNotNull);
        expect(token!.isCancelled, false);

        stateNotifier.dispose();

        expect(token.isCancelled, true);
        await future;
      });

      test('should support state clear', () async {
        await stateNotifier.fetchData();
        expect(stateNotifier.stringState.isSuccess, true);

        stateNotifier.stringState.clear(message: 'Cleared');
        expect(stateNotifier.stringState.isIdle, true);
        expect(stateNotifier.stringState.data, isNull);
        expect(stateNotifier.stringState.message, 'Cleared');
      });

      test('clear should notify listeners', () async {
        var notified = false;
        stateNotifier.stringState.addListener(() {
          notified = true;
        });

        stateNotifier.stringState.clear(message: 'Cleared');
        expect(notified, true);
      });
    });

    group('checkQueryOverlap & temporal matching', () {
      test('should overlap if both maps are empty', () {
        expect(notifier.checkQueryOverlap({}, {}), true);
      });

      test('should overlap if one map is empty', () {
        expect(notifier.checkQueryOverlap({'studentId': '123'}, {}), true);
        expect(notifier.checkQueryOverlap({}, {'studentId': '123'}), true);
      });

      test('should match identical parameters with same type', () {
        expect(
          notifier.checkQueryOverlap(
            {'studentId': '123'},
            {'studentId': '123'},
          ),
          true,
        );
      });

      test(
        'should match identical parameters with different types (normalized to string)',
        () {
          expect(
            notifier.checkQueryOverlap(
              {'studentId': 123},
              {'studentId': '123'},
            ),
            true,
          );
          expect(
            notifier.checkQueryOverlap(
              {'studentId': '123'},
              {'studentId': 123},
            ),
            true,
          );
        },
      );

      test('should mismatch if specific parameters conflict', () {
        expect(
          notifier.checkQueryOverlap(
            {'studentId': '123'},
            {'studentId': '456'},
          ),
          false,
        );
      });

      test('should match date ranges (inclusive check)', () {
        final stateQuery = {
          'studentId': '123',
          'startDate': '2026-05-01',
          'endDate': '2026-05-31',
        };

        // Event in range
        expect(
          notifier.checkQueryOverlap(stateQuery, {
            'studentId': '123',
            'date': '2026-05-18',
          }),
          true,
        );

        // Event outside range
        expect(
          notifier.checkQueryOverlap(stateQuery, {
            'studentId': '123',
            'date': '2026-06-01',
          }),
          false,
        );

        // Event in range but different studentId
        expect(
          notifier.checkQueryOverlap(stateQuery, {
            'studentId': '456',
            'date': '2026-05-18',
          }),
          false,
        );
      });
    });

    group('Pipeline Auto-wiring with mapper', () {
      late TestNotifierWithMapper mapperNotifier;

      setUp(() {
        mapperNotifier = TestNotifierWithMapper();
      });

      tearDown(() {
        mapperNotifier.dispose();
      });

      test('should auto-update state via mapper on pipeline event matching path & query', () async {
        // 1. Run fetch to initial state and register it.
        await mapperNotifier.fetchData();

        expect(mapperNotifier.stringState.data, 'initial_name');

        // Manually simulate active endpoint and query set
        mapperNotifier.stringState.endpointPath = '/profile/view';
        mapperNotifier.stringState.activeQuery = {'id': '99'};

        var notified = false;
        mapperNotifier.addListener(() {
          notified = true;
        });

        // 2. Emit an event on the pipeline with matching path and query
        LikePipeline().emit(
          'GET:/profile/view',
          Response(
            requestOptions: RequestOptions(
              path: '/profile/view',
              queryParameters: {'id': '99'},
            ),
            data: {'name': 'Updated via Pipeline'},
          ),
        );

        // Allow event delivery to propagate on stream
        await Future.delayed(Duration.zero);

        expect(mapperNotifier.stringState.isSuccess, true);
        expect(mapperNotifier.stringState.data, 'Updated via Pipeline');
        expect(notified, true);
      });

      test('should ignore event when state is loading', () async {
        await mapperNotifier.fetchData();

        mapperNotifier.stringState.endpointPath = '/profile/view';
        mapperNotifier.stringState.activeQuery = {'id': '99'};
        mapperNotifier.stringState.value = LikeStateResponse<String>.loading();

        LikePipeline().emit(
          'GET:/profile/view',
          Response(
            requestOptions: RequestOptions(
              path: '/profile/view',
              queryParameters: {'id': '99'},
            ),
            data: {'name': 'Should not apply'},
          ),
        );

        await Future.delayed(Duration.zero);

        expect(mapperNotifier.stringState.isLoading, true);
        expect(mapperNotifier.stringState.data, isNull);
      });
    });

    group('disableRequestCancellation Support', () {
      test('should NOT cancel previous request and should reuse token when disableRequestCancellation is true', () async {
        final notifier = TestNotifierWithState();

        // 1. Fetch once
        final f1 = notifier.fetchData(disableRequestCancellation: true);
        final ct1 = notifier.stringState.ct;
        expect(ct1, isNotNull);
        expect(ct1!.isCancelled, false);

        // 2. Fetch a second time with disableRequestCancellation = true
        final f2 = notifier.fetchData(disableRequestCancellation: true);
        final ct2 = notifier.stringState.ct;
        expect(ct2, isNotNull);

        // 3. Confirm that the first cancel token is NOT cancelled!
        expect(ct1.isCancelled, false);
        // And they are indeed the same token
        expect(ct1, ct2);

        // Wait for both to complete
        await f1;
        await f2;
        notifier.dispose();
      });

      test('should cancel previous request by default (disableRequestCancellation = false)', () async {
        final notifier = TestNotifierWithState();

        // 1. Fetch once
        final f1 = notifier.fetchData(disableRequestCancellation: false);
        final ct1 = notifier.stringState.ct;
        expect(ct1, isNotNull);
        expect(ct1!.isCancelled, false);

        // 2. Fetch a second time (default cancels previous)
        final f2 = notifier.fetchData(disableRequestCancellation: false);
        final ct2 = notifier.stringState.ct;
        expect(ct2, isNotNull);

        // 3. Confirm that the first cancel token is cancelled!
        expect(ct1.isCancelled, true);
        expect(ct1 != ct2, true);

        // Wait for both to complete
        await f1;
        await f2;
        notifier.dispose();
      });
    });
  });
}
