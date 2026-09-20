import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';

import '../../models/api_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/post_provider.dart';

class PostFormScreen extends StatefulWidget {
  const PostFormScreen({this.post, super.key});

  final ApiPost? post;

  @override
  State<PostFormScreen> createState() => _PostFormScreenState();
}

class _PostFormScreenState extends State<PostFormScreen> with LikeVisibilityMixin {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _body;
  late bool _published;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.post?.title);
    _body = TextEditingController(text: widget.post?.body);
    _published = widget.post?.published ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final posts = context.watch<PostProvider>();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.post == null ? 'New post' : 'Edit post'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _key,
          child: Column(
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _body,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(labelText: 'Content'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Content is required'
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Published'),
                value: _published,
                onChanged: (value) => setState(() => _published = value),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: posts.busy ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(posts.busy ? 'Saving…' : 'Save post'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_key.currentState?.validate() != true) return;
    final user = context.read<AuthProvider>().user!;
    final result = await context.read<PostProvider>().save(
          post: widget.post,
          title: _title.text.trim(),
          body: _body.text.trim(),
          published: _published,
          userId: user.id,
        );

    if (!mounted) return;
    await updateNotifier<ApiPost>(
      response: result.toStateResponse(),
      context: context,
      onSuccess: (saved) async {
        Navigator.of(context).pop(saved);
      },
      enableHaptics: true,
      disableSuccessToast: false,
    );
  }
}
