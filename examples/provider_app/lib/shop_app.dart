import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:like_shop_shared/shop_shared.dart';

final class ShopProvider extends ChangeNotifier with ShopActions {
  @override
  final ShopRepository repository;
  ShopState _state = const ShopState();
  ShopProvider(this.repository);
  @override
  ShopState get snapshot => _state;
  @override
  void publish(ShopState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    closeActions();
    super.dispose();
  }
}

class ShopApp extends StatelessWidget {
  final ShopRepository repository;
  const ShopApp({super.key, required this.repository});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => ShopProvider(repository)..initialize(),
    child: MaterialApp(
      title: 'LIKE Provider Shop',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      home: Consumer<ShopProvider>(
        builder: (context, owner, child) => ShopView(
          title: 'Provider Shop',
          state: owner.snapshot,
          actions: owner,
        ),
      ),
    ),
  );
}
