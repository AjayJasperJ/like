import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:like_shop_shared/shop_shared.dart';

final class ShopCubit extends Cubit<ShopState> with ShopActions {
  @override
  final ShopRepository repository;
  ShopCubit(this.repository) : super(const ShopState());
  @override
  ShopState get snapshot => state;
  @override
  void publish(ShopState value) => emit(value);
  @override
  Future<void> close() {
    closeActions();
    return super.close();
  }
}

class ShopApp extends StatelessWidget {
  final ShopRepository repository;
  const ShopApp({super.key, required this.repository});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ShopCubit(repository)..initialize(),
    child: MaterialApp(
      title: 'LIKE BLoC Shop',
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange),
      home: BlocBuilder<ShopCubit, ShopState>(
        builder: (context, state) => ShopView(
          title: 'BLoC Shop',
          state: state,
          actions: context.read<ShopCubit>(),
        ),
      ),
    ),
  );
}
