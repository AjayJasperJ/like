import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/post_provider.dart';
import '../../widgets/app_states.dart';
import '../../widgets/post_card.dart';
import 'post_detail_screen.dart';
import 'post_form_screen.dart';

class PostsScreen extends StatefulWidget {
  const PostsScreen({super.key});

  @override
  State<PostsScreen> createState() => _PostsScreenState();
}

class _PostsScreenState extends State<PostsScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<PostProvider>().load(),
    );
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
          if (provider.pagination case final pagination?)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: pagination.hasPrevious
                      ? () => provider.load(page: pagination.page - 1)
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Page ${pagination.page} of ${pagination.totalPages}'),
                IconButton(
                  onPressed: pagination.hasNext
                      ? () => provider.load(page: pagination.page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
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
    if (provider.busy && provider.posts.isEmpty) return const AppLoading();
    if (provider.error != null && provider.posts.isEmpty) {
      return AppError(message: provider.error!, onRetry: provider.load);
    }
    if (provider.posts.isEmpty) {
      return const EmptyState(message: 'No posts match your filters.');
    }
    return RefreshIndicator(
      onRefresh: provider.load,
      child: ListView.builder(
        itemCount: provider.posts.length,
        itemBuilder: (context, index) {
          final post = provider.posts[index];
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
    );
  }
}
