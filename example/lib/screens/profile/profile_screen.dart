import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with LikeVisibilityMixin {
  @override
  Future<void> onRecover() async {
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    if (auth.error != null) {
      await auth.restoreSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user!;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 46,
              child: Text(user.name.substring(0, 1).toUpperCase(),
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Name'),
                  subtitle: Text(user.name),
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Email'),
                  subtitle: Text(user.email),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Member since'),
                  subtitle: Text(user.createdAt.toLocal().toString()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: auth.busy ? null : auth.logout,
            icon: const Icon(Icons.logout),
            label: Text(auth.busy ? 'Signing out…' : 'Sign out'),
          ),
        ],
      ),
    );
  }
}
