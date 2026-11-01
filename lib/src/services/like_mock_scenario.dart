import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_constants.dart';
import 'dart:convert';
import 'like_mock_controller.dart';
import 'package:like/src/diagnostics/like_redaction.dart';

/// Versioned, persistent scenarios use synthetic payloads only. Safe export strips
/// matching credentials and opaque response values before sharing with others.
class LikeMockScenario {
  final String name;
  final List<MockRule> rules;
  LikeMockScenario({required this.name, required Iterable<MockRule> rules})
      : rules = List.unmodifiable(rules);
  String exportSafe() => jsonEncode({
        'schema': 1,
        'name': 'Synthetic scenario',
        'rules': rules
            .map((rule) => {
                  ...rule.toMap(),
              'name': 'Synthetic rule', 'description': '',
                  'baseUrlPattern': '',
                  'headersPattern': '',
                  'requestBodyPattern': '',
                  'queryParametersPattern': '',
                  'pathPattern': rule.useRegex
                      ? '/'
                      : LikeRedaction.endpoint(rule.pathPattern),
                  'useRegex': false,
                  'responseHeaders': {
                    if (int.tryParse(
                            rule.responseHeaders['retry-after'] ?? '') !=
                        null)
                      'retry-after': rule.responseHeaders['retry-after']
                  },
                  'responseBody':
                      jsonEncode(LikeRedaction.sanitize(rule.responseBody))
                })
            .toList()
      });
  factory LikeMockScenario.fromJson(String json) {
    final value = jsonDecode(json) as Map<String, dynamic>;
    if (value['schema'] != 1 ||
        value['rules'] is! List ||
        (value['rules'] as List).length > 100) {
      throw const FormatException('Unsupported mock scenario');
    }
    final rules = (value['rules'] as List)
        .map((value) => MockRule.fromMap(value as Map))
        .toList();
    if (rules.map((rule) => rule.id).toSet().length != rules.length) {
      throw const FormatException('Duplicate scenario rule IDs');
    }
    return LikeMockScenario(name: value['name'] as String, rules: rules);
  }
  Future<void> install() async {
    if (kReleaseMode) { throw StateError('Synthetic scenarios are unavailable in release builds'); }
    await MockController().importRules(rules, clearExisting: true);
    LikeConstants.apply(LikeConstants.current.copyWith(mockEnabled: true));
  }
  static LikeMockScenario failureThenSuccess(String path,
          {int status = 429,
          LikeMockFailure failure = LikeMockFailure.none,
          int delayMs = 0}) =>
      LikeMockScenario(name: 'Synthetic recovery', rules: [
        MockRule(
            id: 'initial-failure',
            pathPattern: path,
            method: 'ANY',
            maxUses: 1,
            delayMs: delayMs,
            failure: failure,
            statusCode: status,
            responseHeaders: const {'retry-after': '0'},
            responseBody: '{"message":"Synthetic failure"}'),
        MockRule(
            id: 'recovered',
            pathPattern: path,
            method: 'ANY',
            statusCode: 200,
            responseBody: '{"data":{},"message":"Recovered"}'),
      ]);
}
