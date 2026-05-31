import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:like/like.dart';

class TestNotifier extends ChangeNotifier {
  LikeStateResponse<String> _response = LikeStateResponse<String>.loading();
  LikeStateResponse<String> get response => _response;

  void setResponse(LikeStateResponse<String> res) {
    _response = res;
    notifyListeners();
  }
}

void main() {
  group('LikeSelector Widget Tests', () {
    testWidgets('renders SUCCESS state correctly through LikeSelector', (WidgetTester tester) async {
      final notifier = TestNotifier();

      await tester.pumpWidget(
        ChangeNotifierProvider<TestNotifier>.value(
          value: notifier,
          child: MaterialApp(
            home: Scaffold(
              body: LikeSelector<TestNotifier, String>(
                selector: (context, n) => n.response,
                onSuccess: (data, isRef, isSWR) => Text(data),
                onLoading: () => const Text('Loading...'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Loading...'), findsOneWidget);

      notifier.setResponse(LikeStateResponse<String>.success('Hello Selector'));
      await tester.pump();

      expect(find.text('Hello Selector'), findsOneWidget);
    });

    testWidgets('renders SUCCESS state correctly through LikeSelectorSliver', (WidgetTester tester) async {
      final notifier = TestNotifier();

      await tester.pumpWidget(
        ChangeNotifierProvider<TestNotifier>.value(
          value: notifier,
          child: MaterialApp(
            home: Scaffold(
              body: CustomScrollView(
                slivers: [
                  LikeSelectorSliver<TestNotifier, String>(
                    selector: (n) => n.response,
                    onSuccess: (data, isRef, isSWR) => [
                      SliverToBoxAdapter(child: Text(data)),
                    ],
                    onLoading: () => [
                      const SliverToBoxAdapter(child: Text('Sliver Loading...')),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Sliver Loading...'), findsOneWidget);

      notifier.setResponse(LikeStateResponse<String>.success('Hello Sliver Selector'));
      await tester.pump();

      expect(find.text('Hello Sliver Selector'), findsOneWidget);
    });
  });
}
