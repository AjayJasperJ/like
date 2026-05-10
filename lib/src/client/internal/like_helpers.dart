import 'dart:convert';

/// Internal utility class for URL normalization and request key generation.
class LikeHelpers {
  /// Normalizes the base URL by removing the trailing slash if present.
  static String normalizeBaseUrl(String url) {
    if (url.endsWith('/')) {
      return url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Generates a unique request key based on method, path, and query parameters.
  static String generateRequestKey(
    String method,
    String path,
    Map<String, dynamic>? query,
  ) {
    // Normalize path: ensure leading slash, remove trailing slash
    String normalizedPath = path.startsWith('/') ? path : '/$path';
    if (normalizedPath.endsWith('/') && normalizedPath.length > 1) {
      normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
    }

    if (query == null || query.isEmpty) return '$method:$normalizedPath';

    final sortedKeys = query.keys.toList()..sort();
    final queryString = sortedKeys.map((k) => '$k=${query[k]}').join('&');
    return '$method:$normalizedPath?$queryString';
  }

  /// Global JSON parser for use with background isolates.
  static dynamic parseJson(String text) => jsonDecode(text);
}
