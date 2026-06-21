import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

class MockRule {
  final String id;
  final String name;
  final String description;
  final String pathPattern; // Regex or exact path
  final String baseUrlPattern; // Optional base URL match
  final String method; // GET, POST, etc. or ANY
  final int statusCode;
  final String responseBody;
  final String requestBodyPattern; // Optional body match
  final String queryParametersPattern; // Optional query match
  final String headersPattern; // Optional headers match
  final bool isEnabled;
  final bool useRegex;

  MockRule({
    required this.id,
    this.name = '',
    this.description = '',
    required this.pathPattern,
    this.baseUrlPattern = '',
    required this.method,
    this.statusCode = 200,
    required this.responseBody,
    this.requestBodyPattern = '',
    this.queryParametersPattern = '',
    this.headersPattern = '',
    this.isEnabled = true,
    this.useRegex = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'pathPattern': pathPattern,
      'baseUrlPattern': baseUrlPattern,
      'method': method,
      'statusCode': statusCode,
      'responseBody': responseBody,
      'requestBodyPattern': requestBodyPattern,
      'queryParametersPattern': queryParametersPattern,
      'headersPattern': headersPattern,
      'isEnabled': isEnabled,
      'useRegex': useRegex,
    };
  }

  factory MockRule.fromMap(Map<dynamic, dynamic> map) {
    return MockRule(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      pathPattern: map['pathPattern'] as String? ?? '',
      baseUrlPattern: map['baseUrlPattern'] as String? ?? '',
      method: map['method'] as String? ?? 'GET',
      statusCode: map['statusCode'] as int? ?? 200,
      responseBody: map['responseBody'] as String? ?? '{}',
      requestBodyPattern: map['requestBodyPattern'] as String? ?? '',
      queryParametersPattern: map['queryParametersPattern'] as String? ?? '',
      headersPattern: map['headersPattern'] as String? ?? '',
      isEnabled: map['isEnabled'] as bool? ?? true,
      useRegex: map['useRegex'] as bool? ?? false,
    );
  }

  MockRule copyWith({
    String? id,
    String? name,
    String? description,
    String? pathPattern,
    String? baseUrlPattern,
    String? method,
    int? statusCode,
    String? responseBody,
    String? requestBodyPattern,
    String? queryParametersPattern,
    String? headersPattern,
    bool? isEnabled,
    bool? useRegex,
  }) {
    return MockRule(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      pathPattern: pathPattern ?? this.pathPattern,
      baseUrlPattern: baseUrlPattern ?? this.baseUrlPattern,
      method: method ?? this.method,
      statusCode: statusCode ?? this.statusCode,
      responseBody: responseBody ?? this.responseBody,
      requestBodyPattern: requestBodyPattern ?? this.requestBodyPattern,
      queryParametersPattern:
          queryParametersPattern ?? this.queryParametersPattern,
      headersPattern: headersPattern ?? this.headersPattern,
      isEnabled: isEnabled ?? this.isEnabled,
      useRegex: useRegex ?? this.useRegex,
    );
  }
}

class MockController {
  MockController._internal();
  static final MockController _instance = MockController._internal();
  factory MockController() => _instance;

  @visibleForTesting
  void reset() {
    _isInitialized = false;
    rules.value = [];
    isEngineEnabled.value = true;
  }

  static const String _boxName = 'devtools_mock_rules';
  final ValueNotifier<List<MockRule>> rules = ValueNotifier<List<MockRule>>([]);
  final ValueNotifier<bool> isEngineEnabled = ValueNotifier<bool>(true);
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    try {
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox(_boxName);
      }

      final box = Hive.box(_boxName);
      final List<MockRule> loadedRules = [];

      for (var key in box.keys) {
        if (key == '__engine_enabled') continue;
        final data = box.get(key);
        if (data is Map) {
          loadedRules.add(MockRule.fromMap(data));
        }
      }

      rules.value = loadedRules;
      isEngineEnabled.value =
          box.get('__engine_enabled', defaultValue: true) as bool;
      debugPrint(
        '[MockController] Initialized with ${loadedRules.length} rules, engineEnabled: ${isEngineEnabled.value}',
      );
    } catch (e) {
      debugPrint('[MockController] Init failed: $e');
    }
  }

  Future<void> setEngineEnabled(bool enabled) async {
    await init();
    final box = Hive.box(_boxName);
    await box.put('__engine_enabled', enabled);
    isEngineEnabled.value = enabled;
  }

  Future<void> addRule(MockRule rule) async {
    await init();
    final box = Hive.box(_boxName);
    await box.put(rule.id, rule.toMap());
    rules.value = [...rules.value, rule];
  }

  Future<void> updateRule(MockRule rule) async {
    await init();
    final box = Hive.box(_boxName);
    await box.put(rule.id, rule.toMap());

    final index = rules.value.indexWhere((r) => r.id == rule.id);
    if (index != -1) {
      final newRules = List<MockRule>.from(rules.value);
      newRules[index] = rule;
      rules.value = newRules;
    }
  }

  Future<void> deleteRule(String id) async {
    await init();
    final box = Hive.box(_boxName);
    await box.delete(id);
    rules.value = rules.value.where((r) => r.id != id).toList();
  }

  Future<void> toggleRule(String id) async {
    await init();
    final index = rules.value.indexWhere((r) => r.id == id);
    if (index != -1) {
      final rule = rules.value[index];
      await updateRule(rule.copyWith(isEnabled: !rule.isEnabled));
    }
  }

  Future<void> importRules(
    List<MockRule> newRules, {
    bool clearExisting = false,
  }) async {
    await init();
    final box = Hive.box(_boxName);
    if (clearExisting) {
      await box.clear();
      rules.value = [];
    }

    final List<MockRule> updatedRules = List.from(rules.value);
    for (var rule in newRules) {
      final finalRule = rule.id.isEmpty
          ? rule.copyWith(
              id: DateTime.now().millisecondsSinceEpoch.toString() +
                  updatedRules.length.toString(),
            )
          : rule;

      await box.put(finalRule.id, finalRule.toMap());
      updatedRules.add(finalRule);
    }

    rules.value = updatedRules;
    debugPrint('[MockController] Imported ${newRules.length} rules');
  }
}
