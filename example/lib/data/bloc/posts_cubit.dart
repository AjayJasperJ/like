import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/api_models.dart';
import '../repositories/post_repository.dart';

final class PostsCubit extends Cubit<LikeStateResponse<PaginatedPosts>> {
  PostsCubit(
    PostsRepository repository, {
    LikeQuery<PaginatedPosts> Function(int)? watch,
  }) : _watch = watch ?? repository.watchPage,
       super(LikeStateResponse.idle());
  final LikeQuery<PaginatedPosts> Function(int) _watch;
  LikeQuery<PaginatedPosts>? _query;
  StreamSubscription<LikeStateResponse<PaginatedPosts>>? _subscription;
  int _generation = 0;
  Future<void> load({int page = 1}) async {
    if (isClosed) return;
    final generation = ++_generation;
    await _subscription?.cancel();
    await _query?.dispose();
    if (isClosed || generation != _generation) return;
    final query = _watch(page);
    _query = query;
    emit(LikeStateResponse.loading());
    _subscription = query.watch().listen((state) {
      if (!isClosed &&
          generation == _generation &&
          identical(state, query.state)) {
        emit(state);
      }
    });
    await query.refresh();
    if (!isClosed && generation == _generation) emit(query.state);
  }

  @override
  Future<void> close() async {
    _generation++;
    await _subscription?.cancel();
    await _query?.dispose();
    return super.close();
  }
}
