import 'package:flutter/material.dart';
import 'package:like/like.dart';

class Screen2 extends StatefulWidget {
  const Screen2({super.key});

  @override
  State<Screen2> createState() => _Screen2State();
}

class _Screen2State extends State<Screen2> with LikeVisibilityMixin {
  @override
  void onVisibilityChanged(bool visible) {
    debugPrint('Screen2 visibility: $visible');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screen 2')),
      body: Center(
        child: FilledButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const Screen3()),
            );
          },
          child: const Text('Go to Screen 3'),
        ),
      ),
    );
  }
}

class Screen3 extends StatefulWidget {
  const Screen3({super.key});

  @override
  State<Screen3> createState() => _Screen3State();
}

class _Screen3State extends State<Screen3> with LikeVisibilityMixin {
  @override
  void onVisibilityChanged(bool visible) {
    debugPrint('Screen3 visibility: $visible');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Screen 3')),
      body: const Center(
        child: Text('Top of the stack!'),
      ),
    );
  }
}
