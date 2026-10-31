import 'package:flutter/material.dart';
import 'package:like/like.dart';
import '../application/shop_actions.dart';

/// Stateless presentation contract used unchanged by all three state owners.
class ShopView extends StatefulWidget {
  final String title;
  final ShopState state;
  final ShopActions actions;
  const ShopView({super.key, required this.title, required this.state, required this.actions});
  @override
  State<ShopView> createState() => _ShopViewState();
}
class _ShopViewState extends State<ShopView> {
  final _search = TextEditingController();
  final _username = TextEditingController(text: 'emilys');
  final _password = TextEditingController(text: 'emilyspass');
  @override
  void dispose() {
    _search.dispose(); _username.dispose(); _password.dispose(); super.dispose();
  }
  Future<void> _login() async {
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Public demo sign in'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('DummyJSON public test account. Never enter personal credentials.'),
        TextField(key: const Key('username'), controller: _username, decoration: const InputDecoration(labelText: 'Username')),
        TextField(key: const Key('password'), controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(key: const Key('confirm-login'), onPressed: () => Navigator.pop(context, true), child: const Text('Sign in'))]));
    if (accepted == true && mounted) { await widget.actions.login(_username.text, _password.text); }
  }
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final actions = widget.actions;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), actions: [
        if (state.customer != null) Padding(padding: const EdgeInsets.all(8), child: Center(child: Text(state.customer!.name))),
        TextButton(key: const Key('session'), onPressed: state.busy ? null : state.customer == null ? _login : actions.logout,
          child: Text(state.customer == null ? 'Sign in' : 'Sign out')),
      ]),
      body: SafeArea(child: Column(children: [
        if (state.busy) const LinearProgressIndicator(),
        StreamBuilder<LikeNetworkQualitySample>(stream: LikeNetworkQualityMonitor.shared.stream,
          builder: (context, snapshot) => snapshot.data?.quality == LikeNetworkQuality.slow
            ? const ListTile(leading: Icon(Icons.network_check), title: Text('Slow connection. Requests may take longer.')) : const SizedBox.shrink()),
        if (state.error != null) MaterialBanner(content: Text(state.error!), actions: [
          TextButton(key: const Key('retry'), onPressed: state.busy ? null : () => actions.search(state.search), child: const Text('Retry'))]),
        Expanded(child: LayoutBuilder(builder: (context, constraints) => ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Public API demo • no payment is taken • orders are simulated'),
          Row(children: [Expanded(child: TextField(key: const Key('search'), controller: _search,
            decoration: const InputDecoration(labelText: 'Search products'),
            onSubmitted: state.busy ? null : actions.search)),
            IconButton(key: const Key('search-button'), onPressed: state.busy ? null : () => actions.search(_search.text), icon: const Icon(Icons.search)),
            IconButton(key: const Key('refresh'), onPressed: state.busy ? null : () => actions.search(state.search), icon: const Icon(Icons.refresh))]),
          if (state.selected case final product?) Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            Row(children: [Expanded(child: Text(product.title, style: Theme.of(context).textTheme.titleLarge)),
              IconButton(key: const Key('close-detail'), onPressed: actions.closeDetail, icon: const Icon(Icons.close))]),
            Text(product.description), Text('\$${product.price.toStringAsFixed(2)}'),
            FilledButton(key: const Key('detail-add'), onPressed: state.busy ? null : () => actions.changeQuantity(product, 1), child: const Text('Add to cart'))]))),
          if (state.products.isEmpty && !state.busy) const Padding(padding: EdgeInsets.all(24), child: Text('No products found. Try another search.')),
          ...state.products.map((product) => Card(child: ListTile(
            key: Key('product-${product.id}'),
            leading: product.image.isEmpty ? const Icon(Icons.shopping_bag) : Image.network(product.image, width: 48, height: 48,
              errorBuilder: (context, error, stack) => const Icon(Icons.image_not_supported)),
            title: Text(product.title), subtitle: Text('\$${product.price.toStringAsFixed(2)}'),
            onTap: state.busy ? null : () => actions.select(product.id),
            trailing: IconButton(key: Key('add-${product.id}'), tooltip: 'Add to cart',
              onPressed: state.busy ? null : () => actions.changeQuantity(product, 1), icon: const Icon(Icons.add_shopping_cart))))),
          if (state.products.length < state.total) OutlinedButton(key: const Key('load-more'), onPressed: state.busy ? null : actions.loadMore, child: const Text('Load more')),
          const Divider(),
          Text('Cart', style: Theme.of(context).textTheme.headlineSmall),
          if (state.cart.isEmpty) const Text('Your cart is empty.'),
          ...state.cart.map((line) => ListTile(title: Text(line.product.title), subtitle: Text('${line.quantity} × \$${line.product.price.toStringAsFixed(2)}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(key: Key('minus-${line.product.id}'), onPressed: state.busy ? null : () => actions.changeQuantity(line.product, -1), icon: const Icon(Icons.remove)),
              IconButton(key: Key('plus-${line.product.id}'), onPressed: state.busy ? null : () => actions.changeQuantity(line.product, 1), icon: const Icon(Icons.add)),
            ]))),
          Text('Total: \$${state.cartTotal.toStringAsFixed(2)}'),
          FilledButton(key: const Key('checkout'), onPressed: state.busy || state.cart.isEmpty ? null : actions.checkout, child: const Text('Simulate checkout')),
          if (state.receipt case final receipt?) Card(child: ListTile(key: const Key('receipt'), leading: const Icon(Icons.check_circle),
            title: Text('Demo receipt #${receipt.id}'), subtitle: Text('\$${receipt.total.toStringAsFixed(2)} • no real order or charge'))),
          ExpansionTile(title: const Text('Safe request diagnostics'), children: [
            StreamBuilder<LikeRequestTrace>(stream: LikeDiagnostics.shared.stream,
              builder: (context, snapshot) => ListTile(title: Text(snapshot.hasData ? '${snapshot.data!.method} • ${snapshot.data!.phase.name}' : 'No requests yet'),
                subtitle: const Text('Request metadata only. Tokens and API payloads are never shown.'))),
          ]),
        ]))),
      ])),
    );
  }
}
