import 'package:dio/dio.dart';

/// A typed event emitted by the [LikePipeline].
/// Carries both the raw [Response] and potentially a ready-to-use mapped model.
class LikeEvent<T> {
  final String key;
  final Response response;
  final T? model;
  final bool isSyncing;
  final DateTime? timestamp;

  LikeEvent({
    required this.key,
    required this.response,
    this.model,
    this.isSyncing = false,
    this.timestamp,
  });

  dynamic get data => model ?? response.data;
  bool get hasModel => model != null;
}
