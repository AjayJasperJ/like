import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
  if (kIsWeb) {
    await Hive.initFlutter('pagination_browser_tests');
  } else {
    final temp = Directory.systemTemp.createTempSync('hive_pagination_test');
    Hive.init(temp.path);
  }
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
        return kIsWeb ? '/' : Directory.systemTemp.path;
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

    test('PaginationTool.updateCursor tracks cursors and stops on repeated cursor', () {
      final first = PaginationTool<SampleItem>.initial().updateCursor(
        pageData: [SampleItem(id: 1, name: 'A')],
        append: false,
        cursor: null,
        nextCursor: 'c2',
        limit: 1,
      );
      expect(first.isCursorMode, isTrue);
      expect(first.hasMore, isTrue);
      expect(first.nextCursor, 'c2');

      final second = first.updateCursor(
        pageData: [SampleItem(id: 2, name: 'B')],
        append: true,
        cursor: 'c2',
        nextCursor: 'c2',
        limit: 1,
      );
      expect(second.items?.map((e) => e.id), [1, 2]);
      expect(second.hasMore, isFalse);
    });

    test('PaginatedNotifierState.loadCursor and loadNextCursor handle cursor pages', () async {
      final state = PaginatedNotifierState<SampleItem>(pageSize: 1);
      addTearDown(state.dispose);

      await state.loadCursor(
        action: (cursor, limit) async {
          expect(cursor, isNull);
          return ApiResult.success(
            PaginationTool<SampleItem>(
              cursorBased: true,
              nextCursor: 'cursor-2',
              listData: [SampleItem(id: 1, name: 'First')],
            ),
          );
        },
      );
      expect(state.isCursorMode, isTrue);
      expect(state.nextCursor, 'cursor-2');
      expect(state.hasMore, isTrue);

      await state.loadNextCursor(
        action: (cursor, limit) async {
          expect(cursor, 'cursor-2');
          return ApiResult.success(
            PaginationTool<SampleItem>(
              cursorBased: true,
              cursor: cursor,
              nextCursor: null,
              listData: [SampleItem(id: 2, name: 'Second')],
            ),
          );
        },
      );
      expect(state.items.map((e) => e.name), ['First', 'Second']);
      expect(state.currentCursor, 'cursor-2');
      expect(state.nextCursor, isNull);
      expect(state.hasMore, isFalse);
    });

    test(
        'cursor pagination honors 3-parameter combinations: current cursor, next cursor, hasMore',
        () async {
      final state = PaginatedNotifierState<SampleItem>(pageSize: 2);
      addTearDown(state.dispose);

      // Case 1: Initial load with current='c1', next='c2', hasMore=true
      await state.loadCursor(
        action: (cursor, limit) async {
          expect(cursor, isNull);
          expect(limit, 2);
          return ApiResult.success(
            PaginationTool<SampleItem>(
              cursorBased: true,
              cursor: 'c1',
              nextCursor: 'c2',
              hasNextOverride: true,
              listData: [
                SampleItem(id: 1, name: 'A'),
                SampleItem(id: 2, name: 'B'),
              ],
            ),
          );
        },
      );
      expect(state.currentCursor, 'c1');
      expect(state.nextCursor, 'c2');
      expect(state.hasMore, isTrue);
      expect(state.items.map((e) => e.id), [1, 2]);

      // Case 2: hasMore=false overrides non-null nextCursor and stops loadNextCursor
      var nextCalls = 0;
      await state.loadNextCursor(
        action: (cursor, limit) async {
          nextCalls++;
          expect(cursor, 'c2');
          return ApiResult.success(
            PaginationTool<SampleItem>(
              cursorBased: true,
              cursor: 'c2',
              nextCursor: 'c3',
              hasNextOverride: false,
              listData: [SampleItem(id: 3, name: 'C')],
            ),
          );
        },
      );
      expect(nextCalls, 1);
      expect(state.currentCursor, 'c2');
      expect(state.nextCursor, 'c3');
      expect(state.hasMore, isFalse);
      expect(state.items.map((e) => e.id), [1, 2, 3]);

      // Subsequent loadNextCursor must be a no-op because hasMore is false
      await state.loadNextCursor(
        action: (cursor, limit) async {
          nextCalls++;
          return ApiResult.success(const <SampleItem>[]);
        },
      );
      expect(nextCalls, 1);

      // Case 3: Refresh resets cursor state and replaces items
      await state.loadCursor(
        refresh: true,
        action: (cursor, limit) async {
          expect(cursor, isNull);
          return ApiResult.success(
            PaginationTool<SampleItem>(
              cursorBased: true,
              cursor: 'fresh-1',
              nextCursor: 'fresh-2',
              hasNextOverride: true,
              listData: [SampleItem(id: 10, name: 'Fresh')],
            ),
          );
        },
      );
      expect(state.currentCursor, 'fresh-1');
      expect(state.nextCursor, 'fresh-2');
      expect(state.hasMore, isTrue);
      expect(state.items.map((e) => e.id), [10]);
    });

    test(
        'cursor pagination preserves current/next cursors on loadNextCursor failure and stops on repeated cursor',
        () async {
      final state = PaginatedNotifierState<SampleItem>(pageSize: 1);
      addTearDown(state.dispose);

      await state.loadCursor(
        action: (cursor, limit) async => ApiResult.success(
          PaginationTool<SampleItem>(
            cursorBased: true,
            cursor: 'c1',
            nextCursor: 'c2',
            hasNextOverride: true,
            listData: [SampleItem(id: 1, name: 'A')],
          ),
        ),
      );

      // Failed loadNextCursor keeps existing items and cursors intact
      await state.loadNextCursor(
        action: (cursor, limit) async => ApiResult<PaginationTool<SampleItem>>.error(
          LikeError(message: 'Network error', type: LikeApiErrorType.network),
        ),
      );
      expect(state.items.map((e) => e.id), [1]);
      expect(state.currentCursor, 'c1');
      expect(state.nextCursor, 'c2');
      expect(state.hasMore, isTrue);
      expect(state.loadMoreError?.message, 'Network error');

      // Retry succeeds, but API repeats nextCursor == cursor ('c2') -> stops pagination
      await state.loadNextCursor(
        action: (cursor, limit) async {
          expect(cursor, 'c2');
          return ApiResult.success(
            PaginationTool<SampleItem>(
              cursorBased: true,
              cursor: 'c2',
              nextCursor: 'c2',
              hasNextOverride: true,
              listData: [SampleItem(id: 2, name: 'B')],
            ),
          );
        },
      );
      expect(state.items.map((e) => e.id), [1, 2]);
      expect(state.currentCursor, 'c2');
      expect(state.hasMore, isFalse);
    });
  });
}
