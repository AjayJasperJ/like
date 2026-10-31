import 'dart:math';
import 'package:http_parser/http_parser.dart';

/// Bounded positive jitter: never retry before the server's requested minimum.
class LikeRetryPolicy {
  final Duration maximumDelay;
  final double Function() random;
  LikeRetryPolicy({this.maximumDelay = const Duration(seconds: 60),
    double Function()? random}) : random = random ?? Random().nextDouble;

  Duration jitter(Duration base) {
    final micros = (base.inMicroseconds * (1 + 0.2 * random().clamp(0.0, 1.0))).round();
    return Duration(microseconds: micros.clamp(0, maximumDelay.inMicroseconds));
  }

  Duration? rateLimit(String? header, int attempt, {DateTime? now}) {
    final seconds = int.tryParse(header ?? '');
    Duration? requested;
    if (seconds != null) {
      requested = Duration(seconds: max(0, seconds));
    } else if (header != null) {
      try { requested = parseHttpDate(header).difference(now ?? DateTime.now()); }
      catch (_) {}
    }
    requested ??= Duration(seconds: 1 << attempt.clamp(0, 6));
    if (requested.isNegative) requested = Duration.zero;
    if (requested > maximumDelay) return null;
    return jitter(requested);
  }
}
