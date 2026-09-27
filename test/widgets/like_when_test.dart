import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('LikeWhen', () {
    testWidgets('renders custom and default idle states', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeWhen<String>(
            response: LikeStateResponse<String>.idle(),
            onSuccess: Text.new,
            onIdle: () => const Text('idle'),
          ),
        ),
      );
      expect(find.text('idle'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          LikeWhen<String>(
            response: LikeStateResponse<String>.idle(),
            onSuccess: Text.new,
          ),
        ),
      );
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renders custom and default loading states', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeWhen<String>(
            response: LikeStateResponse<String>.loading(),
            onSuccess: Text.new,
            onLoading: () => const Text('loading'),
          ),
        ),
      );
      expect(find.text('loading'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          LikeWhen<String>(
            response: LikeStateResponse<String>.loading(),
            onSuccess: Text.new,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders success, refreshing, and SWR data', (tester) async {
      final responses = <LikeStateResponse<String>>[
        LikeStateResponse<String>.success('success'),
        LikeStateResponse<String>.refreshing('refreshing'),
        LikeStateResponse<String>.staleWhileRevalidate('swr'),
      ];

      for (final response in responses) {
        await tester.pumpWidget(
          _host(
            LikeWhen<String>(
              key: ValueKey(response.state),
              response: response,
              onSuccess: Text.new,
            ),
          ),
        );
        expect(find.text(response.data!), findsOneWidget);
      }
    });

    testWidgets('renders supplied error and synthesized error', (tester) async {
      final error = LikeError(
        message: 'network failed',
        type: LikeApiErrorType.network,
      );
      await tester.pumpWidget(
        _host(
          LikeWhen<String>(
            response: LikeStateResponse<String>.error(error),
            onSuccess: Text.new,
            onError: (value) => Text('${value.message}:${value.type.name}'),
          ),
        ),
      );
      expect(find.text('network failed:network'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          LikeWhen<String>(
            response: const LikeStateResponse<String>(
              state: LikeState.error,
              message: 'synthetic',
              code: 418,
              errorType: LikeApiErrorType.badRequest,
            ),
            onSuccess: Text.new,
            onError: (value) =>
                Text('${value.message}:${value.code}:${value.type.name}'),
          ),
        ),
      );
      expect(find.text('synthetic:418:badRequest'), findsOneWidget);
    });

    testWidgets('renders exception and empty error fallbacks', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeWhen<String>(
            response: LikeStateResponse<String>.exception('crashed'),
            onSuccess: Text.new,
            onException: (message) => Text('exception:$message'),
          ),
        ),
      );
      expect(find.text('exception:crashed'), findsOneWidget);

      final error = LikeError(
        message: 'failed',
        type: LikeApiErrorType.server,
      );
      for (final response in <LikeStateResponse<String>>[
        LikeStateResponse<String>.error(error),
        LikeStateResponse<String>.exception('crashed'),
      ]) {
        await tester.pumpWidget(
          _host(
            LikeWhen<String>(
              key: ValueKey(response.state),
              response: response,
              onSuccess: Text.new,
            ),
          ),
        );
        expect(find.byType(SizedBox), findsOneWidget);
      }
    });

    testWidgets('throws for null or incorrectly typed success data',
        (tester) async {
      final invalidResponses = <LikeStateResponse<dynamic>>[
        const LikeStateResponse<String>(
          state: LikeState.success,
          message: 'missing',
        ),
        LikeStateResponse<int>.success(7),
      ];

      for (var index = 0; index < invalidResponses.length; index++) {
        await tester.pumpWidget(
          _host(
            LikeWhen<String>(
              key: ValueKey(index),
              response: invalidResponses[index],
              onSuccess: Text.new,
            ),
          ),
        );
        expect(tester.takeException(), isA<StateError>());
      }
    });
  });

  group('likeWhenNotifier', () {
    test('calls onInit for every state', () async {
      final states = <LikeState>[];
      await likeWhenNotifier<String>(
        response: LikeStateResponse<String>.loading(),
        onInit: (state) async => states.add(state),
      );
      expect(states, <LikeState>[LikeState.loading]);
    });

    test('maps success and SWR but ignores refreshing', () async {
      final values = <String>[];
      for (final response in <LikeStateResponse<String>>[
        LikeStateResponse<String>.success('success'),
        LikeStateResponse<String>.staleWhileRevalidate('swr'),
        LikeStateResponse<String>.refreshing('refreshing'),
      ]) {
        await likeWhenNotifier<String>(
          response: response,
          onSuccess: (data) async => values.add(data),
        );
      }
      expect(values, <String>['success', 'swr']);
    });

    test('ignores null and mismatched success data', () async {
      var calls = 0;
      await likeWhenNotifier<String>(
        response: LikeStateResponse<int>.success(1),
        onSuccess: (_) async => calls++,
      );
      await likeWhenNotifier<String>(
        response: const LikeStateResponse<String>(
          state: LikeState.success,
          message: 'missing',
        ),
        onSuccess: (_) async => calls++,
      );
      expect(calls, 0);
    });

    test('maps supplied and synthesized errors', () async {
      final errors = <LikeError>[];
      final supplied = LikeError(
        message: 'supplied',
        type: LikeApiErrorType.network,
      );
      await likeWhenNotifier<String>(
        response: LikeStateResponse<String>.error(supplied),
        onError: (error) async => errors.add(error),
      );
      await likeWhenNotifier<String>(
        response: const LikeStateResponse<String>(
          state: LikeState.error,
          message: 'synthetic',
          code: 500,
          errorType: LikeApiErrorType.server,
        ),
        onError: (error) async => errors.add(error),
      );
      expect(errors.first, same(supplied));
      expect(errors.last.message, 'synthetic');
      expect(errors.last.code, 500);
      expect(errors.last.type, LikeApiErrorType.server);
    });

    test('maps exceptions and ignores idle and loading', () async {
      final messages = <String>[];
      await likeWhenNotifier<String>(
        response: LikeStateResponse<String>.exception('crashed'),
        onException: (message) async => messages.add(message),
      );
      await likeWhenNotifier<String>(
        response: LikeStateResponse<String>.idle(),
        onException: (message) async => messages.add(message),
      );
      await likeWhenNotifier<String>(
        response: LikeStateResponse<String>.loading(),
        onException: (message) async => messages.add(message),
      );
      expect(messages, <String>['crashed']);
    });
  });

  group('updateNotifier', () {
    test('maps callbacks with all feedback disabled', () async {
      final events = <String>[];
      final error = LikeError(
        message: 'failed',
        type: LikeApiErrorType.server,
      );
      final responses = <LikeStateResponse<String>>[
        LikeStateResponse<String>.idle(),
        LikeStateResponse<String>.loading(),
        LikeStateResponse<String>.success('success'),
        LikeStateResponse<String>.refreshing('refreshing'),
        LikeStateResponse<String>.staleWhileRevalidate('swr'),
        LikeStateResponse<String>.error(error),
        LikeStateResponse<String>.exception('crashed'),
      ];

      for (final response in responses) {
        await updateNotifier<String>(
          response: response,
          enableHaptics: false,
          onInit: (state) async => events.add('init:${state.name}'),
          onSuccess: (data) async => events.add('success:$data'),
          onError: (value) async => events.add('error:${value.message}'),
          onException: (message) async => events.add('exception:$message'),
        );
      }

      expect(events, <String>[
        'init:idle',
        'init:loading',
        'init:success',
        'success:success',
        'init:refreshing',
        'success:refreshing',
        'init:staleWhileRevalidate',
        'success:swr',
        'init:error',
        'error:failed',
        'init:exception',
        'exception:crashed',
      ]);
    });

    test('synthesizes missing errors and skips mismatched success data',
        () async {
      LikeError? captured;
      var successCalls = 0;
      await updateNotifier<String>(
        response: const LikeStateResponse<String>(
          state: LikeState.error,
          message: 'synthetic',
          code: 400,
          errorType: LikeApiErrorType.badRequest,
        ),
        enableHaptics: false,
        onError: (error) async => captured = error,
      );
      await updateNotifier<String>(
        response: LikeStateResponse<int>.success(1),
        enableHaptics: false,
        onSuccess: (_) async => successCalls++,
      );

      expect(captured?.message, 'synthetic');
      expect(captured?.code, 400);
      expect(captured?.type, LikeApiErrorType.badRequest);
      expect(successCalls, 0);
    });
  });
}
