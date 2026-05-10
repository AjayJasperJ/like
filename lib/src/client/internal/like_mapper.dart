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

    // Rough estimate of size for typical JSON structures (Map/List)
    // For simplicity, we just use compute if it's a Map or List.
    // In production, we could check string length if it was raw JSON.
    if (data is Map || data is List) {
      // We use compute for mapping to models to keep the main thread smooth.
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

  static T _parseInIsolate<T>(_MapperTask<T> task) {
    return task.parser(task.data);
  }
}

class _MapperTask<T> {
  final dynamic data;
  final T Function(dynamic) parser;
  _MapperTask(this.data, this.parser);
}
