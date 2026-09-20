import 'package:like/like.dart';

// Re-export JsonParse and jsonMap from package:like
export 'package:like/like.dart' show JsonParse, jsonMap;

// Backward-compatibility top-level functions
DateTime? parseNullableDateTime(Object? value) =>
    JsonParse.nullableDateTime(value);
DateTime parseDateTime(Object? value, {DateTime? fallback}) =>
    JsonParse.dateTime(value, fallback: fallback);
