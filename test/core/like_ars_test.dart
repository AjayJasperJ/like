import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  group('LikeARS', () {
    test('should have correct default values', () {
      const ars = LikeARS();
      expect(ars.staleWhileRevalidate, isFalse);
      expect(ars.refresh, isFalse);
      expect(ars.singleFetch, isFalse);
      expect(ars.sessionStale, isFalse);
      expect(ars.disableCache, isFalse);
      expect(ars.resetSingleFetch, isFalse);
      expect(ars.resetSessionStale, isFalse);
      expect(ars.offlineSync, isFalse);
      expect(ars.verifySSL, isTrue);
      expect(ars.deduplicate, isTrue);
      expect(ars.suppressErrors, isTrue);
    });

    test('toJson should return correct map', () {
      const ars = LikeARS(
        staleWhileRevalidate: false,
        refresh: true,
        singleFetch: true,
      );
      final json = ars.toJson();
      expect(json['staleWhileRevalidate'], isFalse);
      expect(json['refresh'], isTrue);
      expect(json['singleFetch'], isTrue);
    });

    test('fromJson should create correct object', () {
      final json = {
        'staleWhileRevalidate': false,
        'refresh': true,
        'singleFetch': true,
      };
      final ars = LikeARS.fromJson(json);
      expect(ars.staleWhileRevalidate, isFalse);
      expect(ars.refresh, isTrue);
      expect(ars.singleFetch, isTrue);
    });

    test('fromJson with missing values should use defaults', () {
      final ars = LikeARS.fromJson({});
      expect(ars.staleWhileRevalidate, isFalse);
      expect(ars.refresh, isFalse);
      expect(ars.deduplicate, isTrue);
    });
  });
}
