import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like_shop_shared/testing.dart';
import 'package:like_provider_app/shop_app.dart';

void main() {
  testWidgets('guest to authenticated checkout, search, retry and disposal', (
    tester,
  ) async {
    final repository = FixtureShopRepository();
    await tester.pumpWidget(ShopApp(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('Fixture phone'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('load-more')));
    await tester.tap(find.byKey(const Key('load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Fixture laptop'), findsOneWidget);
    await tester.tap(find.byKey(const Key('session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-login')));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('product-1')));
    await tester.tap(find.byKey(const Key('product-1')));
    await tester.pumpAndSettle();
    expect(find.text('A deterministic product'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('detail-add')));
    await tester.tap(find.byKey(const Key('detail-add')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('plus-1')));
    await tester.tap(find.byKey(const Key('plus-1')));
    await tester.pumpAndSettle();
    expect(repository.cart.single.quantity, 2);
    await tester.tap(find.byKey(const Key('minus-1')));
    await tester.pumpAndSettle();
    expect(repository.cart.single.quantity, 1);
    await tester.ensureVisible(find.byKey(const Key('checkout')));
    await tester.tap(find.byKey(const Key('checkout')));
    await tester.pumpAndSettle();
    expect(repository.checkoutCalls, 1);
    expect(repository.cart, isEmpty);
    await tester.ensureVisible(find.byKey(const Key('receipt')));
    expect(find.text('Demo receipt #42'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('search')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('search')), 'missing');
    await tester.tap(find.byKey(const Key('search-button')));
    await tester.pumpAndSettle();
    expect(find.text('No products found. Try another search.'), findsOneWidget);
    repository.failNext = true;
    await tester.tap(find.byKey(const Key('refresh')));
    await tester.pumpAndSettle();
    expect(find.text('Offline fixture'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry')));
    await tester.pumpAndSettle();
    expect(find.text('Offline fixture'), findsNothing);
    await tester.tap(find.byKey(const Key('session')));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(repository.disposed, isTrue);
  });
}
