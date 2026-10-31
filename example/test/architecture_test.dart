import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/testing.dart';
import 'package:like_example/data/bloc/posts_cubit.dart';
import 'package:like_example/data/models/paginated_posts.dart';
import 'package:like_example/data/providers/post_provider.dart';
import 'package:like_example/data/repositories/post_repository.dart';
import 'package:like_example/data/riverpod/posts_providers.dart';
import 'package:like_example/data/services/post_api_service.dart';
import 'package:mocktail/mocktail.dart';

class MockClient extends Mock implements LikeHttpClient {}

class MockRepository extends Mock implements PostsRepository {}

PaginatedPosts page() => PaginatedPosts.fromJson({
      'data': <dynamic>[],
      'page': 1,
      'limit': 10,
      'total': 0,
    });

void main() {
  test('service and repository work with an injected client without bootstrap',
      () async {
    final client = MockClient();
    when(() => client.get(
          '/api/posts/1',
          withAuth: true,
          disableCache: true,
        )).thenAnswer((_) async => ApiResult.success(Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/posts/1'),
          data: {
            'data': {
              'id': 1,
              'title': 'Test',
              'body': 'Body',
              'userId': 1,
              'createdAt': '2026-01-01T00:00:00Z'
            }
          },
          statusCode: 200,
        )));
    // Use the public URL constant through the service rather than networking.
    final service = PostApiService(client: client);
    final result = await PostRepository(service).find(1);
    expect(result.isSuccess, isTrue);
    expect(result.data!.id, 1);
  });

  test('Provider uses the repository contract', () async {
    final repository = MockRepository();
    when(() => repository.find(1)).thenAnswer(
      (_) async => ApiResult.error(
          LikeError(message: 'Missing', type: LikeApiErrorType.notFound)),
    );
    final provider = PostProvider(repository);
    final result = await provider.find(1);
    expect(result.error!.type, LikeApiErrorType.notFound);
    provider.dispose();
  });

  test('Riverpod repository override avoids the default client', () async {
    final repository = MockRepository();
    final expected = ApiResult.success(page());
    when(() => repository.list(page: 2)).thenAnswer((_) async => expected);
    final container = ProviderContainer(overrides: [
      postsRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    final result = await container.read(postsPageProvider(2).future);
    expect(result, same(expected));
  });

  test('Cubit publishes repository errors', () async {
    final repository = MockRepository();
    when(() => repository.list(page: 1)).thenAnswer((_) async =>
        ApiResult.error(
            LikeError(message: 'Missing', type: LikeApiErrorType.notFound)));
    final cubit = PostsCubit(repository);
    addTearDown(cubit.close);
    await cubit.load();
    expect(cubit.state.state, LikeState.error);
    expect(cubit.state.error!.type, LikeApiErrorType.notFound);
  });

  test('Cubit ignores stale completions and completion after close', () async {
    final repository = MockRepository();
    final first = Completer<ApiResult<PaginatedPosts>>();
    final second = Completer<ApiResult<PaginatedPosts>>();
    when(() => repository.list(page: 1)).thenAnswer((_) => first.future);
    when(() => repository.list(page: 2)).thenAnswer((_) => second.future);
    final cubit = PostsCubit(repository);
    final oldRun = cubit.load();
    final newRun = cubit.load(page: 2);
    final latest = page();
    second.complete(ApiResult.success(latest));
    await newRun;
    first.complete(ApiResult.success(page()));
    await oldRun;
    expect(cubit.state.data, same(latest));
    final pending = Completer<ApiResult<PaginatedPosts>>();
    when(() => repository.list(page: 1)).thenAnswer((_) => pending.future);
    final run = cubit.load();
    await cubit.close();
    pending.complete(ApiResult.success(page()));
    await run;
  });
}
