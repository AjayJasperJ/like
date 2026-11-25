import 'package:flutter/foundation.dart';

/// Internal utility for high-performance data mapping using isolates.
class LikeMapper {
  /// Maps data to a model, using [compute] if the data size is likely large.
  /// thresholdKB is used to decide if the operation should be offloaded to an isolate.
  static Future<T> map<T>(
    dynamic data,
    T Function(dynamic) parser, {
    int thresholdKB = 50,
  }) async {
    // If data is null or threshold is negative (force main thread), just parse.
    if (data == null || thresholdKB < 0) {
      return parser(data);
    }

    final thresholdBytes = thresholdKB * 1024;
    if ((data is Map || data is List) &&
        _exceedsThreshold(data, thresholdBytes)) {
      // We use compute for large payloads to keep the main thread smooth.
      // Note: parser must be a top-level or static function to work with compute.
      try {
        return await compute(_parseInIsolate, _MapperTask(data, parser));
      } catch (e) {
        // Fallback to main thread if compute fails (e.g. non-sendable parser)
        return parser(data);
      }
    }

    return parser(data);
  }

  static bool _exceedsThreshold(dynamic value, int thresholdBytes) {
    if (thresholdBytes <= 0) return true;
    var estimated = 0;
    bool visit(dynamic node, int depth) {
      if (depth > 16) return false;
      if (node is String) {
        estimated += node.length + 2;
      } else if (node is Map) {
        estimated += 2;
        for (final entry in node.entries) {
          estimated += entry.key.toString().length + 4;
          if (estimated >= thresholdBytes) return true;
          if (visit(entry.value, depth + 1)) return true;
        }
      } else if (node is List) {
        estimated += 2;
        for (final item in node) {
          estimated += 2;
          if (estimated >= thresholdBytes) return true;
          if (visit(item, depth + 1)) return true;
        }
      } else {
        estimated += 8;
      }
      return estimated >= thresholdBytes;
    }

    return visit(value, 0);
  }

  static T _parseInIsolate<T>(_MapperTask<T> task) {
    return task.parser(task.data);
  }
}

class _MapperTask<T> {
  final dynamic data;
  final T Function(dynamic) parser;
  _MapperTask(this.data, this.parser);
}
