import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

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

void main() {
  group('LikeAutoReconnectMixin', () {
    late TestNotifier notifier;

    setUp(() {
      notifier = TestNotifier();
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
  });
}
