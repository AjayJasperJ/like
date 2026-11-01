import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:like/like.dart';
import '../domain/shop.dart';

abstract interface class SessionStore {
  Future<String?> read();
  Future<void> write(String? value);
}

final class SecureSessionStore implements SessionStore {
  final FlutterSecureStorage storage;
  const SecureSessionStore([this.storage = const FlutterSecureStorage()]);
  @override
  Future<String?> read() => storage.read(key: 'dummyjson_session');
  @override
  Future<void> write(String? value) => value == null
      ? storage.delete(key: 'dummyjson_session')
      : storage.write(key: 'dummyjson_session', value: value);
}

/// The service only knows the injectable HTTP contract.
final class ShopApi {
  final LikeHttpClient http;
  const ShopApi(this.http);
  Map<String, dynamic> _body(ApiResult<Response> result) {
    if (!result.isSuccess || result.data?.data is! Map) {
      throw const ShopFailure(
        'Request failed. Check your connection and retry.',
      );
    }
    return Map<String, dynamic>.from(result.data!.data as Map);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) async => _body(
    await http.get(
      path,
      query: query,
      headers: headers,
      disableCache: path.startsWith('/auth/'),
    ),
  );
  Future<Map<String, dynamic>> post(
    String path,
    Object body, {
    Map<String, String>? headers,
  }) async => _body(
    await http.post(path, body: body, headers: headers, offlineSync: false),
  );
}

/// Tokens never enter Hive, application state, widgets or diagnostic messages.
final class PublicShopRepository implements ShopRepository {
  final ShopApi api;
  final SessionStore sessions;
  final Box<dynamic> cartBox;
  final void Function(Customer?) setScope;
  final void Function() closeClient;
  Customer? _customer;
  String? _accessToken, _refreshToken;
  PublicShopRepository(
    this.api,
    this.sessions,
    this.cartBox, {
    required this.setScope,
    required this.closeClient,
  });
  Future<Customer> _accept(Map<String, dynamic> json) async {
    final customer = Customer(
      json['id'] as int,
      '${json['firstName'] ?? ''} ${json['lastName'] ?? ''}'.trim(),
    );
    _accessToken = json['accessToken'] as String;
    _refreshToken = json['refreshToken'] as String;
    await sessions.write(
      jsonEncode({'accessToken': _accessToken, 'refreshToken': _refreshToken}),
    );
    _customer = customer;
    setScope(customer);
    return customer;
  }

  @override
  Future<Customer> login(String username, String password) async => _accept(
    await api.post('/auth/login', {
      'username': username,
      'password': password,
      'expiresInMins': 30,
    }),
  );
  @override
  Future<Customer?> restore() async {
    final saved = await sessions.read();
    if (saved == null) {
      return null;
    }
    final json = jsonDecode(saved) as Map;
    _accessToken = json['accessToken'] as String?;
    _refreshToken = json['refreshToken'] as String?;
    try {
      final me = await api.get('/auth/me', headers: _headers);
      _customer = Customer(me['id'] as int, me['firstName'] as String);
      setScope(_customer);
      return _customer;
    } on ShopFailure {
      if (_refreshToken == null) {
        rethrow;
      }
      final tokens = await api.post('/auth/refresh', {
        'refreshToken': _refreshToken,
        'expiresInMins': 30,
      });
      _accessToken = tokens['accessToken'] as String;
      final me = await api.get('/auth/me', headers: _headers);
      return _accept({...me, ...tokens});
    }
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer $_accessToken'};
  @override
  Future<void> logout() async {
    await sessions.write(null);
    _accessToken = null;
    _refreshToken = null;
    _customer = null;
    setScope(null);
  }

  @override
  Future<ProductPage> products({
    required String search,
    required int skip,
  }) async {
    final json = await api.get(
      search.isEmpty ? '/products' : '/products/search',
      query: {'limit': 12, 'skip': skip, if (search.isNotEmpty) 'q': search},
    );
    return ProductPage(
      (json['products'] as List)
          .map((p) => Product.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList(),
      json['total'] as int,
    );
  }

  @override
  Future<Product> product(int id) async =>
      Product.fromJson(await api.get('/products/$id'));
  String get _cartKey => 'cart:${_customer?.id ?? 'guest'}';
  @override
  Future<List<CartLine>> loadCart() async =>
      ((cartBox.get(_cartKey) as List?) ?? []).map((item) {
        final value = Map<String, dynamic>.from(item as Map);
        return CartLine(
          Product.fromJson(Map<String, dynamic>.from(value['product'] as Map)),
          value['quantity'] as int,
        );
      }).toList();
  @override
  Future<void> saveCart(List<CartLine> cart) => cartBox.put(
    _cartKey,
    cart
        .map(
          (line) => {
            'product': line.product.toJson(),
            'quantity': line.quantity,
          },
        )
        .toList(),
  );
  @override
  Future<Receipt> checkout(List<CartLine> cart) async {
    if (_customer == null) {
      throw const ShopFailure('Sign in before checkout.');
    }
    if (cart.isEmpty) {
      throw const ShopFailure('Your cart is empty.');
    }
    final json = await api.post('/carts/add', {
      'userId': _customer!.id,
      'products': cart
          .map((line) => {'id': line.product.id, 'quantity': line.quantity})
          .toList(),
    }, headers: _headers);
    final receipt = Receipt(
      json['id'] as int,
      (json['total'] as num).toDouble(),
    );
    // DummyJSON simulates mutations. This receipt is explicitly a demo receipt.
    await cartBox.put('receipt:${_customer!.id}', {
      'id': receipt.id,
      'total': receipt.total,
    });
    await saveCart([]);
    return receipt;
  }

  @override
  void dispose() => closeClient();
}

Future<ShopRepository> createShopRepository(String projectName) async {
  await LikeService.init(
    config: LikeConfig(
      projectName: projectName,
      baseUrl: 'https://dummyjson.com',
      supportWeb: true,
      withAuthByDefault: false,
      enableLogging: false,
    ),
  );
  final client = LikeClient.scoped(
    const LikeClientConfig(baseUrl: 'https://dummyjson.com'),
  );
  final box = await Hive.openBox<dynamic>('${projectName}_cart');
  return PublicShopRepository(
    ShopApi(client),
    const SecureSessionStore(),
    box,
    setScope: (customer) => client.setSessionScope(
      LikeSessionScope(
        environment: 'dummyjson',
        accountId: customer?.id.toString(),
      ),
    ),
    closeClient: client.dispose,
  );
}
