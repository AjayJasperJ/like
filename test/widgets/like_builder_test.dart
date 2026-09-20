import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('LikeBuilder', () {
    testWidgets('renders custom and default idle states', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => LikeStateResponse<String>.idle(),
            onSuccess: (data, refreshing, swr) => Text(data),
            onIdle: () => const Text('idle'),
          ),
        ),
      );
      expect(find.text('idle'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => LikeStateResponse<String>.idle(),
            onSuccess: (data, refreshing, swr) => Text(data),
          ),
        ),
      );
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renders custom and default loading states', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => LikeStateResponse<String>.loading(),
            onSuccess: (data, refreshing, swr) => Text(data),
            onLoading: () => const Text('loading'),
          ),
        ),
      );
      expect(find.text('loading'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => LikeStateResponse<String>.loading(),
            onSuccess: (data, refreshing, swr) => Text(data),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('passes success, refreshing, and SWR metadata', (tester) async {
      final states = <LikeStateResponse<String>>[
        LikeStateResponse<String>.success('success'),
        LikeStateResponse<String>.refreshing('refreshing'),
        LikeStateResponse<String>.staleWhileRevalidate('swr'),
        LikeStateResponse<String>.success(
          'flagged',
          isFromStaleWhileRevalidate: true,
        ),
      ];
      final expected = <String>[
        'success:false:false',
        'refreshing:true:false',
        'swr:false:true',
        'flagged:false:true',
      ];

      for (var index = 0; index < states.length; index++) {
        await tester.pumpWidget(
          _host(
            LikeBuilder<String>(
              key: ValueKey(index),
              observe: () => states[index],
              onSuccess: (data, refreshing, swr) =>
                  Text('$data:$refreshing:$swr'),
            ),
          ),
        );
        expect(find.text(expected[index]), findsOneWidget);
      }
    });

    testWidgets('renders error and exception builders', (tester) async {
      final error = LikeError(
        message: 'request failed',
        type: LikeApiErrorType.server,
      );
      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => LikeStateResponse<String>.error(error),
            onSuccess: (data, refreshing, swr) => Text(data),
            onError: (value) => Text('error:${value.message}'),
          ),
        ),
      );
      expect(find.text('error:request failed'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => LikeStateResponse<String>.exception(
              'crashed',
              error: error,
            ),
            onSuccess: (data, refreshing, swr) => Text(data),
            onException: (message, value) =>
                Text('exception:$message:${value?.type.name}'),
          ),
        ),
      );
      expect(find.text('exception:crashed:server'), findsOneWidget);
    });

    testWidgets('uses empty fallbacks when error builders are omitted',
        (tester) async {
      final error = LikeError(
        message: 'request failed',
        type: LikeApiErrorType.server,
      );
      for (final response in <LikeStateResponse<String>>[
        LikeStateResponse<String>.error(error),
        LikeStateResponse<String>.exception('crashed'),
      ]) {
        await tester.pumpWidget(
          _host(
            LikeBuilder<String>(
              key: ValueKey(response.state),
              observe: () => response,
              onSuccess: (data, refreshing, swr) => Text(data),
            ),
          ),
        );
        expect(find.byType(SizedBox), findsOneWidget);
      }
    });

    testWidgets(
        'rebuilds from notifier updates and invokes listener once per value',
        (tester) async {
      final notifier = LikeNotifierState<String>();
      final heard = <LikeStateResponse<dynamic>>[];

      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => notifier,
            listener: heard.add,
            onIdle: () => const Text('idle'),
            onLoading: () => const Text('loading'),
            onSuccess: (data, refreshing, swr) => Text(data),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('idle'), findsOneWidget);
      expect(heard, hasLength(1));

      notifier.value = LikeStateResponse<String>.loading();
      await tester.pump();
      expect(find.text('loading'), findsOneWidget);
      expect(heard, hasLength(2));

      await tester.pump();
      expect(heard, hasLength(2));

      notifier.value = LikeStateResponse<String>.success('done');
      await tester.pump();
      expect(find.text('done'), findsOneWidget);
      expect(heard, hasLength(3));

      await tester.pumpWidget(const SizedBox());
      notifier.value = LikeStateResponse<String>.success('after dispose');
      await tester.pump();
      expect(tester.takeException(), isNull);
      notifier.dispose();
    });

    testWidgets('switches subscriptions when the observed notifier changes',
        (tester) async {
      final first = LikeNotifierState<String>(
        initialValue: LikeStateResponse<String>.success('first'),
      );
      final second = LikeNotifierState<String>(
        initialValue: LikeStateResponse<String>.success('second'),
      );

      Widget build(LikeNotifierState<String> notifier) => _host(
            LikeBuilder<String>(
              observe: () => notifier,
              onSuccess: (data, refreshing, swr) => Text(data),
            ),
          );

      await tester.pumpWidget(build(first));
      expect(find.text('first'), findsOneWidget);
      await tester.pumpWidget(build(second));
      expect(find.text('second'), findsOneWidget);

      first.value = LikeStateResponse<String>.success('ignored');
      await tester.pump();
      expect(find.text('second'), findsOneWidget);

      second.value = LikeStateResponse<String>.success('updated');
      await tester.pump();
      expect(find.text('updated'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      first.dispose();
      second.dispose();
    });

    testWidgets('rejects invalid observe values', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => 'invalid',
            onSuccess: (data, refreshing, swr) => Text(data),
          ),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });

    testWidgets('throws when a data state has null data', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeBuilder<String>(
            observe: () => const LikeStateResponse<String>(
              state: LikeState.success,
              message: 'invalid',
            ),
            onSuccess: (data, refreshing, swr) => Text(data),
          ),
        ),
      );
      expect(tester.takeException(), isA<StateError>());
    });
  });

  group('LikeStateResponseBuilder', () {
    testWidgets('delegates snapshot states to LikeBuilder', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeStateResponseBuilder<String>(
            response: LikeStateResponse<String>.success('snapshot'),
            onSuccess: (data, refreshing, swr) =>
                Text('$data:$refreshing:$swr'),
          ),
        ),
      );
      expect(find.text('snapshot:false:false'), findsOneWidget);
    });
  });
}
