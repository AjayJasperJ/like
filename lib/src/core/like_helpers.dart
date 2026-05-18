import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'package:like/src/models/like_state_response.dart';

/// Central helper utilities for the LIKE networking engine.
/// Matches enterprise's ApiHelpers and NetworkUtils parity.
class LikeHelpers {
  /// Normalizes the base URL by removing the trailing slash if present.
  static String normalizeBaseUrl(String url) {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Generates a unique request key based on path and query parameters.
  static String generateRequestKey(String path, Map<String, dynamic>? query) {
    // Normalize path: ensure leading slash, remove trailing slash
    String normalizedPath = path.startsWith('/') ? path : '/$path';
    if (normalizedPath.endsWith('/') && normalizedPath.length > 1) {
      normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
    }

    if (query == null || query.isEmpty) return 'GET:$normalizedPath';

    final sortedKeys = query.keys.toList()..sort();
    final queryString = sortedKeys.map((k) => '$k=${query[k]}').join('&');
    return 'GET:$normalizedPath?$queryString';
  }

  /// Extracts the path from a request key.
  static String getPathFromKey(String key) {
    String path = key.replaceFirst('GET:', '');
    if (path.contains('?')) {
      path = path.split('?').first;
    }
    return path;
  }

  /// Global JSON parser for use with `compute`.
  static dynamic parseJson(String text) => jsonDecode(text);

  /// Defensively extracts the mapped model from the response.
  static T extract<T>(Response res, LikeModelFactory<T> factory) {
    if (res.extra.containsKey('mappedModel')) {
      final model = res.extra['mappedModel'];
      if (model is T) return model;
    }

    // Fallback: This means background mapping failed or was skipped
    return factory(res.data);
  }
}

/// Model for raw bytes multipart files.
class LikeMultipartFile {
  final String field;
  final Uint8List bytes;
  final String filename;
  final MediaType? contentType;

  const LikeMultipartFile({
    required this.field,
    required this.bytes,
    required this.filename,
    this.contentType,
  });
}
