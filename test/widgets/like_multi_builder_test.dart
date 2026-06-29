import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  group('LikeMultiBuilder Widget Tests', () {
    testWidgets('renders onSuccess when all responses are successful',
        (WidgetTester tester) async {
      final res1 = LikeStateResponse<String>.success('Hello');
      final res2 = LikeStateResponse<int>.success(42);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LikeMultiBuilder(
              observes: [() => res1, () => res2],
              onSuccess: (results, isRef, isSWR) =>
                  Text('${results[0]} - ${results[1]}'),
            ),
          ),
        ),
      );

      expect(find.text('Hello - 42'), findsOneWidget);
    });

    testWidgets('renders onLoading when at least one response is loading',
        (WidgetTester tester) async {
      final res1 = LikeStateResponse<String>.success('Hello');
      final res2 = LikeStateResponse<int>.loading();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LikeMultiBuilder(
              observes: [() => res1, () => res2],
              onSuccess: (results, isRef, isSWR) =>
                  Text('${results[0]} - ${results[1]}'),
              onLoading: () => const Text('Loading Multi...'),
            ),
          ),
        ),
      );

      expect(find.text('Loading Multi...'), findsOneWidget);
    });

    testWidgets(
        'renders onSuccess in CustomScrollView with LikeMultiSliverBuilder',
        (WidgetTester tester) async {
      final res1 = LikeStateResponse<String>.success('SliverHello');
      final res2 = LikeStateResponse<int>.success(100);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                LikeMultiSliverBuilder(
                  observes: [() => res1, () => res2],
                  onSuccess: (results, isRef, isSWR) => [
                    SliverToBoxAdapter(
                      child: Text('${results[0]} - ${results[1]}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('SliverHello - 100'), findsOneWidget);
    });
  });
}
