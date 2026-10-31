import '../domain/shop.dart';

/// Immutable state shared as a contract. Each app owns it with its chosen library.
final class ShopState {
  final Customer? customer;
  final List<Product> products;
  final List<CartLine> cart;
  final Product? selected;
  final Receipt? receipt;
  final bool busy;
  final String search;
  final String? error;
  final int total;
  const ShopState({this.customer, this.products = const [], this.cart = const [],
    this.selected, this.receipt, this.busy = false, this.search = '',
    this.error, this.total = 0});
  double get cartTotal => cart.fold(0, (sum, line) => sum + line.total);
  ShopState copy({Customer? customer, List<Product>? products, List<CartLine>? cart,
    Product? selected, Receipt? receipt, bool? busy, String? search, String? error,
    int? total, bool clearSelection = false}) => ShopState(
      customer: customer ?? this.customer, products: products ?? this.products,
      cart: cart ?? this.cart, selected: clearSelection ? null : selected ?? this.selected,
      receipt: receipt ?? this.receipt, busy: busy ?? this.busy,
      search: search ?? this.search, error: error, total: total ?? this.total);
}
/// Reusable application use cases; presentation adapters own publication/lifecycle.
/// Serial mutations prevent double checkout. Generations suppress stale async results.
mixin ShopActions {
  ShopRepository get repository;
  ShopState get snapshot;
  void publish(ShopState state);
  int _generation = 0;
  bool _closed = false;
  Future<void> _run(Future<ShopState> Function(ShopState) action) async {
    if (_closed || snapshot.busy) { return; }
    final generation = ++_generation;
    final before = snapshot;
    publish(before.copy(busy: true));
    try {
      final next = await action(before);
      if (!_closed && generation == _generation) { publish(next.copy(busy: false)); }
    } catch (error) {
      if (!_closed && generation == _generation) {
        publish(before.copy(error: error is ShopFailure ? error.message : 'Unable to complete action. Please retry.', busy: false));
      }
    }
  }
  Future<void> initialize() => _run((state) async {
    final customer = await repository.restore();
    final page = await repository.products(search: '', skip: 0);
    return ShopState(customer: customer, products: List.unmodifiable(page.products),
      total: page.total, cart: List.unmodifiable(await repository.loadCart()));
  });
  Future<void> login(String username, String password) => _run((state) async {
    final customer = await repository.login(username, password);
    return state.copy(customer: customer, cart: List.unmodifiable(await repository.loadCart()));
  });
  Future<void> logout() => _run((state) async {
    await repository.logout();
    return ShopState(products: state.products, total: state.total,
      search: state.search, cart: List.unmodifiable(await repository.loadCart()));
  });
  Future<void> search(String query) => _run((state) async {
    final page = await repository.products(search: query.trim(), skip: 0);
    return state.copy(products: List.unmodifiable(page.products), search: query.trim(),
      total: page.total, clearSelection: true);
  });
  Future<void> loadMore() => _run((state) async {
    if (state.products.length >= state.total) { return state; }
    final page = await repository.products(search: state.search, skip: state.products.length);
    final byId = {for (final product in [...state.products, ...page.products]) product.id: product};
    return state.copy(products: List.unmodifiable(byId.values), total: page.total);
  });
  Future<void> select(int id) => _run((state) async => state.copy(selected: await repository.product(id)));
  void closeDetail() { if (!_closed) { publish(snapshot.copy(clearSelection: true)); } }
  Future<void> changeQuantity(Product product, int delta) => _run((state) async {
    final lines = [...state.cart];
    final index = lines.indexWhere((line) => line.product.id == product.id);
    final quantity = (index < 0 ? 0 : lines[index].quantity) + delta;
    if (index >= 0) { lines.removeAt(index); }
    if (quantity > 0) { lines.add(CartLine(product, quantity.clamp(1, 99))); }
    await repository.saveCart(lines);
    return state.copy(cart: List.unmodifiable(lines));
  });
  Future<void> checkout() => _run((state) async => state.copy(
    receipt: await repository.checkout(state.cart), cart: const []));
  void closeActions() { _closed = true; _generation++; repository.dispose(); }
}
