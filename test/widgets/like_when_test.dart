import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  group('LikeWhen Widget Tests', () {
    testWidgets('renders onSuccess builder when state is success',
        (WidgetTester tester) async {
      final response = LikeStateResponse<String>.success('Hello World');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LikeWhen<String>(
              response: response,
              onSuccess: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.text('Hello World'), findsOneWidget);
    });

    testWidgets('renders onLoading builder when state is loading',
        (WidgetTester tester) async {
      final response = LikeStateResponse<String>.loading();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LikeWhen<String>(
              response: response,
              onSuccess: (data) => Text(data),
              onLoading: () => const Text('Loading...'),
            ),
          ),
        ),
      );

      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('renders onError builder when state is error',
        (WidgetTester tester) async {
      final error =
          LikeError(message: 'Network Failure', type: LikeApiErrorType.network);
      final response = LikeStateResponse<String>.error(error);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LikeWhen<String>(
              response: response,
              onSuccess: (data) => Text(data),
              onError: (err) => Text(err.message),
            ),
          ),
        ),
      );

      expect(find.text('Network Failure'), findsOneWidget);
    });
  });
}
