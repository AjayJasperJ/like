import 'package:flutter_bloc/flutter_bloc.dart';
import '../models/api_models.dart';
import '../repositories/post_repository.dart';

/// BLoC/Cubit integration uses the same repository as Provider and Riverpod.
final class PostsCubit extends Cubit<LikeStateResponse<PaginatedPosts>> {
  PostsCubit(this._repository) : super(LikeStateResponse.idle());

  final PostsRepository _repository;
  int _generation = 0;

  Future<void> load({int page = 1}) async {
    if (isClosed) return;
    final generation = ++_generation;
    emit(LikeStateResponse.loading());
    try {
      final result = await _repository.list(page: page);
      if (!isClosed && generation == _generation) {
        emit(result.toStateResponse());
      }
    } catch (error) {
      if (!isClosed && generation == _generation) {
        emit(LikeStateResponse.error(LikeError(
          message: error.toString(),
          type: LikeApiErrorType.unknown,
        )));
      }
    }
  }
}
