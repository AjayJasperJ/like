import 'package:flutter/material.dart';
import 'package:like_shop_shared/shop_shared.dart';
import 'shop_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repository = await createShopRepository('like_bloc_shop');
    runApp(ShopApp(repository: repository));
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to open local storage. Please retry.'),
                FilledButton(onPressed: main, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
