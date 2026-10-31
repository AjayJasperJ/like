import 'dart:convert';

/// Sanitizes diagnostic copies only; application responses are never modified.
class LikeRedaction {
  static const masked = '[REDACTED]';
  static const omitted = '[PAYLOAD OMITTED]';
  static const _keys = <String>{
    'authorization',
    'proxyauthorization',
    'cookie',
    'setcookie',
    'password',
    'passwd',
    'secret',
    'token',
    'accesstoken',
    'refreshtoken',
    'idtoken',
    'apikey',
    'xapikey',
    'email',
    'phone',
    'creditcard',
    'cardnumber',
    'cvv',
    'clientsecret',
    'sessionid',
    'ssn',
    'privatekey',
  };

  static Object? apiPayload(Object? value, {required bool release}) =>
      release ? omitted : sanitize(value);

  static String message(String value) => value
      .replaceAllMapped(
          RegExp(r'https?://[^\s]+'), (match) => endpoint(match.group(0)!))
      .replaceAll(RegExp(r'Bearer\s+[^\s,;]+', caseSensitive: false),
          'Bearer [REDACTED]');

  static String _normalize(String key) =>
      key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

  static Object? sanitize(Object? value,
      {Iterable<String> sensitiveKeys = const []}) {
    final keys = {..._keys, ...sensitiveKeys.map(_normalize)};
    return _sanitize(value, keys, 0);
  }

  static Object? _sanitize(Object? value, Set<String> keys, int depth) {
    if (depth > 20) return omitted;
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): keys.contains(_normalize(entry.key.toString()))
              ? masked
              : _sanitize(entry.value, keys, depth + 1),
      };
    }
    if (value is Iterable) {
      return value.map((item) => _sanitize(item, keys, depth + 1)).toList();
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map || decoded is List) {
          return _sanitize(decoded, keys, depth + 1);
        }
      } catch (_) {}
      // Opaque strings cannot reliably be inspected for secrets.
      return omitted;
    }
    if (value == null || value is num || value is bool) return value;
    // Never call arbitrary toString() on payloads (e.g. multipart objects).
    return omitted;
  }

  /// Drops URL queries/fragments and userinfo before diagnostic publication.
  static String endpoint(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return omitted;
    final path = uri.path;
    if (!uri.hasScheme) return path;
    return Uri(
            scheme: uri.scheme,
            host: uri.host,
            port: uri.hasPort ? uri.port : null,
            path: path)
        .toString();
  }
}
