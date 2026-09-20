import 'dart:io' as io;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/core/like_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/app_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final testRoot = io.Directory(
    '${io.Directory.systemTemp.path}/like_app_cache_manager_test',
  );

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (methodCall) async {
      if (methodCall.method == 'getTemporaryDirectory' ||
          methodCall.method == 'getApplicationSupportDirectory') {
        return testRoot.path;
      }
      return null;
    });
  });

  setUp(() async {
    await testRoot.delete(recursive: true).catchError((_) => testRoot);
    await testRoot.create(recursive: true);
    LikeConstants.reset();
    LikeConstants.apply(LikeConfig(projectName: 'cache_test'));
    AppCacheManager.reset();
  });

  tearDown(() async {
    AppCacheManager.reset();
    LikeConstants.reset();
    await testRoot.delete(recursive: true).catchError((_) => testRoot);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('AppCacheManager', () {
    test('uses a versioned namespace that excludes legacy cache metadata', () {
      expect(AppCacheManager.key, 'cache_test_universalImageCache_v2');
      expect(AppCacheManager.key, isNot('cache_test_universalImageCache'));
    });

    test('putFile stores and returns the original bytes', () async {
      final manager = AppCacheManager();
      final bytes = Uint8List.fromList(<int>[0, 1, 2, 127, 128, 254, 255]);

      final stored = await manager.putFile(
        'https://example.test/image.png',
        bytes,
        fileExtension: 'png',
      );
      final cached = await manager.getFileFromCache(
        'https://example.test/image.png',
      );

      expect(await stored.readAsBytes(), bytes);
      expect(cached, isNotNull);
      expect(await cached!.file.readAsBytes(), bytes);
      expect(
        io.Directory('${testRoot.path}/${AppCacheManager.key}/decrypted')
            .existsSync(),
        isFalse,
      );
    });

    test('normalizeUrl strips query and fragment and normalizes host casing',
        () {
      expect(
        AppCacheUtils.normalizeUrl(
          ' HTTPS://Example.COM/avatar.png?v=123#profile ',
        ),
        'https://example.com/avatar.png',
      );
      expect(
        AppCacheUtils.normalizeUrl(
          ' HTTPS://Example.COM/avatar.png?token=secret#profile ',
        ),
        'https://example.com/avatar.png?token=secret',
      );
      expect(AppCacheUtils.normalizeUrl(''), '');
    });

    test('pruning removes the least recently used file first', () async {
      final directory = io.Directory('${testRoot.path}/${AppCacheManager.key}');
      await directory.create(recursive: true);
      final oldest = io.File('${directory.path}/oldest.bin');
      final newest = io.File('${directory.path}/newest.bin');
      await oldest.writeAsBytes(List<int>.filled(1024, 1));
      await newest.writeAsBytes(List<int>.filled(1024, 2));
      await oldest.setLastModified(DateTime(2020));
      await newest.setLastModified(DateTime(2021));

      await AppCacheManager().pruneCacheIfExceedsSize(
        maxMB: 0.0015,
        minMB: 0.001,
      );

      expect(await oldest.exists(), isFalse);
      expect(await newest.exists(), isTrue);
    });

    test('clearAll removes ordinary cache files', () async {
      final manager = AppCacheManager();
      final directory = io.Directory('${testRoot.path}/${AppCacheManager.key}');
      await directory.create(recursive: true);
      final file = io.File('${directory.path}/cached-image.bin');
      await file.writeAsBytes(<int>[1, 2, 3]);

      await manager.clearAll();

      expect(await file.exists(), isFalse);
    });
  });
}
