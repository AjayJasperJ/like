import 'package:flutter/foundation.dart';
import 'package:like/like.dart';
import '../models/post.dart';
import '../repositories/post_repository.dart';

class PostProvider extends ChangeNotifier {
  final PostRepository _repository;
  final LikeEngine engine = LikeEngine();

  PostProvider(this._repository) {
    paginatedPosts.addListener(notifyListeners);
  }

  late final paginatedPosts = PaginatedNotifierState<Post>(
    pageSize: 10,
    initialValue: StateResponse.loading(),
    fetcher: (page, limit) => _repository.getPosts(
      page: page,
      limit: limit,
    ),
  );

  final createPostState = NotifierState<Post>(
    initialValue: StateResponse.idle(),
  );

  bool get hasMorePosts => paginatedPosts.hasMore;
  
  // We expose this so the UI can easily access the primary state without changing too much.
  NotifierState<List<Post>> get postsState => paginatedPosts;
  NotifierState<List<Post>> get postsPaginationState => paginatedPosts.paginationState;

  Future<void> getPosts({bool loadMore = false, ARS? ars}) async {
    if (loadMore) {
      await paginatedPosts.fetchNextPage(engine: engine, ars: ars);
    } else {
      await paginatedPosts.fetchInitial(engine: engine, ars: ars);
    }
  }

  Future<void> createPost(String title, String body) async {
    if (title.isEmpty) {
      createPostState.value = StateResponse.missingData('missing title');
      return;
    }
    
    final response = await engine.fetchResult<Post>(
      state: createPostState,
      action: () => _repository.createPost(
        {'title': title, 'body': body, 'userId': 1},
      ),
    );
    
    if (response.isSuccess) {
      await getPosts();
    }
  }

  @override
  void dispose() {
    engine.dispose();
    paginatedPosts.removeListener(notifyListeners);
    paginatedPosts.dispose();
    super.dispose();
  }
}
