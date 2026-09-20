import 'package:flutter/material.dart';

import '../../../data/models/api_models.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    required this.post,
    required this.onOpen,
    required this.onToggle,
    super.key,
  });

  final ApiPost post;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Text('${post.id}')),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(post.body,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Text('By user ${post.userId}'),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: post.published ? 'Unpublish' : 'Publish',
                  onPressed: onToggle,
                  icon: Icon(post.published
                      ? Icons.public
                      : Icons.public_off_outlined),
                ),
              ],
            ),
          ),
        ),
      );
}
