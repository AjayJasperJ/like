import 'dart:io' as io;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/services/app_cache_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Setup path provider mock channel
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (methodCall) async {
    if (methodCall.method == 'getTemporaryDirectory') {
      return io.Directory.systemTemp.path;
    }
    if (methodCall.method == 'getApplicationSupportDirectory') {
      return io.Directory.systemTemp.path;
    }
    return null;
  });

  group('AppCacheManager', () {
    late AppCacheManager cacheManager;

    setUp(() {
      cacheManager = AppCacheManager();
    });

    test('clearAll should remove both encrypted and decrypted files from disk', () async {
      final tempDir = io.Directory.systemTemp;
      final cacheDir = io.Directory('${tempDir.path}/${AppCacheManager.key}');
      final decryptedDir = io.Directory('${cacheDir.path}/decrypted');

      // Ensure directories exist
      await cacheDir.create(recursive: true);
      await decryptedDir.create(recursive: true);

      // Write dummy files
      final encryptedFile = io.File('${cacheDir.path}/dummy_encrypted.file');
      await encryptedFile.writeAsString('encrypted_data');

      final decryptedFile = io.File('${decryptedDir.path}/dummy_decrypted.file');
      await decryptedFile.writeAsString('decrypted_data');

      expect(await encryptedFile.exists(), isTrue);
      expect(await decryptedFile.exists(), isTrue);

      // Clear all
      await cacheManager.clearAll();

      // Assert decrypted files are deleted
      expect(await decryptedFile.exists(), isFalse);
      // Assert encrypted files are deleted
      expect(await encryptedFile.exists(), isFalse);
    });
  });
}
