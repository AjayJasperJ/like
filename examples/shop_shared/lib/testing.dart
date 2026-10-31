/// Deterministic repository fixture for adapter and end-to-end UI tests.
/// Production entry points never import this library.
import 'shop_shared.dart';
final class FixtureShopRepository implements ShopRepository {
  static const item = Product(1, 'Fixture phone', 'A deterministic product', '', 12.5);
  bool disposed = false;
  bool failNext = false;
  bool signedIn = false;
  int checkoutCalls = 0;
  List<CartLine> cart = [];
  @override
  Future<Customer?> restore() async => signedIn ? const Customer(1, 'Demo') : null;
  @override
  Future<Customer> login(String username, String password) async {
    if (username != 'emilys' || password != 'emilyspass') {
      throw const ShopFailure('Invalid demo credentials.');
    }
    signedIn = true;
    return const Customer(1, 'Demo');
  }
  @override
  Future<void> logout() async { signedIn = false; cart = []; }
  @override
  Future<ProductPage> products({required String search, required int skip}) async {
    if (failNext) { failNext = false; throw const ShopFailure('Offline fixture'); }
    return ProductPage(search == 'missing' ? [] : [item], search == 'missing' ? 0 : 1);
  }
  @override
  Future<Product> product(int id) async => item;
  @override
  Future<List<CartLine>> loadCart() async => List.of(cart);
  @override
  Future<void> saveCart(List<CartLine> value) async { cart = List.of(value); }
  @override
  Future<Receipt> checkout(List<CartLine> value) async {
    if (!signedIn) { throw const ShopFailure('Sign in before checkout.'); }
    checkoutCalls++;
    final total = value.fold<double>(0, (sum, line) => sum + line.total);
    cart = [];
    return Receipt(42, total);
  }
  @override
  void dispose() { disposed = true; }
}
