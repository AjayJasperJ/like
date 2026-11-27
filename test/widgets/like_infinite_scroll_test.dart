import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  testWidgets(
    'LikeInfiniteScroll triggers onLoadMore near bottom and respects hasMore',
    (tester) async {
      var loadMoreCalls = 0;
      var hasMore = true;
      final controller = ScrollController();

      Widget buildTree() => MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return LikeInfiniteScroll(
                    hasMore: hasMore,
                    threshold: 100,
                    onLoadMore: () => loadMoreCalls++,
                    child: ListView.builder(
                      controller: controller,
                      itemCount: 30,
                      itemExtent: 50,
                      itemBuilder: (_, index) => Text('Item $index'),
                    ),
                  );
                },
              ),
            ),
          );

      await tester.pumpWidget(buildTree());
      expect(loadMoreCalls, 0);

      // Scroll near the bottom (extentAfter <= 100)
      controller.jumpTo(controller.position.maxScrollExtent - 50);
      await tester.pump();
      expect(loadMoreCalls, 1);

      // Should not trigger when hasMore == false
      hasMore = false;
      await tester.pumpWidget(buildTree());
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(loadMoreCalls, 1);

      controller.dispose();
    },
  );

  testWidgets(
    'LikeInfiniteScroll ignores horizontal scrolls, nested scrollables, and inactive routes (bottom sheets)',
    (tester) async {
      var loadMoreCalls = 0;
      final horizontalController = ScrollController();
      final outerController = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LikeInfiniteScroll(
              threshold: 100,
              onLoadMore: () => loadMoreCalls++,
              child: ListView(
                controller: outerController,
                children: [
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      controller: horizontalController,
                      scrollDirection: Axis.horizontal,
                      itemCount: 20,
                      itemExtent: 80,
                      itemBuilder: (_, i) => Text('H$i'),
                    ),
                  ),
                  for (var i = 0; i < 20; i++)
                    SizedBox(height: 50, child: Text('V$i')),
                ],
              ),
            ),
          ),
        ),
      );

      // Horizontal nested list scroll must NOT trigger vertical load-more
      horizontalController.jumpTo(horizontalController.position.maxScrollExtent);
      await tester.pump();
      expect(loadMoreCalls, 0);

      // Open a modal bottom sheet over the screen: ModalRoute.isCurrent is false
      showModalBottomSheet<void>(
        context: tester.element(find.byType(Scaffold)),
        builder: (_) => const SizedBox(height: 200, child: Text('Sheet')),
      );
      await tester.pumpAndSettle();

      outerController.jumpTo(outerController.position.maxScrollExtent);
      await tester.pump();
      expect(loadMoreCalls, 0);

      horizontalController.dispose();
      outerController.dispose();
    },
  );
}
