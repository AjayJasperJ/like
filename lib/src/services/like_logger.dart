import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:like/src/core/like_constants.dart';

enum LikeLogLevel { info, warning, error, debug }

/// Professional logging service for the LIKE networking engine.
/// Supports disk logging, tiered console levels, and api event tracking.
/// Matches the exact logic and feature set of enterprise's LoggerService.
class LikeLogger {
  static File? _logFile;
  static final _lock = Lock();
  static final _logStream = StreamController<String>.broadcast();
  static Stream<String> get logStream => _logStream.stream;
  static const int _maxLogSize = 1024 * 1024 * 5; // 5MB

  static bool _isInitialized = false;

  /// Initializes the logging system.
  static Future<void> init() async {
    if (LikeConstants.disableFileLogging) {
      _isInitialized = true;
      return;
    }

    await _lock.synchronized(() async {
      if (_isInitialized) return;
      try {
        final dir = await getApplicationDocumentsDirectory();
        _logFile = File('${dir.path}/like_api_log.txt');
        if (!await _logFile!.exists()) {
          await _logFile!.create(recursive: true);
        }
        _isInitialized = true;
        debugPrint('[LikeLogger] Initialized at: ${_logFile!.path}');
      } catch (e) {
        debugPrint('[LikeLogger] Initialization failed: $e');
      }
    });
  }

  static Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }

  /// Logs a generic message with metadata.
  static Future<void> log({
    required LikeLogLevel level,
    required String category,
    required String message,
    Map<String, dynamic>? details,
  }) async {
    await _ensureInitialized();

    final timestampStr = DateTime.now().toIso8601String();
    final entry = {
      'timestamp': timestampStr,
      'level': level.name,
      'category': category,
      'message': message,
      if (details != null && details.isNotEmpty) 'details': details,
    };

    final jsonString = jsonEncode(entry, toEncodable: (o) => o.toString());
    await _writeLine(jsonString);
    _printToConsole(level, category, message, details, timestampStr);
  }

  /// Specialized API event logging.
  static Future<void> logApi(
    String endpoint, {
    required bool success,
    dynamic response,
    int? statusCode,
    String? requestId,
    String? method,
    dynamic requestHeaders,
    dynamic responseHeaders,
    dynamic requestBody,
    bool? shrinkEndpointOnly,
    String? statusText,
  }) async {
    final shouldShrink = shrinkEndpointOnly ?? LikeConstants.compactApiLogs;
    final finalStatus = statusText ?? (success ? 'SUCCESS' : 'FAILED');

    final message = shouldShrink
        ? '$endpoint ${statusCode != null ? '[$statusCode] ' : ''}: $finalStatus'
        : '$endpoint | $finalStatus';

    await log(
      level: success ? LikeLogLevel.info : LikeLogLevel.error,
      category: 'api',
      message: message,
      details: {
        'success': success,
        'requestId': ?requestId,
        'statusCode': ?statusCode,
        'method': ?method,
        'requestHeaders': ?requestHeaders,
        'responseHeaders': ?responseHeaders,
        'requestBody': ?requestBody,
        if (response != null) 'response': response.toString(),
        if (shouldShrink) 'shrink': true,
        'status': ?statusText,
      },
    );
  }

  /// Logs the start of an API request.
  static Future<void> logApiRequest(
    String endpoint, {
    required String requestId,
    String? method,
    dynamic headers,
    dynamic body,
  }) async {
    if (LikeConstants.silentApiStartLogs) return;

    await log(
      level: LikeLogLevel.info,
      category: 'api',
      message: '$endpoint | STARTED',
      details: {
        'requestId': requestId,
        'method': ?method,
        'headers': ?headers,
        'body': ?body,
      },
    );
  }

  static Future<void> _writeLine(String line) async {
    _logStream.add(line);

    if (LikeConstants.disableFileLogging) return;

    await _lock.synchronized(() async {
      if (_logFile == null) return;
      try {
        if (await _logFile!.length() > _maxLogSize) {
          await _logFile!.writeAsString('', mode: FileMode.write);
        }
        await _logFile!.writeAsString(
          '$line\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (e) {
        debugPrint('[LikeLogger] Disk log error: $e');
      }
    });
  }

  static void _printToConsole(
    LikeLogLevel level,
    String category,
    String message,
    Map<String, dynamic>? details,
    String fullTimestamp,
  ) {
    if (!kDebugMode || LikeConstants.silentConsole) return;

    if (LikeConstants.silentSyncLogs &&
        ['sync', 'background_sync', 'offline_sync'].contains(category)) {
      return;
    }

    final isApi = category == 'api';
    final shouldShrink = LikeConstants.compactApiLogs;

    final colorCode = level == LikeLogLevel.error
        ? '31'
        : (level == LikeLogLevel.warning ? '33' : '32');
    final color = '\x1B[${colorCode}m';
    const reset = '\x1B[0m';
    final time = fullTimestamp.contains('T')
        ? fullTimestamp.split('T')[1].substring(0, 8)
        : fullTimestamp;

    debugPrint('$color[$time][$category] $message$reset');

    if (details != null && details.isNotEmpty && !(isApi && shouldShrink)) {
      try {
        final prettyJson = const JsonEncoder.withIndent('  ').convert(details);
        debugPrint('$color$prettyJson$reset');
      } catch (e) {
        debugPrint('$color$details$reset');
      }
    }
  }

  /// Sets up global Flutter and platform error tracking.
  static void initGlobalErrorHandling() {
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) FlutterError.dumpErrorToConsole(details);
      log(
        level: LikeLogLevel.error,
        category: 'flutter_error',
        message: details.exceptionAsString(),
        details: {
          'library': details.library,
          'context': details.context?.toString(),
          'stack': details.stack?.toString(),
        },
      );
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      log(
        level: LikeLogLevel.error,
        category: 'app_error',
        message: error.toString(),
        details: {'stack': stack.toString()},
      );
      return true;
    };
  }

  static Future<String> readLogs() async {
    await _ensureInitialized();
    if (await _logFile!.exists()) {
      return await _logFile!.readAsString();
    }
    return '';
  }

  static Future<void> clearLogs() async {
    await _ensureInitialized();
    if (await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  }
}
