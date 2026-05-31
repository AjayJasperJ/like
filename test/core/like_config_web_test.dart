import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  group('LikeConfig Web Support', () {
    test('supportWeb default is false', () {
      final config = LikeConfig(projectName: 'test_project');
      expect(config.supportWeb, isFalse);
    });

    test('supportWeb copyWith works correctly', () {
      final config = LikeConfig(projectName: 'test_project');
      final updated = config.copyWith(supportWeb: true);
      expect(updated.supportWeb, isTrue);

      final reset = updated.copyWith(supportWeb: false);
      expect(reset.supportWeb, isFalse);
    });

    test('LikeConstants integrates supportWeb correctly', () {
      final config = LikeConfig(supportWeb: true, projectName: 'test_web');
      LikeConstants.apply(config);
      expect(LikeConstants.supportWeb, isTrue);

      final configFalse =
          LikeConfig(supportWeb: false, projectName: 'test_web');
      LikeConstants.apply(configFalse);
      expect(LikeConstants.supportWeb, isFalse);
    });
  });

  group('LikeConfig Project Namespacing', () {
    test('default namespacing replaces invalid chars and lowercases', () {
      final config = LikeConfig(projectName: 'My Super Project 123!');
      expect(config.projectName, 'My Super Project 123!');

      // Box names should be formatted and prefixed correctly
      expect(config.boxApiCache, 'my_super_project_123__api_cache');
      expect(config.boxOfflineQueue, 'my_super_project_123__offline_queue');
      expect(config.boxCacheMetadata, 'my_super_project_123__cache_metadata');
      expect(config.boxEtags, 'my_super_project_123__etags');
    });

    test('copyWith keeps or updates projectName', () {
      final config = LikeConfig(projectName: 'A');
      expect(config.boxApiCache, 'a_api_cache');

      final updated = config.copyWith(projectName: 'B');
      expect(updated.projectName, 'B');
      expect(updated.boxApiCache, 'b_api_cache');
    });
  });
}
