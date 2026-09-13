/// The lifecycle phase of an owner-scoped UI resynchronization run.
enum LikeResyncPhase {
  /// No resynchronization is active.
  idle,

  /// A run is waiting for its bounded retry delay.
  waiting,

  /// The retained refresh action is running.
  running,

  /// The retained refresh action completed successfully.
  succeeded,

  /// The run was cancelled because its owner became inactive or requested it.
  cancelled,

  /// The bounded run ended with an error or an unsuccessful network state.
  failed,
}

/// The event that initiated an owner-scoped UI resynchronization run.
enum LikeResyncTrigger {
  /// Explicitly requested by the provider or screen owner.
  manual,

  /// Triggered by an exact canonical-origin connectivity restoration.
  restoration,

  /// Triggered by a relevant successful mutation notification.
  mutation,

  /// Triggered by the legacy manual `reconnected` broadcast.
  legacyReconnection,

  /// Triggered while initializing legacy provider synchronization.
  initial,
}

/// Immutable observable state for owner-scoped UI resynchronization.
class LikeResyncState {
  /// Current lifecycle phase.
  final LikeResyncPhase phase;

  /// Trigger that started the current or most recently completed run.
  final LikeResyncTrigger? trigger;

  /// One-based attempt number, or zero before the first attempt.
  final int attempt;

  /// Maximum attempts permitted for this run.
  final int maxAttempts;

  /// Delay applied before the current or next attempt.
  final Duration? delay;

  /// Time at which the next attempt is eligible to begin.
  final DateTime? nextRetryAt;

  /// Canonical `scheme://host:port` origin associated with this work.
  final String? origin;

  /// Terminal error retained when [phase] is [LikeResyncPhase.failed].
  final Object? terminalError;

  /// Time at which this run was created.
  final DateTime? startedAt;

  /// Time at which this state snapshot was produced.
  final DateTime updatedAt;

  /// Time at which this run reached a terminal phase.
  final DateTime? completedAt;

  const LikeResyncState({
    required this.phase,
    required this.attempt,
    required this.maxAttempts,
    required this.updatedAt,
    this.trigger,
    this.delay,
    this.nextRetryAt,
    this.origin,
    this.terminalError,
    this.startedAt,
    this.completedAt,
  });

  /// Creates the initial idle state.
  factory LikeResyncState.idle({DateTime? timestamp}) {
    final now = timestamp ?? DateTime.now();
    return LikeResyncState(
      phase: LikeResyncPhase.idle,
      attempt: 0,
      maxAttempts: 0,
      updatedAt: now,
    );
  }

  /// Whether a delay or refresh action is currently active.
  bool get isActive =>
      phase == LikeResyncPhase.waiting || phase == LikeResyncPhase.running;

  /// Whether this snapshot represents a terminal run state.
  bool get isTerminal =>
      phase == LikeResyncPhase.succeeded ||
      phase == LikeResyncPhase.cancelled ||
      phase == LikeResyncPhase.failed;
}
