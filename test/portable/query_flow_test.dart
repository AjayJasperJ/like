import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  test(
    'invalidation and reconnect refresh matching active queries only',
    () async {
      final hub = LikeInvalidationHub();
      final restored = StreamController<String>.broadcast();
      var calls = 0;
      final query = LikeQuery<int>(
        action: (_) async => LikeApiResult.success(++calls),
        scope: () => 'account',
        origin: 'https://api.example',
        tags: ['posts'],
        invalidations: hub,
        restoredOrigins: restored.stream,
      );
      await query.refresh();
      expect(query.state.data, 1);
      hub.emit(
        LikeInvalidationEvent(
          ['posts'],
          scope: 'other',
          origin: 'https://api.example',
        ),
      );
      final updated = query.watch().firstWhere((state) => state.data == 2);
      hub.emit(
        LikeInvalidationEvent(
          ['posts'],
          scope: 'account',
          origin: 'https://api.example',
        ),
      );
      await updated.timeout(const Duration(seconds: 2));
      expect(calls, 2);
      final reconnected = query.watch().firstWhere((state) => state.data == 3);
      restored.add('https://api.example:443');
      await reconnected.timeout(const Duration(seconds: 2));
      await query.dispose();
      await restored.close();
      await hub.dispose();
    },
  );

  test('query replacement cancels transport and ignores stale data', () async {
    final pending = <Completer<LikeApiResult<int>>>[];
    final tokens = <CancelToken>[];
    final query = LikeQuery<int>(
      action: (token) {
        tokens.add(token);
        final result = Completer<LikeApiResult<int>>();
        pending.add(result);
        return result.future;
      },
      scope: () => 'a',
      origin: 'https://api.example',
      restoredOrigins: const Stream.empty(),
    );
    final old = query.refresh();
    final current = query.refresh();
    expect(tokens.first.isCancelled, isTrue);
    pending[1].complete(LikeApiResult.success(2));
    await current;
    pending[0].complete(LikeApiResult.success(1));
    await old;
    expect(query.state.data, 2);
    final late = query.refresh();
    await query.dispose();
    expect(tokens.last.isCancelled, isTrue);
    pending.last.complete(LikeApiResult.success(3));
    await late;
  });

  test('optimistic rollback preserves a newer committed change', () {
    final store = LikeOptimisticStore<List<int>>([]);
    final first = store.begin((base) => [...base, 1]);
    final second = store.begin((base) => [...base, 2]);
    store.commit(second, (base) => [...base, 20]);
    expect(store.value, [1, 20]);
    store.rollback(first);
    expect(store.value, [20]);
    store.dispose();
  });

  test(
    'cursor pagination deduplicates IDs and stops at a null terminal cursor',
    () async {
      var calls = 0;
      final query = LikePagedQuery<int>(
        identity: (item) => item,
        pageSize: 2,
        action: (page, cursor, token) async {
          calls++;
          return LikeApiResult.success(
            PaginationTool<int>(
              cursorBased: true,
              listData: page == 1 ? [1, 2] : [2, 3],
              cursor: cursor,
              nextCursor: page == 1 ? 'next' : null,
            ),
          );
        },
      );
      await query.loadNext();
      await query.loadNext();
      await query.loadNext();
      expect(query.value.items, [1, 2, 3]);
      expect(query.value.hasMore, isFalse);
      expect(calls, 2);
      query.dispose();
    },
  );

  test(
    'failed page retry retains previous pages and refresh cancels old work',
    () async {
      var fail = true;
      final query = LikePagedQuery<int>(
        identity: (item) => item,
        pageSize: 2,
        action: (page, cursor, token) async {
          if (page == 2 && fail) {
            return LikeApiResult.error(
              LikeError(message: 'retry', type: LikeApiErrorType.network),
            );
          }
          return LikeApiResult.success(
            PaginationTool<int>(
              listData: page == 1 ? [1, 2] : [2, 3],
              totalContent: 4,
            ),
          );
        },
      );
      await query.loadNext();
      await query.loadNext();
      expect(query.value.items, [1, 2]);
      expect(query.value.failedPage, 2);
      fail = false;
      await query.retryFailedPage();
      expect(query.value.items, [1, 2, 3]);
      expect(query.value.failedPage, isNull);
      query.dispose();
    },
  );

  test('void success and 304 provenance survive result transformations', () {
    final result = LikeApiResult<void>.success(null, isFrom304: true);
    expect(result.toStateResponse().state, LikeState.success);
    final mapped = LikeApiResult<int>.success(
      1,
      isFrom304: true,
    ).mapSuccess((value) => value + 1);
    expect(mapped.isFrom304, isTrue);
  });
}
