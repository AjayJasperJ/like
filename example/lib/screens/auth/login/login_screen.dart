import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';

import '../../../data/models/api_models.dart';
import '../../../data/providers/auth_provider.dart';
import '../widgets/auth_form.dart';
import '../register/register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with LikeVisibilityMixin {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
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
                    Icon(Icons.hub_outlined,
                        size: 56, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('Welcome back',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 8),
                    Text('Sign in to manage your posts',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 28),
                    if (auth.error != null) ...[
                      Text(auth.error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 12),
                    ],
                    IgnorePointer(
                      ignoring: auth.busy,
                      child: AuthForm(
                        submitLabel: auth.busy ? 'Signing in…' : 'Sign in',
                        onSubmit: (_, email, password) async {
                          final provider = context.read<AuthProvider>();
                          await provider.login(email, password);
                          if (!context.mounted) return;
                          await updateNotifier<ApiUser>(
                            response: provider.authState.value,
                            context: context,
                            enableHaptics: true,
                            disableSuccessToast: false,
                          );
                        },
                      ),
                    ),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              ),
                      child: const Text('Create an account'),
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
