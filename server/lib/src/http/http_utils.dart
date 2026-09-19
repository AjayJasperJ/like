import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../core/api_exception.dart';

Response jsonResponse(Object? body, {int status = HttpStatus.ok}) => Response(
      status,
      body: jsonEncode(body),
      headers: const {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
      },
    );

Future<Map<String, Object?>> readJsonObject(Request request) async {
  final contentType = request.headers[HttpHeaders.contentTypeHeader] ?? '';
  if (!contentType.toLowerCase().contains('application/json')) {
    throw ApiException(415, 'Content-Type must be application/json');
  }

  final text = await request.readAsString();
  if (text.trim().isEmpty) {
    throw ApiException(400, 'JSON body is required');
  }

  try {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(400, 'JSON body must be an object');
    }
    return Map<String, Object?>.from(decoded);
  } on FormatException {
    throw ApiException(400, 'Malformed JSON body');
  }
}

String requiredString(
  Map<String, Object?> body,
  String field, {
  int minimumLength = 1,
}) {
  final value = body[field];
  if (value is! String || value.trim().length < minimumLength) {
    throw ApiException(
      422,
      '$field must be a string with at least $minimumLength characters',
    );
  }
  return value.trim();
}

int positiveInt(
  String? raw, {
  int? fallback,
  required String name,
  int? maximum,
}) {
  if (raw == null && fallback != null) return fallback;
  final value = int.tryParse(raw ?? '');
  if (value == null || value < 1 || (maximum != null && value > maximum)) {
    final range =
        maximum == null ? 'a positive integer' : 'between 1 and $maximum';
    throw ApiException(400, '$name must be $range');
  }
  return value;
}

bool? optionalBool(String? raw, String name) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.toLowerCase() == 'true') return true;
  if (raw.toLowerCase() == 'false') return false;
  throw ApiException(400, '$name must be true or false');
}

int authenticatedUserId(Request request) {
  final userId = request.context['userId'];
  if (userId is! int) {
    throw const ApiException(401, 'Authentication context is missing');
  }
  return userId;
}
