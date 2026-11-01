import '../models/api_models.dart';
import '../repositories/post_repository.dart';

/// ChangeNotifier/Provider adapter over the same query used by Riverpod and Cubit.
final class PostsQueryProvider extends LikeQueryNotifier<PaginatedPosts> {
  PostsQueryProvider(PostsRepository repository, {int page = 1})
    : super(repository.watchPage(page));
}
