import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  tearDown(LikeConstants.reset);

  group('LikeCacheImage', () {
    testWidgets('uses the custom empty URL error builder', (tester) async {
      Object? receivedError;
      String? receivedUrl;

      await tester.pumpWidget(
        _host(
          LikeCacheImage(
            imageUrl: '   ',
            errorWidget: (context, url, error) {
              receivedUrl = url;
              receivedError = error;
              return const Text('empty error');
            },
          ),
        ),
      );

      expect(find.text('empty error'), findsOneWidget);
      expect(receivedUrl, '   ');
      expect(receivedError, 'Empty URL');
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('uses the default empty URL error widget', (tester) async {
      await tester.pumpWidget(
        _host(const LikeCacheImage(imageUrl: '')),
      );

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('forwards native cache image configuration', (tester) async {
      const url = 'https://example.com/images/avatar.png?size=large';
      const color = Color(0xFF123456);
      const fadeIn = Duration(milliseconds: 125);
      const fadeOut = Duration(milliseconds: 250);
      Widget placeholder(BuildContext context, String imageUrl) =>
          const Text('placeholder');
      Widget errorWidget(
              BuildContext context, String imageUrl, dynamic error) =>
          const Text('error');
      Widget imageBuilder(BuildContext context, ImageProvider provider) =>
          const Text('image');

      await tester.pumpWidget(
        _host(
          LikeCacheImage(
            imageUrl: url,
            fit: BoxFit.contain,
            width: 120,
            height: 80,
            placeholder: placeholder,
            errorWidget: errorWidget,
            imageBuilder: imageBuilder,
            memCacheWidth: 240,
            memCacheHeight: 160,
            fadeInDuration: fadeIn,
            fadeOutDuration: fadeOut,
            normalizeUrl: false,
            color: color,
          ),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.imageUrl, url);
      expect(image.cacheKey, isNull);
      expect(image.fit, BoxFit.contain);
      expect(image.width, 120);
      expect(image.height, 80);
      expect(image.memCacheWidth, 240);
      expect(image.memCacheHeight, 160);
      expect(image.fadeInDuration, fadeIn);
      expect(image.fadeOutDuration, fadeOut);
      expect(image.placeholder, same(placeholder));
      expect(image.errorWidget, same(errorWidget));
      expect(image.imageBuilder, same(imageBuilder));
      expect(image.color, color);
      expect(image.cacheManager, isNotNull);
    });

    testWidgets('normalizes the cache key by default', (tester) async {
      const url = 'https://example.com/image.png?token=secret';
      await tester.pumpWidget(
        _host(const LikeCacheImage(imageUrl: url)),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.cacheKey, isNotNull);
      expect(image.cacheKey, isNotEmpty);
    });
  });
}
