import 'dart:async';

class LikeInvalidationEvent {
  final Set<String> tags;
  final String scope;
  final String origin;
  LikeInvalidationEvent(Iterable<String> tags, {required this.scope, required this.origin})
      : tags = Set.unmodifiable(tags);
}

/// Application data events only: no payloads, credentials or diagnostic logging.
class LikeInvalidationHub {
  static final shared = LikeInvalidationHub();
  final _events = StreamController<LikeInvalidationEvent>.broadcast();
  Stream<LikeInvalidationEvent> get stream => _events.stream;
  void emit(LikeInvalidationEvent event) { if (!_events.isClosed) _events.add(event); }
  Future<void> dispose() => _events.close();
}

class LikeResourceIndex {
  final Map<String, ({String origin, Set<String> tags})> _resources = {};
  void bind(String key, String origin, Iterable<String> tags) {
    if (_resources.length >= 500) _resources.remove(_resources.keys.first);
    _resources[key] = (origin: origin, tags: tags.toSet());
  }
  Set<String> matching(LikeInvalidationEvent event) => _resources.entries
      .where((entry) => entry.value.origin == event.origin && entry.value.tags.any(event.tags.contains))
      .map((entry) => entry.key).toSet();
  void clear() => _resources.clear();
}
