import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:like_shop_shared/shop_shared.dart';
import 'package:like_shop_shared/testing.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('production repository uses public HTTPS API and real native storage', (tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final repository = await createShopRepository('like_live_native_fixture');
    addTearDown(() async {
      try { await repository.logout(); }
      finally { repository.dispose(); await closeLiveShopTestResources(); }
    });
    final customer = await repository.login('emilys', 'emilyspass');
    expect(customer.id, greaterThan(0));
    expect((await repository.restore())!.id, customer.id);
    final page = await repository.products(search: '', skip: 0);
    expect(page.products, isNotEmpty);
    final item = await repository.product(page.products.first.id);
    await repository.saveCart([CartLine(item, 2)]);
    expect((await repository.loadCart()).single.quantity, 2);
    final receipt = await repository.checkout(await repository.loadCart());
    expect(receipt.id, greaterThan(0));
    expect(receipt.total, greaterThan(0));
    expect(await repository.loadCart(), isEmpty);
    await repository.logout();
    expect(await repository.restore(), isNull);
  });
}
