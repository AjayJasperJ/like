import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/services/like_utils.dart';
import 'package:toastification/toastification.dart';

void main() {
  group('LikeUtils', () {
    test('castToMapStringDynamic converts keys to String and maps nested values', () {
      final dynamic inputMap = {
        1: 'a',
        'list': [
          {2: 'b'}
        ],
        'nested': {
          3: 'c',
        }
      };

      final result = LikeUtils.castToMapStringDynamic(inputMap);

      expect(result, isA<Map<String, dynamic>>());
      expect(result['1'], 'a');
      expect(result['list'], isA<List>());
      expect(result['list'][0], isA<Map<String, dynamic>>());
      expect(result['list'][0]['2'], 'b');
      expect(result['nested'], isA<Map<String, dynamic>>());
      expect(result['nested']['3'], 'c');
    });

    test('castToMapStringDynamic returns primitive inputs unchanged', () {
      expect(LikeUtils.castToMapStringDynamic(123), 123);
      expect(LikeUtils.castToMapStringDynamic('hello'), 'hello');
      expect(LikeUtils.castToMapStringDynamic(null), null);
    });

    testWidgets('showToast and cache/swr notification helpers run without exception', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ToastificationWrapper(
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  return Column(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          LikeUtils.showToast(
                            message: 'Test Message',
                            submessage: 'Submessage',
                            type: LikeToastStyle.success,
                            context: context,
                          );
                          LikeUtils.showToast(
                            message: 'Test Message 2',
                            type: LikeToastStyle.error,
                            context: context,
                          );
                          LikeUtils.showToast(
                            message: 'Test Message 3',
                            type: LikeToastStyle.warning,
                            context: context,
                          );
                          LikeUtils.showToast(
                            message: 'Test Message 4',
                            type: LikeToastStyle.info,
                            context: context,
                          );
                          LikeUtils.notifyCacheUse(context);
                          LikeUtils.notifySwrUse(context);
                        },
                        child: const Text('Show Toast'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Toast'));
      await tester.pumpAndSettle();
      
      // Verify Toastification has some child displayed (like the message text)
      expect(find.text('Test Message'), findsOneWidget);

      // Dismiss all to clear pending auto-close timers
      toastification.dismissAll();
      await tester.pumpAndSettle();
    });
  });
}
