import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';
import 'package:like_devtool/like_devtool.dart';
import 'providers/post_provider.dart';
import 'repositories/post_repository.dart';
import 'ui/posts_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Like package
  await LikeService.init(
    config: LikeConfig(
      projectName: 'like_example_app',
      baseUrl: 'https://jsonplaceholder.typicode.com',
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PostProvider(PostRepository()),
        ),
      ],
      child: MaterialApp(
        title: 'Like Resync Example',
        navigatorObservers: [likeRouteObserver],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            scrolledUnderElevation: 1,
          ),
          cardTheme: const CardThemeData(
            elevation: 2,
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
        ),
        home: Like(
            devTool: (child) => LikeDevTool(child: child),
            child: const PostsPage()),
      ),
    );
  }
}
