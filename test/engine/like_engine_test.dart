import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/like.dart';

import '../mocks/mocks.dart';

class TestProvider with ChangeNotifier {
  final LikeEngine engine = LikeEngine();
  final LikeNotifierState<String> state = LikeNotifierState<String>();

  void triggerFetch() {
    engine.fetch<String>(
      state: state,
      action: () async {
        await Future.delayed(const Duration(milliseconds: 100));
        return LikeStateResponse<String>.success('Fetched Data');
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    setupMocks();
    await initTestHive();
  });

  setUp(() async {
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
    await Hive.openBox(LikeConstants.boxEtags);
    await Hive.openBox(LikeConstants.boxOfflineQueue);
    LikeClient.reset();
    LikeClient(baseUrl: 'https://test-api.com');
  });

  test('Fetch successfully returns data', () async {
    final provider = TestProvider();
    provider.triggerFetch();

    expect(provider.state.value.isLoading, isTrue);

    await Future.delayed(const Duration(milliseconds: 150));
    expect(provider.state.value.isSuccess, isTrue);
    expect(provider.state.value.data, equals('Fetched Data'));
  });

  test('Token rotation cancels previous request', () async {
    final provider = TestProvider();

    // First fetch
    provider.triggerFetch();
    final firstToken = provider.state.ct;
    expect(provider.state.value.isLoading, isTrue);

    // Second fetch immediately (rotates token)
    provider.triggerFetch();
    final secondToken = provider.state.ct;

    expect(firstToken, isNotNull);
    expect(secondToken, isNotNull);
    expect(firstToken != secondToken, isTrue);

    await Future.delayed(const Duration(milliseconds: 150));
    expect(provider.state.value.isSuccess, isTrue);
  });
}
