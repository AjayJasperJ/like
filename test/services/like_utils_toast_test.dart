import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:like/src/services/like_utils.dart';

void main() {
  setUp(LikeConstants.reset);
  tearDown(LikeConstants.reset);

  testWidgets('cache and SWR hooks replace their default SnackBars', (
    tester,
  ) async {
    final cacheMessages = <String>[];
    final swrMessages = <String>[];
    LikeConstants.apply(
      LikeConstants.current.copyWith(
        toastConfig: LikeToastConfig(
          cacheUse: cacheMessages.add,
          swrUse: swrMessages.add,
        ),
      ),
    );

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    LikeUtils.notifyCacheUse(context);
    LikeUtils.notifySwrUse(context);
    await tester.pump();

    expect(cacheMessages, <String>['You are viewing offline data']);
    expect(swrMessages, <String>['Loading fresh data in background...']);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('cache and SWR notifications fall back to SnackBars', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    LikeUtils.notifyCacheUse(context);
    await tester.pump();
    expect(find.text('You are viewing offline data'), findsOneWidget);

    ScaffoldMessenger.of(context).clearSnackBars();
    await tester.pumpAndSettle();
    LikeUtils.notifySwrUse(context);
    await tester.pump();
    expect(find.text('Loading fresh data in background...'), findsOneWidget);
  });
}
