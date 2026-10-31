import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:like_shop_shared/shop_shared.dart';

final shopRepositoryProvider = Provider<ShopRepository>((ref) => throw StateError('Repository must be injected'));
final shopProvider = NotifierProvider<ShopNotifier, ShopState>(ShopNotifier.new);
final class ShopNotifier extends Notifier<ShopState> with ShopActions {
  @override
  ShopRepository get repository => ref.read(shopRepositoryProvider);
  @override
  ShopState build() {
    ref.onDispose(closeActions);
    return const ShopState();
  }
  @override
  ShopState get snapshot => state;
  @override
  void publish(ShopState value) => state = value;
}
class ShopApp extends StatelessWidget {
  final ShopRepository repository;
  const ShopApp({super.key, required this.repository});
  @override
  Widget build(BuildContext context) => ProviderScope(overrides: [
    shopRepositoryProvider.overrideWithValue(repository)], child: MaterialApp(
      title: 'LIKE Riverpod Shop', theme: ThemeData(colorSchemeSeed: Colors.teal), home: const _ShopHome()));
}
class _ShopHome extends ConsumerStatefulWidget {
  const _ShopHome();
  @override
  ConsumerState<_ShopHome> createState() => _ShopHomeState();
}
class _ShopHomeState extends ConsumerState<_ShopHome> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() { if (mounted) { ref.read(shopProvider.notifier).initialize(); } });
  }
  @override
  Widget build(BuildContext context) => ShopView(title: 'Riverpod Shop',
    state: ref.watch(shopProvider), actions: ref.read(shopProvider.notifier));
}
