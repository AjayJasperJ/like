import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Internal utility to generate and compare content hashes.
/// Used to detect if data has actually changed compared to cache,
/// preventing unnecessary UI rebuilds or heavy processing.
class LikeHash {
  static final LikeHash _instance = LikeHash._internal();
  factory LikeHash() => _instance;
  LikeHash._internal();

  final Map<String, String> _hashes = {};

  /// Generates a deterministic MD5 hash of the given data.
  String generate(dynamic data) {
    if (data == null) return '';

    String stringToHash;
    if (data is String) {
      stringToHash = data;
    } else {
      try {
        // jsonEncode is usually deterministic in Dart for Map/List
        stringToHash = jsonEncode(data);
      } catch (e) {
        stringToHash = data.toString();
      }
    }

    return md5.convert(utf8.encode(stringToHash)).toString();
  }

  /// Checks if the data matches the stored hash for a key.
  bool isSame(String key, dynamic data) {
    final newHash = generate(data);
    return _hashes[key] == newHash;
  }

  /// Updates the hash and returns [true] if the data has changed.
  bool updateIfChanged(String key, dynamic data) {
    final newHash = generate(data);
    final oldHash = _hashes[key];

    if (oldHash == newHash) return false;

    _hashes[key] = newHash;
    return true;
  }

  void remove(String key) => _hashes.remove(key);

  void clear() => _hashes.clear();
}
