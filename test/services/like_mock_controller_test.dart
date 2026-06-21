import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/src/services/like_mock_controller.dart';
import '../mocks/mocks.dart';

void main() {
  setUpAll(() async {
    setupMocks();
    await initTestHive();
  });

  group('MockRule', () {
    test('default constructor parameters', () {
      final rule = MockRule(
        id: 'rule_1',
        pathPattern: '/api/v1/users',
        method: 'GET',
        responseBody: '{"status": "ok"}',
      );

      expect(rule.id, equals('rule_1'));
      expect(rule.name, isEmpty);
      expect(rule.description, isEmpty);
      expect(rule.pathPattern, equals('/api/v1/users'));
      expect(rule.baseUrlPattern, isEmpty);
      expect(rule.method, equals('GET'));
      expect(rule.statusCode, equals(200));
      expect(rule.responseBody, equals('{"status": "ok"}'));
      expect(rule.requestBodyPattern, isEmpty);
      expect(rule.queryParametersPattern, isEmpty);
      expect(rule.headersPattern, isEmpty);
      expect(rule.isEnabled, isTrue);
      expect(rule.useRegex, isFalse);
    });

    test('toMap and fromMap serialization', () {
      final rule = MockRule(
        id: 'rule_2',
        name: 'Get User Profile',
        description: 'Mock profile response',
        pathPattern: '/profile',
        baseUrlPattern: 'https://test.com',
        method: 'POST',
        statusCode: 201,
        responseBody: '{"id": 1}',
        requestBodyPattern: '.*',
        queryParametersPattern: 'id=1',
        headersPattern: 'auth=true',
        isEnabled: false,
        useRegex: true,
      );

      final map = rule.toMap();
      final decoded = MockRule.fromMap(map);

      expect(decoded.id, equals('rule_2'));
      expect(decoded.name, equals('Get User Profile'));
      expect(decoded.description, equals('Mock profile response'));
      expect(decoded.pathPattern, equals('/profile'));
      expect(decoded.baseUrlPattern, equals('https://test.com'));
      expect(decoded.method, equals('POST'));
      expect(decoded.statusCode, equals(201));
      expect(decoded.responseBody, equals('{"id": 1}'));
      expect(decoded.requestBodyPattern, equals('.*'));
      expect(decoded.queryParametersPattern, equals('id=1'));
      expect(decoded.headersPattern, equals('auth=true'));
      expect(decoded.isEnabled, isFalse);
      expect(decoded.useRegex, isTrue);
    });

    test('fromMap fallback values', () {
      final decoded = MockRule.fromMap({});
      expect(decoded.id, isEmpty);
      expect(decoded.name, isEmpty);
      expect(decoded.description, isEmpty);
      expect(decoded.pathPattern, isEmpty);
      expect(decoded.baseUrlPattern, isEmpty);
      expect(decoded.method, equals('GET'));
      expect(decoded.statusCode, equals(200));
      expect(decoded.responseBody, equals('{}'));
      expect(decoded.requestBodyPattern, isEmpty);
      expect(decoded.queryParametersPattern, isEmpty);
      expect(decoded.headersPattern, isEmpty);
      expect(decoded.isEnabled, isTrue);
      expect(decoded.useRegex, isFalse);
    });

    test('copyWith works correctly', () {
      final rule = MockRule(
        id: 'rule_3',
        pathPattern: '/path',
        method: 'PUT',
        responseBody: 'body',
      );

      final copied = rule.copyWith(
        id: 'rule_copied',
        name: 'name',
        description: 'desc',
        pathPattern: '/path2',
        baseUrlPattern: 'base',
        method: 'GET',
        statusCode: 400,
        responseBody: 'body2',
        requestBodyPattern: 'req',
        queryParametersPattern: 'query',
        headersPattern: 'headers',
        isEnabled: false,
        useRegex: true,
      );

      expect(copied.id, equals('rule_copied'));
      expect(copied.name, equals('name'));
      expect(copied.description, equals('desc'));
      expect(copied.pathPattern, equals('/path2'));
      expect(copied.baseUrlPattern, equals('base'));
      expect(copied.method, equals('GET'));
      expect(copied.statusCode, equals(400));
      expect(copied.responseBody, equals('body2'));
      expect(copied.requestBodyPattern, equals('req'));
      expect(copied.queryParametersPattern, equals('query'));
      expect(copied.headersPattern, equals('headers'));
      expect(copied.isEnabled, isFalse);
      expect(copied.useRegex, isTrue);

      final emptyCopy = rule.copyWith();
      expect(emptyCopy.id, equals(rule.id));
      expect(emptyCopy.pathPattern, equals(rule.pathPattern));
    });
  });

  group('MockController', () {
    late MockController controller;
    const boxName = 'devtools_mock_rules';

    setUp(() async {
      await Hive.openBox(boxName);
      final box = Hive.box(boxName);
      await box.clear();

      controller = MockController();
      controller.reset();
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
    });

    test('singleton instance check', () {
      final c1 = MockController();
      final c2 = MockController();
      expect(identical(c1, c2), isTrue);
    });

    test('init loading rules and engine state', () async {
      final box = Hive.box(boxName);
      
      final rule = MockRule(id: 'rule_load', pathPattern: '/test', method: 'GET', responseBody: '{}');
      await box.put('rule_load', rule.toMap());
      await box.put('__engine_enabled', false);

      // Force initialization
      // (MockController's internal initialization field can be bypassed by creating the controller or just calling methods)
      // Since it's a singleton, let's trigger add/delete to call internal init, or call init directly.
      await controller.init();

      expect(controller.rules.value.length, equals(1));
      expect(controller.rules.value.first.id, equals('rule_load'));
      expect(controller.isEngineEnabled.value, isFalse);
    });

    test('addRule, updateRule, deleteRule, toggleRule', () async {
      final rule = MockRule(id: 'r1', pathPattern: '/p1', method: 'GET', responseBody: '{}', isEnabled: true);
      
      await controller.addRule(rule);
      expect(controller.rules.value.length, equals(1));
      expect(controller.rules.value.first.id, equals('r1'));

      final updatedRule = rule.copyWith(responseBody: '{"updated": true}');
      await controller.updateRule(updatedRule);
      expect(controller.rules.value.first.responseBody, equals('{"updated": true}'));

      // toggleRule
      await controller.toggleRule('r1');
      expect(controller.rules.value.first.isEnabled, isFalse);

      // deleteRule
      await controller.deleteRule('r1');
      expect(controller.rules.value, isEmpty);
    });

    test('setEngineEnabled saves to box and notifier', () async {
      await controller.setEngineEnabled(true);
      expect(controller.isEngineEnabled.value, isTrue);

      await controller.setEngineEnabled(false);
      expect(controller.isEngineEnabled.value, isFalse);
    });

    test('importRules cleans or appends rules', () async {
      final rule1 = MockRule(id: 'imp1', pathPattern: '/p1', method: 'GET', responseBody: '{}');
      final rule2 = MockRule(id: 'imp2', pathPattern: '/p2', method: 'POST', responseBody: '{}');
      final ruleNoId = MockRule(id: '', pathPattern: '/p3', method: 'GET', responseBody: '{}');

      // Clear existing
      await controller.importRules([rule1], clearExisting: true);
      expect(controller.rules.value.length, equals(1));
      expect(controller.rules.value[0].id, equals('imp1'));

      // Append new rules
      await controller.importRules([rule2, ruleNoId], clearExisting: false);
      expect(controller.rules.value.length, equals(3));
      expect(controller.rules.value[1].id, equals('imp2'));
      expect(controller.rules.value[2].id, isNotEmpty); // generated ID
    });
  });
}
