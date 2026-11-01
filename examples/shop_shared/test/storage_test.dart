import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:like/like.dart';
import 'package:like_shop_shared/shop_shared.dart';
import 'package:like_shop_shared/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart' show RequestOptions;

class _Http extends Mock implements LikeHttpClient {}

class _Sessions implements SessionStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? next) async {
    value = next;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cart is durable and isolated between guest and signed-in sessions',
    () async {
      Directory? directory;
      if (kIsWeb) {
        await Hive.initFlutter();
      } else {
        directory = await Directory.systemTemp.createTemp('like-shop-storage-');
        Hive.init(directory.path);
      }
      var box = await Hive.openBox<dynamic>('shop_storage_fixture');
      final http = _Http();
      final sessions = _Sessions();
      Customer? scope;
      registerFallbackValue(const LikeRequestConfig());
      when(
        () => http.post(
          '/auth/login',
          body: any(named: 'body'),
          headers: null,
          offlineSync: false,
        ),
      ).thenAnswer(
        (_) async => LikeApiResult.success(
          Response(
            requestOptions: RequestOptions(path: '/auth/login'),
            data: {
              'id': 7,
              'firstName': 'Demo',
              'accessToken': 'access-fixture',
              'refreshToken': 'refresh-fixture',
            },
          ),
        ),
      );
      PublicShopRepository repository() => PublicShopRepository(
        ShopApi(http),
        sessions,
        box,
        setScope: (value) => scope = value,
        closeClient: () {},
      );
      var repo = repository();
      try {
        await repo.saveCart([const CartLine(FixtureShopRepository.item, 2)]);
        await repo.login('emilys', 'emilyspass');
        expect(scope!.id, 7);
        expect(await repo.loadCart(), isEmpty);
        await repo.saveCart([const CartLine(FixtureShopRepository.second, 1)]);
        await repo.logout();
        expect(scope, isNull);
        expect((await repo.loadCart()).single.quantity, 2);
        await box.close();
        box = await Hive.openBox<dynamic>('shop_storage_fixture');
        repo = repository();
        expect((await repo.loadCart()).single.product.id, 1);
        expect(box.toMap().toString(), isNot(contains('access-fixture')));
        expect(box.toMap().toString(), isNot(contains('refresh-fixture')));
      } finally {
        await box.clear();
        await box.close();
        if (directory != null) {
          await directory.delete(recursive: true);
        }
      }
    },
  );
}
