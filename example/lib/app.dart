import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'data/providers/auth_provider.dart';
import 'di.dart';
import 'screens/auth/login/login_screen.dart';
import 'screens/home/dashboard/home_screen.dart';
import 'widgets/app_states.dart';

class LikeServerApp extends StatelessWidget {
  const LikeServerApp({super.key});

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: DependencyInjection.value,
        child: MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          navigatorObservers: [likeRouteObserver],
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
          home: Like(
            child: Consumer<AuthProvider>(
              builder: (_, auth, __) {
                if (auth.initializing) {
                  return const Scaffold(
                    body: AppLoading(label: 'Restoring session…'),
                  );
                }
                return auth.isAuthenticated
                    ? const HomeScreen()
                    : const LoginScreen();
              },
            ),
          ),
        ),
      );
}
