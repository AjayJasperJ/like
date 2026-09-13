import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';
import '../providers/post_provider.dart';
import '../models/post.dart';
import 'dummy_screens.dart';
import 'widgets/post_error_view.dart';
import 'widgets/post_list_item.dart';
import 'widgets/post_pagination_footer.dart';

class PostsPage extends StatefulWidget {
  const PostsPage({super.key});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> with LikeVisibilityMixin {
  late final PostProvider _postProvider;

  @override
  void initState() {
    super.initState();
    _postProvider = context.read<PostProvider>();
  }

  @override
  void onVisibilityChanged(bool visible) {
    if (visible) {
      _postProvider.getPosts(
          ars: ARS(checkAvailability: true, visibility: visible));
    } else {
      _postProvider.engine.cancelResync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Like Package Example'),
        actions: [
          Consumer<PostProvider>(
            builder: (context, provider, _) {
              final isPageRefreshing = provider.postsState.isRefreshing;
              return IconButton(
                onPressed: isPageRefreshing
                    ? null
                    : () => provider.getPosts(ars: const ARS(refresh: true)),
                icon: isPageRefreshing
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              );
            },
          ),
        ],
      ),
      body: Consumer<PostProvider>(
        builder: (context, provider, _) {
          return LikeBuilder<List<Post>>(
            observe: () => provider.postsState,
            onError: (error) => PostErrorView(
              title: 'Failed to load',
              message: error.message,
              onRetry: () => provider.getPosts(ars: const ARS(refresh: true)),
            ),
            onException: (message) => PostErrorView(
              title: 'Something went wrong',
              message: message,
              onRetry: () => provider.getPosts(ars: const ARS(refresh: true)),
            ),
            onSuccess: (posts, isRefreshing, isSWR) {
              if (posts.isEmpty) {
                return const Center(
                  child:
                      Text('No posts found.', style: TextStyle(fontSize: 16)),
                );
              }
              final isLoadingMore = provider.postsPaginationState.isLoading ||
                  provider.postsPaginationState.isRefreshing;
              final paginationError = provider.postsPaginationState.error;

              return RefreshIndicator(
                onRefresh: () =>
                    provider.getPosts(ars: const ARS(refresh: true)),
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: posts.length + (provider.hasMorePosts ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == posts.length) {
                      return PostPaginationFooter(
                        isLoading: isLoadingMore,
                        errorMessage: paginationError?.message,
                        onRetry: () => provider.getPosts(loadMore: true),
                      );
                    }
                    return PostListItem(post: posts[index]);
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const Screen2()),
          );
        },
        child: const Icon(Icons.arrow_forward),
      ),
    );
  }
}
