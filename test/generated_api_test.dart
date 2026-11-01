import 'package:dio/dio.dart' show RequestOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:mocktail/mocktail.dart';
import 'generated/fixture_api.dart';

class _Http extends Mock implements LikeHttpClient {}

void main() {
  test(
    'generated parser and explicit HTTP policy execute through injected contract',
    () async {
      final http = _Http();
      final token = CancelToken();
      registerFallbackValue(const LikeRequestConfig());
      when(
        () => http.get(
          '/items/7',
          cancelToken: token,
          withAuth: false,
          requestConfig: any(named: 'requestConfig'),
        ),
      ).thenAnswer(
        (_) async => LikeApiResult.success(
          Response(
            requestOptions: RequestOptions(path: '/items/7'),
            data: {'id': 7, 'title': 'Fixture', 'price': 2},
          ),
        ),
      );
      final result = await GeneratedApi(
        http,
      ).getItem(id: 7, cancelToken: token);
      expect(result.isSuccess, isTrue);
      expect(result.data!.price, 2.0);
      expect(result.data!.note, isNull);
      final config =
          verify(
                () => http.get(
                  '/items/7',
                  cancelToken: token,
                  withAuth: false,
                  requestConfig: captureAny(named: 'requestConfig'),
                ),
              ).captured.single
              as LikeRequestConfig;
      expect(config.cacheTags, ['items']);
      expect(result.data!.toJson()['title'], 'Fixture');
    },
  );
}
