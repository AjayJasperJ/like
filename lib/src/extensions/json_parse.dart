import 'package:flutter/material.dart';

/// Comprehensive utility class for safe JSON field parsing.

abstract final class JsonParse {
  /// Converts dynamic value to `Map<String, dynamic>` safely.
  static Map<String, dynamic> map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  /// Parses a String safely.
  static String string(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  /// Parses an int safely.
  static int integer(Object? value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    if (value == null) return fallback;
    return int.tryParse(value.toString().trim()) ?? fallback;
  }

  /// Parses a double safely.
  static double decimal(Object? value, {double fallback = 0.0}) {
    if (value is num) return value.toDouble();
    if (value == null) return fallback;
    return double.tryParse(value.toString().trim()) ?? fallback;
  }

  /// Parses a num safely.
  static num number(Object? value, {num fallback = 0}) {
    if (value is num) return value;
    if (value == null) return fallback;
    return num.tryParse(value.toString().trim()) ?? fallback;
  }

  /// Parses a boolean safely.
  static bool boolean(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value == null) return fallback;
    final str = value.toString().trim().toLowerCase();
    if (str == 'true' || str == '1' || str == 'yes') return true;
    if (str == 'false' || str == '0' || str == 'no') return false;
    return fallback;
  }

  /// Parses a nullable DateTime safely.
  static DateTime? nullableDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    return DateTime.tryParse(str);
  }

  /// Parses a DateTime safely with optional fallback.
  static DateTime dateTime(Object? value, {DateTime? fallback}) {
    return nullableDateTime(value) ?? fallback ?? DateTime.now();
  }

  /// Parses a `List<T>` safely with optional item parser. Defaults to an empty list.
  static List<T> list<T>(
    Object? value, [
    T Function(dynamic item)? itemParser,
  ]) {
    if (value is! List) return const [];
    if (itemParser != null) {
      return value.map((item) => itemParser(item)).toList();
    }
    if (T == String) {
      return value.map((item) => item?.toString() ?? '').cast<T>().toList();
    }
    return value.whereType<T>().toList();
  }

  /// Parses a `List<String>` safely. Defaults to an empty list.
  static List<String> stringList(Object? value) => list<String>(value);

  /// Parses a Color safely from hex string (e.g. '#FF0000', '0xFFFF0000') or int.
  static Color? color(Object? value) {
    if (value == null) return null;
    if (value is Color) return value;
    if (value is int) return Color(value);
    var hex = value.toString().trim().replaceAll('#', '');
    if (hex.startsWith('0x') || hex.startsWith('0X')) {
      hex = hex.substring(2);
    }
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    final colorInt = int.tryParse(hex, radix: 16);
    if (colorInt == null) return null;
    return Color(colorInt);
  }
}

// ignore: unintended_html_in_doc_comment
/// Helper function to safely cast/convert dynamic value to `Map<String, dynamic>`.
Map<String, dynamic> jsonMap(Object? value) => JsonParse.map(value);
