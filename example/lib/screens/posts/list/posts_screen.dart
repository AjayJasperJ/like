import 'package:flutter/material.dart';
import 'package:like/like.dart' hide Pagination;
import 'package:provider/provider.dart';

import '../../../data/models/api_models.dart';
import '../../../data/providers/post_provider.dart';
import '../../../widgets/app_states.dart';
import '../widgets/post_card.dart';
import '../detail/post_detail_screen.dart';
import '../form/post_form_screen.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> with LikeVisibilityMixin {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PostProvider>();
      if (provider.postsState.value.isIdle) {
        provider.load();
      }
    });
  }

  @override
  Future<void> onRecover() async {
    if (!mounted) return;
    final provider = context.read<PostProvider>();
    if (provider.postsState.value.state == LikeState.error) {
      final currentPage = provider.pagination.page ?? 1;
      await provider.load(page: currentPage);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PostProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts'),
        actions: [
          PopupMenuButton<bool?>(
            tooltip: 'Filter publication status',
            onSelected: (value) => provider.filter(
              published: value,
              clear: value == null,
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: Text('All posts')),
              PopupMenuItem(value: true, child: Text('Published')),
              PopupMenuItem(value: false, child: Text('Drafts')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchBar(
              controller: _search,
              hintText: 'Search posts',
              leading: const Icon(Icons.search),
              trailing: [
                IconButton(
                  onPressed: () {
                    _search.clear();
                    provider.filter(search: '');
                  },
                  icon: const Icon(Icons.clear),
                ),
              ],
              onSubmitted: (value) => provider.filter(search: value),
            ),
          ),
          Expanded(child: _content(provider)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PostFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('New post'),
      ),
    );
  }

  Widget _content(PostProvider provider) {
    return LikeBuilder<List<ApiPost>>(
      observe: () => provider.postsState,
      onLoading: () => const AppLoading(),
      onError: (error) => AppError(
        message: error.message,
        onRetry: provider.load,
      ),
      onException: (message, error) => AppError(
        message: 'Exception ($message)\nDetails: ${error?.rawResponse ?? ''}',
        onRetry: provider.load,
      ),
      onSuccess: (posts, isRefreshing, isSWR) {
        if (posts.isEmpty) {
          return const EmptyState(message: 'No posts match your filters.');
        }
        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (scrollInfo.metrics.pixels >=
                scrollInfo.metrics.maxScrollExtent - 200) {
              provider.loadMore();
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: provider.load,
            child: ListView.builder(
              itemCount: posts.length + 1,
              itemBuilder: (context, index) {
                if (index == posts.length) {
                  return _bottomLoaderView(provider);
                }
                final post = posts[index];
                return PostCard(
                  post: post,
                  onToggle: () => provider.toggle(post),
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PostDetailScreen(post: post),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _bottomLoaderView(PostProvider provider) {
    if (provider.postsState.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 12),
              Text(
                'Loading more posts...',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final error = provider.postsState.loadMoreError;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                'Failed to load more: ${error.message}',
                style: const TextStyle(color: Colors.red, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: provider.loadMore,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!provider.postsState.hasMore &&
        (provider.postsState.value.data?.isNotEmpty ?? false)) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            '• You reached the end •',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
