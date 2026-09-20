import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';

import '../../models/api_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/post_provider.dart';
import 'post_form_screen.dart';

class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({required this.post, super.key});

  final ApiPost post;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> with LikeVisibilityMixin {
  late ApiPost _post;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  Future<void> onRecover() async {
    if (!mounted) return;
    await _reload();
  }

  Future<void> _reload() async {
    final result = await context.read<PostProvider>().find(_post.id);
    if (result.isSuccess && result.data != null && mounted) {
      setState(() => _post = result.data!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = context.watch<AuthProvider>().user?.id == _post.userId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        actions: [
          if (mine)
            IconButton(
              tooltip: 'Edit',
              onPressed: _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (mine)
            IconButton(
              tooltip: 'Delete',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(_post.title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text('User ${_post.userId}')),
              Chip(label: Text(_post.published ? 'Published' : 'Draft')),
            ],
          ),
          const Divider(height: 32),
          Text(_post.body, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final updated = await Navigator.of(context).push<ApiPost>(
      MaterialPageRoute(builder: (_) => PostFormScreen(post: _post)),
    );
    if (updated != null && mounted) setState(() => _post = updated);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await context.read<PostProvider>().remove(_post.id);

    if (!mounted) return;
    await updateNotifier<Object>(
      response: result.toStateResponse(),
      context: context,
      onSuccess: (_) async {
        Navigator.of(context).pop();
      },
      enableHaptics: true,
      disableSuccessToast: false,
    );
  }
}
