import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/api_models.dart';
import '../repositories/post_repository.dart';
import '../services/post_api_service.dart';

/// Override this boundary in ProviderScope/ProviderContainer tests.
final postsRepositoryProvider = Provider<PostsRepository>(
  (ref) => PostRepository(PostApiService()),
);

/// Each page owns its lifecycle. Invalidate this provider after a mutation.
final postsPageProvider = FutureProvider.autoDispose
    .family<ApiResult<PaginatedPosts>, int>((ref, page) {
  return ref.watch(postsRepositoryProvider).list(page: page);
});

/// Shared query engine supplies cancellation, resource invalidation and reconnects.
final postsQueryProvider = StreamProvider.autoDispose
    .family<LikeStateResponse<PaginatedPosts>, int>((ref, page) {
  final query = ref.watch(postsRepositoryProvider).watchPage(page);
  ref.onDispose(query.dispose);
  query.refresh();
  return query.watch();
});
