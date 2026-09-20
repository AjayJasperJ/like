import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';

import '../../../data/providers/system_provider.dart';

class ApiToolsScreen extends StatefulWidget {
  const ApiToolsScreen({super.key});

  @override
  State<ApiToolsScreen> createState() => _ApiToolsScreenState();
}

class _ApiToolsScreenState extends State<ApiToolsScreen>
    with LikeVisibilityMixin {
  final _status = TextEditingController(text: '200');
  final _delay = TextEditingController(text: '500');

  @override
  Future<void> onRecover() async {
    if (!mounted) return;
    final tools = context.read<SystemProvider>();
    if (tools.error != null) {
      await tools.retryLastAction();
    }
  }

  @override
  void dispose() {
    _status.dispose();
    _delay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tools = context.watch<SystemProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('API tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                  onPressed: tools.busy ? null : tools.metadata,
                  child: const Text('Metadata')),
              FilledButton.tonal(
                  onPressed: tools.busy ? null : tools.health,
                  child: const Text('Health')),
              FilledButton.tonal(
                  onPressed: tools.busy ? null : tools.reset,
                  child: const Text('Reset posts')),
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: tools.busy ? null : tools.triggerException,
                child: const Text('Trigger Exception'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _status,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'HTTP status'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: tools.busy
                    ? null
                    : () => tools.status(int.tryParse(_status.text) ?? 200),
                child: const Text('Send'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _delay,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Delay milliseconds'),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: tools.busy
                    ? null
                    : () => tools.delay(int.tryParse(_delay.text) ?? 500),
                child: const Text('Send'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          LikeBuilder<String>(
            observe: () => tools.systemState,
            onIdle: () => const SizedBox.shrink(),
            onLoading: () => const LinearProgressIndicator(),
            onError: (error) => Text(
              error.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onException: (message, error) => Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Theme.of(context).colorScheme.error),
                        const SizedBox(width: 8),
                        Text(
                          'Client Exception Caught',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(message),
                    ...[
                      const SizedBox(height: 4),
                      Text(
                        'Raw: ${error?.toString()}',
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            onSuccess: (output, _, __) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(output),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
