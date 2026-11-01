import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like_shop_shared/testing.dart';
import 'package:like_provider_app/shop_app.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 15),
  );
}

void main() {
  testWidgets('guest to authenticated checkout, search, retry and disposal', (
    tester,
  ) async {
    final repository = FixtureShopRepository();
    await tester.pumpWidget(ShopApp(repository: repository));
    await settle(tester);
    expect(find.text('Fixture phone'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('load-more')));
    await tester.tap(find.byKey(const Key('load-more')));
    await settle(tester);
    expect(find.text('Fixture laptop'), findsOneWidget);
    await tester.tap(find.byKey(const Key('session')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-login')));
    await settle(tester);
    expect(find.text('Sign out'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('product-1')));
    await tester.tap(find.byKey(const Key('product-1')));
    await settle(tester);
    expect(find.text('A deterministic product'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('detail-add')));
    await tester.tap(find.byKey(const Key('detail-add')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('plus-1')));
    await tester.tap(find.byKey(const Key('plus-1')));
    await settle(tester);
    expect(repository.cart.single.quantity, 2);
    await tester.tap(find.byKey(const Key('minus-1')));
    await settle(tester);
    expect(repository.cart.single.quantity, 1);
    await tester.ensureVisible(find.byKey(const Key('checkout')));
    await tester.tap(find.byKey(const Key('checkout')));
    await settle(tester);
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
    await settle(tester);
    expect(find.text('No products found. Try another search.'), findsOneWidget);
    repository.failNext = true;
    await tester.tap(find.byKey(const Key('refresh')));
    await settle(tester);
    expect(find.text('Offline fixture'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry')));
    await settle(tester);
    expect(find.text('Offline fixture'), findsNothing);
    await tester.tap(find.byKey(const Key('session')));
    await settle(tester);
    expect(find.text('Sign in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    expect(repository.disposed, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
