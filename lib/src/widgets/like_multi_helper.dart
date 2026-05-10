import 'package:like/src/models/like_state_response.dart';

/// Internal helper for aggregating multiple [LikeStateResponse] states.
/// Provides logic to determine the combined state of multiple network operations.
class LikeMultiHelper {
  /// Aggregates a list of [LikeStateResponse]s into a single priority-based [LikeState].
  ///
  /// Priority order (highest to lowest):
  /// 1. Exception
  /// 2. Error
  /// 3. Loading
  /// 4. Idle
  /// 5. Refreshing
  /// 6. StaleWhileRevalidate
  /// 7. Success (only if all are success)
  static LikeState aggregate(List<LikeStateResponse<dynamic>> responses) {
    if (responses.any((r) => r.state == LikeState.exception)) {
      return LikeState.exception;
    }
    if (responses.any((r) => r.state == LikeState.error)) {
      return LikeState.error;
    }
    if (responses.any((r) => r.state == LikeState.loading)) {
      return LikeState.loading;
    }
    if (responses.any((r) => r.state == LikeState.idle)) {
      return LikeState.idle;
    }
    if (responses.any((r) => r.state == LikeState.refreshing)) {
      return LikeState.refreshing;
    }
    if (responses.any((r) => r.state == LikeState.staleWhileRevalidate)) {
      return LikeState.staleWhileRevalidate;
    }
    return LikeState.success;
  }
}
