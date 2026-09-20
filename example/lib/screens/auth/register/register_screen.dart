import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';

import '../../../data/models/api_models.dart';
import '../../../data/providers/auth_provider.dart';
import '../widgets/auth_form.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with LikeVisibilityMixin {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Join Like',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 24),
                    if (auth.error != null) ...[
                      Text(auth.error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 12),
                    ],
                    IgnorePointer(
                      ignoring: auth.busy,
                      child: AuthForm(
                        collectName: true,
                        submitLabel:
                            auth.busy ? 'Creating account…' : 'Register',
                        onSubmit: (name, email, password) async {
                          final provider = context.read<AuthProvider>();
                          await provider.register(name, email, password);
                          if (!context.mounted) return;
                          await updateNotifier<ApiUser>(
                            response: provider.authState.value,
                            context: context,
                            onSuccess: (_) async {
                              Navigator.of(context).pop();
                            },
                            enableHaptics: true,
                            disableSuccessToast: false,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
