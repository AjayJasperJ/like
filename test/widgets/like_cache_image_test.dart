import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  testWidgets('LikeCacheImage applies ClipRRect when borderRadius is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LikeCacheImage(
            imageUrl: 'https://example.com/avatar.jpg',
            width: 80,
            height: 80,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );

    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(16));
  });
}
