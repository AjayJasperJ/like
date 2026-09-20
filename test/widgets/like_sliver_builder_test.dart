import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

Widget _host(Widget sliver) => MaterialApp(
      home: Scaffold(
        body: CustomScrollView(slivers: <Widget>[sliver]),
      ),
    );

List<Widget> _textSliver(String text) => <Widget>[
      SliverToBoxAdapter(child: Text(text)),
    ];

void main() {
  group('LikeSliverBuilder', () {
    testWidgets('renders custom idle and loading slivers', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeSliverBuilder<String>(
            observe: () => LikeStateResponse<String>.idle(),
            onSuccess: (data, refreshing, swr) => _textSliver(data),
            onIdle: () => _textSliver('idle'),
          ),
        ),
      );
      expect(find.text('idle'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          LikeSliverBuilder<String>(
            observe: () => LikeStateResponse<String>.loading(),
            onSuccess: (data, refreshing, swr) => _textSliver(data),
            onLoading: () => _textSliver('loading'),
          ),
        ),
      );
      expect(find.text('loading'), findsOneWidget);
    });

    testWidgets('renders default loading sliver safely', (tester) async {
      await tester.pumpWidget(
        _host(
          LikeSliverBuilder<String>(
            observe: () => LikeStateResponse<String>.loading(),
            onSuccess: (data, refreshing, swr) => _textSliver(data),
          ),
        ),
      );
      expect(find.byType(SliverFillRemaining), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
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
            LikeSliverBuilder<String>(
              key: ValueKey(index),
              observe: () => states[index],
              onSuccess: (data, refreshing, swr) =>
                  _textSliver('$data:$refreshing:$swr'),
            ),
          ),
        );
        expect(find.text(expected[index]), findsOneWidget);
      }
    });

    testWidgets('renders error and exception slivers', (tester) async {
      final error = LikeError(
        message: 'request failed',
        type: LikeApiErrorType.server,
      );
      await tester.pumpWidget(
        _host(
          LikeSliverBuilder<String>(
            observe: () => LikeStateResponse<String>.error(error),
            onSuccess: (data, refreshing, swr) => _textSliver(data),
            onError: (value) => _textSliver('error:${value.message}'),
          ),
        ),
      );
      expect(find.text('error:request failed'), findsOneWidget);

      await tester.pumpWidget(
        _host(
          LikeSliverBuilder<String>(
            observe: () => LikeStateResponse<String>.exception(
              'crashed',
              error: error,
            ),
            onSuccess: (data, refreshing, swr) => _textSliver(data),
            onException: (message, value) =>
                _textSliver('exception:$message:${value?.type.name}'),
          ),
        ),
      );
      expect(find.text('exception:crashed:server'), findsOneWidget);
    });

    testWidgets('renders no content for omitted idle and error builders',
        (tester) async {
      final error = LikeError(
        message: 'request failed',
        type: LikeApiErrorType.server,
      );
      for (final response in <LikeStateResponse<String>>[
        LikeStateResponse<String>.idle(),
        LikeStateResponse<String>.error(error),
        LikeStateResponse<String>.exception('crashed'),
      ]) {
        await tester.pumpWidget(
          _host(
            LikeSliverBuilder<String>(
              key: ValueKey(response.state),
              observe: () => response,
              onSuccess: (data, refreshing, swr) => _textSliver(data),
            ),
          ),
        );
        expect(find.byType(SliverToBoxAdapter), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('rebuilds from notifier and invokes listener once per value',
        (tester) async {
      final notifier = LikeNotifierState<String>();
      final heard = <LikeStateResponse<dynamic>>[];

      await tester.pumpWidget(
        _host(
          LikeSliverBuilder<String>(
            observe: () => notifier,
            listener: heard.add,
            onIdle: () => _textSliver('idle'),
            onSuccess: (data, refreshing, swr) => _textSliver(data),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('idle'), findsOneWidget);
      expect(heard, hasLength(1));

      notifier.value = LikeStateResponse<String>.success('done');
      await tester.pump();
      expect(find.text('done'), findsOneWidget);
      expect(heard, hasLength(2));
      await tester.pump();
      expect(heard, hasLength(2));

      await tester.pumpWidget(const SizedBox());
      notifier.value = LikeStateResponse<String>.success('after dispose');
      await tester.pump();
      expect(tester.takeException(), isNull);
      notifier.dispose();
    });

    testWidgets('switches subscriptions when notifier changes', (tester) async {
      final first = LikeNotifierState<String>(
        initialValue: LikeStateResponse<String>.success('first'),
      );
      final second = LikeNotifierState<String>(
        initialValue: LikeStateResponse<String>.success('second'),
      );

      Widget build(LikeNotifierState<String> notifier) => _host(
            LikeSliverBuilder<String>(
              observe: () => notifier,
              onSuccess: (data, refreshing, swr) => _textSliver(data),
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
          LikeSliverBuilder<String>(
            observe: () => 'invalid',
            onSuccess: (data, refreshing, swr) => _textSliver(data),
          ),
        ),
      );
      expect(tester.takeException(), isA<AssertionError>());
    });

    testWidgets('throws when a data state has null data', (tester) async {
      LikeStateResponse<String> response =
          LikeStateResponse<String>.success('valid');
      await tester.pumpWidget(
        _host(
          LikeSliverBuilder<String>(
            observe: () => response,
            onSuccess: (data, refreshing, swr) => _textSliver(data),
          ),
        ),
      );
      final element = tester.element(
        find.byType(LikeSliverBuilder<String>),
      ) as StatefulElement;
      response = const LikeStateResponse<String>(
        state: LikeState.success,
        message: 'invalid',
      );

      expect(
        () => (element.state as dynamic).build(element),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('requires non-null data'),
          ),
        ),
      );
    });
  });

  group('LikeStateResponseBuilderSliver', () {
    testWidgets('delegates snapshot states to LikeSliverBuilder',
        (tester) async {
      await tester.pumpWidget(
        _host(
          LikeStateResponseBuilderSliver<String>(
            response: LikeStateResponse<String>.success('snapshot'),
            onSuccess: (data, refreshing, swr) =>
                _textSliver('$data:$refreshing:$swr'),
          ),
        ),
      );
      expect(find.text('snapshot:false:false'), findsOneWidget);
    });
  });
}
