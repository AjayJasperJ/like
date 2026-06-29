import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');

  bool simulatePathError = false;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (methodCall) async {
    if (simulatePathError) {
      throw Exception('Simulated path provider error');
    }
    if (methodCall.method == 'getApplicationDocumentsDirectory') {
      return io.Directory.systemTemp.path;
    }
    return null;
  });

  FlutterExceptionHandler? originalOnError;
  bool Function(Object, StackTrace)? originalPlatformOnError;

  setUp(() {
    originalOnError = FlutterError.onError;
    originalPlatformOnError = PlatformDispatcher.instance.onError;
    simulatePathError = false;
    LikeConstants.reset();
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    PlatformDispatcher.instance.onError = originalPlatformOnError;
    LikeConstants.reset();
  });

  group('LikeLogger - Initialization and Basic Logging', () {
    test('1. init handles error when getApplicationDocumentsDirectory fails',
        () async {
      simulatePathError = true;

      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
      ));

      await LikeLogger.init();
      expect(await LikeLogger.readLogs(), isEmpty);
    });

    test('2. init initializes correctly and creates the log file', () async {
      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
      ));

      await LikeLogger.init();

      // Call init again to test the early return under the lock when _isInitialized is true
      await LikeLogger.init();

      final logFilePath =
          '${io.Directory.systemTemp.path}/shared_logger_project_api_log.txt';
      final file = io.File(logFilePath);
      expect(await file.exists(), isTrue);
    });

    test('3. log records messages to file and stream, and handles rotation',
        () async {
      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
      ));

      final logs = <String>[];
      final subscription = LikeLogger.logStream.listen((log) {
        logs.add(log);
      });

      await LikeLogger.clearLogs();

      await LikeLogger.log(
        level: LikeLogLevel.info,
        category: 'test_category',
        message: 'Hello, Logger!',
        details: {'key': 'value'},
      );

      await Future.delayed(const Duration(milliseconds: 50));

      expect(logs.length, 1);
      final decoded = jsonDecode(logs.first);
      expect(decoded['category'], 'test_category');
      expect(decoded['message'], 'Hello, Logger!');
      expect(decoded['details']['key'], 'value');

      final fileContent = await LikeLogger.readLogs();
      expect(fileContent, contains('Hello, Logger!'));

      // Test log rotation: write a large file
      final logFilePath =
          '${io.Directory.systemTemp.path}/shared_logger_project_api_log.txt';
      final file = io.File(logFilePath);
      final largeBytes = Uint8List(5 * 1024 * 1024 + 100);
      await file.writeAsBytes(largeBytes);

      // Log again, which should trigger rotation (truncation)
      await LikeLogger.log(
        level: LikeLogLevel.warning,
        category: 'test_category',
        message: 'Rotated message',
      );

      final rotatedContent = await LikeLogger.readLogs();
      expect(rotatedContent.length, lessThan(1000));
      expect(rotatedContent, contains('Rotated message'));

      await subscription.cancel();
    });

    test('4. log disk error is caught and printed, then restored', () async {
      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
      ));

      final logFilePath =
          '${io.Directory.systemTemp.path}/shared_logger_project_api_log.txt';
      final logFile = io.File(logFilePath);

      // Delete the file and create a directory at its path to trigger a FileSystemException
      if (await logFile.exists()) {
        await logFile.delete();
      }

      final fileDir = io.Directory(logFilePath);
      await fileDir.create(recursive: true);

      await LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'test_category',
        message: 'This will trigger disk write exception',
      );

      // Restore directory back to file for subsequent tests
      await fileDir.delete(recursive: true);
      await logFile.create(recursive: true);
    });

    test('5. log console output options and styles', () async {
      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
        silentSyncLogs: true,
      ));

      await LikeLogger.log(
        level: LikeLogLevel.info,
        category: 'sync',
        message: 'Sync message',
      );

      await LikeLogger.log(
        level: LikeLogLevel.warning,
        category: 'custom',
        message: 'Warning message',
        details: {'non_encodable': io.Directory.systemTemp},
      );

      await LikeLogger.log(
        level: LikeLogLevel.debug,
        category: 'custom',
        message: 'Debug message',
      );
    });

    test('6. logApi outputs compact and full modes correctly', () async {
      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
        compactApiLogs: true,
      ));

      await LikeLogger.logApi(
        '/users',
        success: true,
        statusCode: 200,
        requestId: 'req_1',
        method: 'GET',
      );

      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
        compactApiLogs: false,
      ));

      await LikeLogger.logApi(
        '/users',
        success: false,
        statusCode: 500,
        requestId: 'req_2',
        method: 'POST',
        requestHeaders: {'Content-Type': 'application/json'},
        responseHeaders: {'Server': 'nginx'},
        requestBody: {'name': 'John'},
        requestFields: {'field': 'value'},
        requestQuery: {'q': 'search'},
        response: 'Internal Server Error',
        statusText: 'SERVER_CRASH',
      );
    });

    test('7. logApiRequest respects silentApiStartLogs config', () async {
      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
        silentApiStartLogs: true,
      ));

      final logs = <String>[];
      final subscription = LikeLogger.logStream.listen((log) {
        logs.add(log);
      });

      await LikeLogger.logApiRequest(
        '/users',
        requestId: 'req_start_1',
      );

      expect(logs, isEmpty);

      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
        silentApiStartLogs: false,
      ));

      await LikeLogger.logApiRequest(
        '/users',
        requestId: 'req_start_2',
        method: 'GET',
        headers: {'Auth': 'Bearer token'},
        body: {'id': 1},
        fields: {'f': 'v'},
        query: {'limit': 10},
      );

      await Future.delayed(const Duration(milliseconds: 50));
      expect(logs.length, 1);
      expect(logs.first, contains('req_start_2'));

      await subscription.cancel();
    });

    test(
        '8. initGlobalErrorHandling captures and logs Flutter and platform errors',
        () async {
      LikeConstants.apply(LikeConfig(
        projectName: 'shared_logger_project',
        enableLogging: true,
        silentConsole: false,
        verboseLogging: true,
      ));

      final logs = <String>[];
      final subscription = LikeLogger.logStream.listen((log) {
        logs.add(log);
      });

      LikeLogger.initGlobalErrorHandling();

      final flutterErrorDetails = FlutterErrorDetails(
        exception: Exception('Test Flutter Exception'),
        library: 'test_library',
        context: DiagnosticsNode.message('testing error handler'),
        stack: StackTrace.current,
      );
      FlutterError.onError!(flutterErrorDetails);

      final handled = PlatformDispatcher.instance.onError!(
        Exception('Test Platform Exception'),
        StackTrace.current,
      );
      expect(handled, isTrue);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(logs.length, 2);
      expect(logs[0], contains('Test Flutter Exception'));
      expect(logs[1], contains('Test Platform Exception'));

      await subscription.cancel();
    });

    test('9. readLogs and clearLogs when file does not exist', () async {
      final logFilePath =
          '${io.Directory.systemTemp.path}/shared_logger_project_api_log.txt';
      final file = io.File(logFilePath);

      // Delete the file at the very end to cover the "file does not exist" path
      if (await file.exists()) {
        await file.delete();
      }

      expect(await LikeLogger.readLogs(), isEmpty);

      await LikeLogger.clearLogs();
    });
  });
}
