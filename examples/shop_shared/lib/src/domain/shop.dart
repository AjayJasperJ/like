/// Domain types have no Flutter, HTTP, persistence or state management dependency.
final class Product {
  final int id;
  final String title, description, image;
  final double price;
  const Product(this.id, this.title, this.description, this.image, this.price);
  factory Product.fromJson(Map<String, dynamic> value) => Product(
    value['id'] as int, value['title'] as String,
    value['description'] as String? ?? '', value['thumbnail'] as String? ?? '',
    (value['price'] as num).toDouble());
  Map<String, dynamic> toJson() => {'id': id, 'title': title,
    'description': description, 'thumbnail': image, 'price': price};
}
final class ProductPage {
  final List<Product> products;
  final int total;
  const ProductPage(this.products, this.total);
}
final class Customer {
  final int id;
  final String name;
  const Customer(this.id, this.name);
}
final class CartLine {
  final Product product;
  final int quantity;
  const CartLine(this.product, this.quantity);
  double get total => product.price * quantity;
}
final class Receipt {
  final int id;
  final double total;
  const Receipt(this.id, this.total);
}
abstract interface class ShopRepository {
  Future<Customer?> restore();
  Future<Customer> login(String username, String password);
  Future<void> logout();
  Future<ProductPage> products({required String search, required int skip});
  Future<Product> product(int id);
  Future<List<CartLine>> loadCart();
  Future<void> saveCart(List<CartLine> cart);
  Future<Receipt> checkout(List<CartLine> cart);
  void dispose();
}
final class ShopFailure implements Exception {
  final String message;
  const ShopFailure(this.message);
  @override
  String toString() => message;
}
