import 'package:flutter/material.dart';
import 'package:like/like.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize the LIKE engine
  // This handles Hive, Connectivity, and default Client setup.
  runApp(const LikeExampleApp());
}

class LikeExampleApp extends StatelessWidget {
  const LikeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 2. The 'Like' widget is the root wrapper (replaces original LikeRootWrapper)
    return Like(
      baseUrl: 'https://jsonplaceholder.typicode.com',
      child: MaterialApp(
        title: 'LIKE Package Example',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        home: const UserListScreen(),
      ),
    );
  }
}

class UserListScreen extends StatefulWidget {
  const UserListScreen({super.key});

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  // 3. Define the response state to observe
  late ValueNotifier<LikeStateResponse<List<dynamic>>> _usersNotifier;

  @override
  void initState() {
    super.initState();
    // Initialize with an idle state
    _usersNotifier = ValueNotifier(LikeStateResponse.idle());
    
    // Initial fetch
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    _usersNotifier.value = LikeStateResponse.loading();
    
    final result = await LikeClient().get(
      '/users',
      ars: const ARS(staleWhileRevalidate: true),
    );

    // LikeClient.get returns a LikeApiResult, which can be converted to LikeStateResponse
    _usersNotifier.value = LikeStateResponse.fromResult(result);
  }

  @override
  void dispose() {
    _usersNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LIKE Engine Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUsers,
          ),
        ],
      ),
      body: LikeBuilder<List<dynamic>>(
        // 4. Observe the state response
        observe: () => _usersNotifier.value,
        // 5. Handle success (including SWR and Refreshing states)
        onSuccess: (users, isRefreshing, isFromSWR) {
          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: _fetchUsers,
                child: ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return ListTile(
                      leading: CircleAvatar(child: Text(user['name'][0])),
                      title: Text(user['name']),
                      subtitle: Text(user['email']),
                      trailing: isFromSWR 
                        ? const Icon(Icons.history, color: Colors.orange)
                        : const Icon(Icons.check_circle, color: Colors.green),
                    );
                  },
                ),
              ),
              if (isRefreshing)
                const Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
            ],
          );
        },
        // 6. Handle loading (Initial)
        onLoading: () => const Center(child: CircularProgressIndicator()),
        // 7. Handle errors
        onError: (error) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(error.message),
              ElevatedButton(
                onPressed: _fetchUsers,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          LikeClient().post(
            '/posts',
            body: {'title': 'Example', 'body': 'Offline sync demo'},
            offlineSync: true,
          );
        },
        child: const Icon(Icons.send),
      ),
    );
  }
}
