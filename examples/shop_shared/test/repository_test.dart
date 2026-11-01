import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:like_shop_shared/shop_shared.dart';
import 'package:mocktail/mocktail.dart';

class _Http extends Mock implements LikeHttpClient {}

void main() {
  test(
    'public service returns data and safely maps failure without exposing body',
    () async {
      final http = _Http();
      when(
        () => http.get(
          '/products',
          query: null,
          headers: null,
          disableCache: false,
        ),
      ).thenAnswer(
        (_) async => LikeApiResult.success(
          Response(
            requestOptions: RequestOptions(path: '/products'),
            data: {'products': [], 'total': 0},
          ),
        ),
      );
      expect((await ShopApi(http).get('/products'))['total'], 0);
      when(
        () => http.get(
          '/products',
          query: null,
          headers: null,
          disableCache: false,
        ),
      ).thenAnswer(
        (_) async => LikeApiResult.error(
          LikeError(
            message: 'private upstream response',
            type: LikeApiErrorType.unknown,
          ),
        ),
      );
      await expectLater(
        ShopApi(http).get('/products'),
        throwsA(
          isA<ShopFailure>().having(
            (error) => error.message,
            'message',
            isNot(contains('private')),
          ),
        ),
      );
    },
  );
  test('product parser normalizes numeric prices', () {
    final item = Product.fromJson({'id': 1, 'title': 'Test', 'price': 2});
    expect(item.price, 2.0);
    expect(Product.fromJson(item.toJson()).id, item.id);
  });
}
