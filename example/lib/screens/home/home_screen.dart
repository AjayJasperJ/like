import 'package:flutter/material.dart';

import '../posts/posts_screen.dart';
import '../profile/profile_screen.dart';
import '../tools/api_tools_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _pages = [
    PostsScreen(),
    ApiToolsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _pages.length; i++)
              TickerMode(
                enabled: i == _index,
                child: _pages[i],
              ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article),
              label: 'Posts',
            ),
            NavigationDestination(
              icon: Icon(Icons.build_outlined),
              selectedIcon: Icon(Icons.build),
              label: 'Tools',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      );
}
