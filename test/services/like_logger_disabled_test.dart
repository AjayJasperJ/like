import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LikeLogger - Disabled File Logging', () {
    test('init sets _isInitialized and logs do not write to file', () async {
      LikeConstants.apply(LikeConfig(
        projectName: 'disabled_project',
        enableLogging: true,
        silentConsole: true,
        disableFileLogging: true,
      ));

      await LikeLogger.init();

      final logs = <String>[];
      final subscription = LikeLogger.logStream.listen((log) {
        logs.add(log);
      });

      await LikeLogger.log(
        level: LikeLogLevel.info,
        category: 'test',
        message: 'No file write',
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(logs.length, 1);
      final decoded = jsonDecode(logs.first);
      expect(decoded['message'], 'No file write');

      // File logging is disabled, so readLogs should be empty
      expect(await LikeLogger.readLogs(), isEmpty);

      await subscription.cancel();
    });
  });
}
