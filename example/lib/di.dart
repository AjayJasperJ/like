import 'package:like/like.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'data/providers/auth_provider.dart';
import 'data/providers/post_provider.dart';
import 'data/providers/system_provider.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/post_repository.dart';
import 'data/repositories/system_repository.dart';
import 'data/services/auth_api_service.dart';
import 'data/services/post_api_service.dart';
import 'data/services/system_api_service.dart';
import 'data/storage/token_storage.dart';

abstract final class DependencyInjection {
  static List<SingleChildWidget> get value => [
        // Data sources and API services.
        Provider(create: (_) => TokenStorageService()),
        Provider(create: (_) => AuthApiService()),
        Provider(create: (_) => PostApiService()),
        Provider(create: (_) => SystemApiService()),

        // Repositories expose application-focused operations.
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

        // Providers own presentation state.
        ChangeNotifierProvider<AuthProvider>(
          create: (context) {
            final authProvider = AuthProvider(
              context.read<AuthRepository>(),
              context.read<TokenStorageService>(),
            );

            LikeConstants.apply(
              LikeConstants.current.copyWith(
                authConfig: authProvider.createAuthConfig(),
              ),
            );

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
