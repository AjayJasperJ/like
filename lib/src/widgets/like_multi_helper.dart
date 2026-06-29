import 'package:like/src/models/like_state_response.dart';

/// # LikeMultiHelper
///
/// A lightweight, internal utility class designed to aggregate a list of individual
/// `LikeStateResponse` lifecycle states into a single consolidated `LikeState`.
///
/// This helper implements the core **Priority State Machine** logic used by widgets
/// like `LikeMultiBuilder` and `LikeMultiSliverBuilder`.
class LikeMultiHelper {
  /// Aggregates a list of [LikeStateResponse]s into a single priority-based [LikeState].
  ///
  /// ### State Priority Hierarchy (Highest to Lowest):
  /// 1. **Exception:** If any single request crashed on the client-side, the entire screen
  ///    must halt and display the exception UI.
  /// 2. **Error:** If any request fails with a server error, the entire screen halts and
  ///    displays the error UI.
  /// 3. **Loading:** If any request is fetching for the very first time, the loader must run
  ///    (unless sticky success data resides in memory).
  /// 4. **Idle:** If any request has not started loading yet, we hold the screen in an idle state.
  /// 5. **Refreshing:** If any request is currently refreshing, the app is marked as refreshing
  ///    (old data remains visible).
  /// 6. **StaleWhileRevalidate:** If any request is displaying cached data while revalidating
  ///    in the background.
  /// 7. **Success:** Only returned when **every single** request has completed successfully
  ///    and resolved to a stable success state.
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
