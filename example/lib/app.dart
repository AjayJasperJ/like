import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'widgets/app_states.dart';
import 'di.dart';

class LikeServerApp extends StatelessWidget {
  const LikeServerApp({super.key});
  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: DependencyInjection.value,
        child: MaterialApp(
          title: 'Like Posts',
          debugShowCheckedModeBanner: false,
          navigatorObservers: [likeRouteObserver],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
            useMaterial3: true,
            inputDecorationTheme:
                const InputDecorationTheme(border: OutlineInputBorder()),
          ),
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
