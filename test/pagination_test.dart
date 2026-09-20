import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/like.dart';

class SampleItem {
  final int id;
  final String name;

  SampleItem({required this.id, required this.name});

  factory SampleItem.fromJson(Map<String, dynamic> json) => SampleItem(
        id: json['id'] as int,
        name: json['name'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

class CustomPaginatedResponse extends PaginationTool<SampleItem> {
  final List<SampleItem> records;

  CustomPaginatedResponse({
    required this.records,
    required super.page,
    required super.contentLimit,
    required super.totalContent,
    required super.totalPages,
    required super.hasNextOverride,
  }) : super(listData: records);

  factory CustomPaginatedResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['records'] as List)
        .map((e) => SampleItem.fromJson(e as Map<String, dynamic>))
        .toList();
    return CustomPaginatedResponse(
      records: list,
      page: json['page'] as int?,
      contentLimit: json['limit'] as int?,
      totalContent: json['total'] as int?,
      totalPages: json['totalPages'] as int?,
      hasNextOverride: json['hasNext'] as bool?,
    );
  }
}

Future<void> initTestHive() async {
  final temp = Directory.systemTemp.createTempSync('hive_pagination_test');
  Hive.init(temp.path);
}

void setupMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory' ||
          methodCall.method == 'getTemporaryDirectory' ||
          methodCall.method == 'getApplicationSupportDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    },
  );
  messenger.setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    MockStreamHandler.inline(
      onListen: (arguments, events) {},
      onCancel: (arguments) {},
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupMocks();
    await initTestHive();
    await LikeService.init(config: LikeConfig(projectName: 'test_project'));
  });

  group('PaginationTool Model Extraction & Response Model Extension', () {
    test(
        'Response model extending PaginationTool automatically provides pagination metadata and items',
        () {
      final json = {
        'page': 1,
        'limit': 10,
        'total': 30,
        'totalPages': 3,
        'hasNext': true,
        'records': [
          {'id': 100, 'name': 'Record A'},
        ],
      };

      final response = CustomPaginatedResponse.fromJson(json);

      expect(response, isA<PaginationTool<SampleItem>>());
      expect(response.page, equals(1));
      expect(response.limit, equals(10));
      expect(response.total, equals(30));
      expect(response.hasNext, isTrue);
      expect(response.items?.first.name, equals('Record A'));
    });
  });

  group('PaginatedNotifierState All-in-One Loader', () {
    test('postsState.load handles initial page 1 load', () async {
      final state = PaginatedNotifierState<SampleItem>();

      await state.load(
        page: 1,
        action: (p, limit) async {
          return ApiResult.success(
            CustomPaginatedResponse(
              records: [SampleItem(id: 1, name: 'Item 1')],
              page: 1,
              contentLimit: 10,
              totalContent: 20,
              totalPages: 2,
              hasNextOverride: true,
            ),
          );
        },
      );

      expect(state.items.length, equals(1));
      expect(state.items.first.name, equals('Item 1'));
      expect(state.hasMore, isTrue);
    });

    test('postsState.loadNext appends data for page 2', () async {
      final state = PaginatedNotifierState<SampleItem>();

      await state.load(
        page: 1,
        action: (p, limit) async {
          return ApiResult.success(
            CustomPaginatedResponse(
              records: [SampleItem(id: 1, name: 'Item 1')],
              page: 1,
              contentLimit: 10,
              totalContent: 20,
              totalPages: 2,
              hasNextOverride: true,
            ),
          );
        },
      );

      await state.loadNext(
        action: (p, limit) async {
          return ApiResult.success(
            CustomPaginatedResponse(
              records: [SampleItem(id: 2, name: 'Item 2')],
              page: 2,
              contentLimit: 10,
              totalContent: 20,
              totalPages: 2,
              hasNextOverride: false,
            ),
          );
        },
      );

      expect(state.items.length, equals(2));
      expect(state.items[0].name, equals('Item 1'));
      expect(state.items[1].name, equals('Item 2'));
      expect(state.hasMore, isFalse);
    });

    test(
        'postsState.load with overwrite: true replaces specified page slice in-place',
        () async {
      final state = PaginatedNotifierState<SampleItem>(pageSize: 1);

      await state.load(
        page: 1,
        action: (p, limit) async {
          return ApiResult.success([SampleItem(id: 1, name: 'Item 1')]);
        },
      );

      await state.load(
        page: 2,
        action: (p, limit) async {
          return ApiResult.success([SampleItem(id: 2, name: 'Item 2')]);
        },
      );

      expect(state.items.map((e) => e.name), equals(['Item 1', 'Item 2']));

      await state.load(
        page: 1,
        overwrite: true,
        action: (p, limit) async {
          return ApiResult.success([SampleItem(id: 1, name: 'Item 1 Updated')]);
        },
      );

      expect(
          state.items.map((e) => e.name), equals(['Item 1 Updated', 'Item 2']));
    });
  });
}
