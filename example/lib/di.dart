import 'package:like/like.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'providers/auth_provider.dart';
import 'providers/post_provider.dart';
import 'providers/system_provider.dart';
import 'repositories/auth_repository.dart';
import 'repositories/post_repository.dart';
import 'repositories/system_repository.dart';
import 'services/auth_api_service.dart';
import 'services/post_api_service.dart';
import 'services/system_api_service.dart';
import 'services/token_storage_service.dart';

class DependencyInjection {
  static List<SingleChildWidget> get value => [
        // ==========================================
        // 1. Services Layer (Stateless / Singletons)
        // ==========================================
        Provider(create: (_) => TokenStorageService()),
        Provider(create: (_) => AuthApiService()),
        Provider(create: (_) => PostApiService()),
        // SystemApiService automatically encapsulates its scoped secondary client
        Provider(create: (_) => SystemApiService()),

        // ==========================================
        // 2. Repositories Layer
        // ==========================================
        Provider<AuthRepository>(
          create: (context) => AuthRepository(
            context.read<AuthApiService>(),
            context.read<TokenStorageService>(),
          ),
        ),
        Provider<PostRepository>(
          create: (context) => PostRepository(
            context.read<PostApiService>(),
          ),
        ),
        Provider<SystemRepository>(
          create: (context) => SystemRepository(
            context.read<SystemApiService>(),
          ),
        ),

        // ==========================================
        // 3. Providers / ViewModels Layer
        // ==========================================
        ChangeNotifierProvider<AuthProvider>(
          create: (context) {
            final authProvider = AuthProvider(
              context.read<AuthRepository>(),
              context.read<TokenStorageService>(),
            );

            // Attach dynamic authConfig to LikeConstants for the primary client
            LikeConstants.apply(
              LikeConstants.current.copyWith(
                authConfig: authProvider.createAuthConfig(),
              ),
            );

            // Restore active session asynchronously
            authProvider.restoreSession();

            return authProvider;
          },
        ),
        ChangeNotifierProvider<PostProvider>(
          create: (context) => PostProvider(
            context.read<PostRepository>(),
          ),
        ),
        ChangeNotifierProvider<SystemProvider>(
          create: (context) => SystemProvider(
            context.read<SystemRepository>(),
          ),
        ),
      ];
}
