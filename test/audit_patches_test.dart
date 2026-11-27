import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/like.dart';
import 'package:like/src/models/like_resync_state.dart';
import 'package:like/src/client/internal/like_mapper.dart';
import 'package:like/src/interceptors/like_cache_interceptor.dart';
import 'package:like/src/interceptors/like_etag_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_pipeline.dart';
import 'package:like/src/services/like_sync_manager.dart';

import 'mocks/mocks.dart';

class _FnAdapter implements HttpClientAdapter {
  _FnAdapter(this.handler);
  final Future<ResponseBody> Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<dynamic>? cancelFuture,
  ) {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    setupMocks();
  });

  tearDown(() async {
    await LikeService.reset(closeBoxes: true);
    LikeAuthInterceptor.resetGlobalState();
    LikeClient.reset();
    await LikeSyncManager().reset();
    await LikeConnectivityManager().reset();
    LikeDiagnostics.shared.clear();
    LikeDiagnostics.shared.enabled = true;
    LikeConstants.reset();
  });

  test('LikeService.init(cacheEnabled: false) skips Hive and sets disabled status', () async {
    await LikeService.init(
      config: LikeConfig(
        projectName: 'audit_disabled_cache',
        cacheEnabled: false,
        disableFileLogging: true,
        silentConsole: true,
      ),
    );
    expect(LikeService.storageAvailable, isFalse);
    expect(LikeService.storageStatus, LikeStorageStatus.disabled);
    expect(Hive.isBoxOpen(LikeConstants.boxApiCache), isFalse);

    // Client creation works without offline queue box when storage is disabled
    final client = LikeClient.scoped(const LikeClientConfig(baseUrl: 'https://api.example'));
    addTearDown(client.dispose);
    expect(client.offlineQueue, isNull);
  });

  test('LikeEtagInterceptor skips If-None-Match when cache is disabled and retries 304 on miss', () async {
    LikeConstants.apply(
      LikeConfig(
        projectName: 'audit_etag_miss',
        cacheEnabled: true,
        offlineSyncEnabled: false,
        disableFileLogging: true,
        silentConsole: true,
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://etag.example'));
    var call = 0;
    final adapter = _FnAdapter((options) async {
      call++;
      if (call == 1) {
        return ResponseBody.fromString('', 304);
      }
      return ResponseBody.fromString(
        jsonEncode({'fresh': true}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    });
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(LikeEtagInterceptor(dio: dio));

    final response = await dio.get<dynamic>('/item');
    expect(response.statusCode, 200);
    expect(response.data, contains('fresh'));
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.headers.containsKey('If-None-Match'), isFalse);
    dio.close();
  });

  test('LikeCacheInterceptor.pruneCache is safe when cache box is not open', () async {
    LikeConstants.apply(LikeConfig(projectName: 'audit_unopened_prune'));
    final interceptor = LikeCacheInterceptor();
    await interceptor.pruneCache();
  });

  test('LikeAuthInterceptor does not replay unsafe POST on 401 without Idempotency-Key', () async {
    LikeConstants.apply(LikeConfig(projectName: 'audit_replay_guard', disableFileLogging: true));
    final dio = Dio(BaseOptions(baseUrl: 'https://auth.example'));
    final adapter = _FnAdapter((options) async {
      if (options.headers['Authorization'] == 'Bearer fresh') {
        return ResponseBody.fromString('{"ok":true}', 200);
      }
      return ResponseBody.fromString('{"error":"unauth"}', 401);
    });
    dio.httpClientAdapter = adapter;
    var refreshes = 0;
    dio.interceptors.add(
      LikeAuthInterceptor(
        dio: dio,
        authConfig: LikeAuthConfig(
          getToken: () => 'old',
          refreshToken: () async {
            refreshes++;
            return 'fresh';
          },
        ),
      ),
    );

    // Unsafe POST without Idempotency-Key must NOT replay
    await expectLater(
      dio.post<dynamic>('/orders', options: Options(extra: {'withAuth': true})),
      throwsA(isA<DioException>()),
    );
    expect(refreshes, 0);
    expect(adapter.requests, hasLength(1));

    // POST with Idempotency-Key DOES replay and preserves the header
    final ok = await dio.post<dynamic>(
      '/orders',
      options: Options(extra: {'withAuth': true, 'idempotencyKey': 'idem-123'}),
    );
    expect(ok.statusCode, 200);
    expect(refreshes, 1);
    expect(adapter.requests.last.headers['Idempotency-Key'], 'idem-123');
    dio.close();
  });

  test('LikeEngine exactQueryMatch isolates paginated/mode pipeline updates', () async {
    LikeConstants.apply(LikeConfig(projectName: 'audit_exact_query', disableFileLogging: true));
    final engine = LikeEngine();
    final stateA = LikeNotifierState<String>(mapper: (d) => d.toString())
      ..endpointPath = '/feed'
      ..activeQuery = {'mode': 'following', 'page': 1};
    final stateB = LikeNotifierState<String>(mapper: (d) => d.toString())
      ..endpointPath = '/feed'
      ..activeQuery = {'mode': 'discover', 'page': 1};
    addTearDown(() {
      stateA.dispose();
      stateB.dispose();
      engine.dispose();
    });

    await engine.fetch<String>(
      state: stateA,
      exactQueryMatch: true,
      action: () async => LikeStateResponse.success('following-1'),
    );
    await engine.fetch<String>(
      state: stateB,
      exactQueryMatch: true,
      action: () async => LikeStateResponse.success('discover-1'),
    );

    // Emit pipeline update for mode=following&page=2; neither page=1 state should mutate
    LikePipeline().emit(
      'https://api.example/feed',
      Response(
        requestOptions: RequestOptions(
          path: '/feed',
          queryParameters: {'mode': 'following', 'page': 2},
        ),
        data: 'following-2',
        statusCode: 200,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(stateA.value.data, 'following-1');
    expect(stateB.value.data, 'discover-1');
  });

  test('LikeService invalidation generation blocks stale in-flight cache writes', () async {
    await initTestHive();
    LikeConstants.apply(LikeConfig(projectName: 'audit_cache_gen', disableFileLogging: true));
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
    await Hive.openBox(LikeConstants.boxEtags);

    final options = RequestOptions(
      path: '/posts',
      baseUrl: 'https://cache.example',
      extra: {
        LikeSessionIdentity.scopeKey: '',
        'like.cacheGeneration': LikeService.generationForKey(
          LikeSessionIdentity.forRequest(
            RequestOptions(path: '/posts', baseUrl: 'https://cache.example'),
          ),
        ),
      },
    );
    final key = LikeSessionIdentity.forRequest(options);
    LikeService.markKeysInvalidated([key]);

    await LikeService.saveResponseToCache(
      Response(requestOptions: options, data: {'stale': true}, statusCode: 200),
    );
    expect(await LikeService.fetchResponseFromCache(options), isNull);
  });

  test('LikeMapper respects thresholdKB before offloading to compute', () async {
    final small = {'id': 1, 'name': 'ok'};
    final mapped = await LikeMapper.map<int>(small, (d) => (d as Map)['id'] as int, thresholdKB: 50);
    expect(mapped, 1);
  });

  test('LikeDiagnostics clears on session scope change', () {
    LikeConstants.apply(LikeConfig(projectName: 'audit_diag', disableFileLogging: true));
    final client = LikeClient.scoped(const LikeClientConfig(baseUrl: 'https://diag.example'));
    addTearDown(client.dispose);

    LikeDiagnostics.shared.emit(
      LikeRequestTrace(
        requestId: 'r1',
        method: 'GET',
        origin: 'https://diag.example',
        scope: '',
        phase: LikeTracePhase.completed,
        source: LikeResponseSource.network,
      ),
    );
    expect(LikeDiagnostics.shared.history, hasLength(1));

    client.setSessionScope(const LikeSessionScope(accountId: 'user-2'));
    expect(LikeDiagnostics.shared.history, isEmpty);
  });

  test('LikePagedQuery stops on repeated cursor and suppresses stale in-flight page on refresh', () async {
    // 1. Repeated cursor stops pagination
    final repeated = LikePagedQuery<int>(
      identity: (item) => item,
      pageSize: 2,
      action: (page, cursor, token) async => LikeApiResult.success(
        PaginationTool<int>(
          cursorBased: true,
          listData: const [1, 2],
          cursor: cursor,
          nextCursor: 'same-cursor',
        ),
      ),
    );
    await repeated.loadNext();
    expect(repeated.value.hasMore, isTrue);
    await repeated.loadNext();
    expect(repeated.value.hasMore, isFalse);
    repeated.dispose();

    // 2. Refresh cancels in-flight loadNext and ignores stale response
    final firstLoad = Completer<LikeApiResult<PaginationTool<int>>>();
    CancelToken? firstToken;
    final query = LikePagedQuery<int>(
      identity: (item) => item,
      pageSize: 2,
      action: (page, cursor, token) {
        if (firstToken == null) {
          firstToken = token;
          return firstLoad.future;
        }
        return Future.value(
          LikeApiResult.success(
            const PaginationTool<int>(listData: [99, 100], totalContent: 2),
          ),
        );
      },
    );
    final pending = query.loadNext();
    await query.refresh();
    expect(firstToken!.isCancelled, isTrue);
    firstLoad.complete(
      LikeApiResult.success(
        const PaginationTool<int>(listData: [1, 2], totalContent: 4),
      ),
    );
    await pending;
    expect(query.value.items, [99, 100]);
    query.dispose();
  });

  test('cacheAuthenticatedGets: false disables caching on scoped withAuth GETs by default', () async {
    await initTestHive();
    LikeConstants.apply(
      LikeConfig(
        projectName: 'audit_auth_cache_optin',
        cacheEnabled: true,
        cacheAuthenticatedGets: false,
        offlineSyncEnabled: false,
        disableFileLogging: true,
        silentConsole: true,
      ),
    );
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
    await Hive.openBox(LikeConstants.boxEtags);
    final client = LikeClient.scoped(
      const LikeClientConfig(
        baseUrl: 'https://authcache.example',
        sessionScope: LikeSessionScope(accountId: 'user-1'),
      ),
    );
    addTearDown(client.dispose);
    client.dio.httpClientAdapter = _FnAdapter(
      (options) async => ResponseBody.fromString(
        '{"secret":1}',
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      ),
    );
    final res = await client.get('/me', withAuth: true);
    expect(res.isSuccess, isTrue);
    expect(
      await LikeService.fetchResponseFromCache(
        RequestOptions(
          path: '/me',
          baseUrl: 'https://authcache.example',
          extra: {LikeSessionIdentity.scopeKey: 'user:user-1'},
        ),
      ),
      isNull,
    );
  });

  test('enableRedaction defaults to true and can be disabled for raw API logs', () async {
    expect(LikeConfig(projectName: 'p').enableRedaction, isTrue);

    LikeConstants.apply(
      LikeConfig(
        projectName: 'audit_redaction_off',
        enableRedaction: false,
        disableFileLogging: true,
        silentConsole: true,
      ),
    );

    final logs = <String>[];
    final sub = LikeLogger.logStream.listen(logs.add);
    addTearDown(sub.cancel);

    await LikeLogger.logApi(
      '/items?page=1',
      success: true,
      statusCode: 200,
      method: 'GET',
      requestBody: 'raw-request-body',
      response: 'raw-response-string',
    );
    await Future<void>.delayed(Duration.zero);

    expect(logs, hasLength(1));
    final decoded = jsonDecode(logs.first) as Map<String, dynamic>;
    final details = decoded['details'] as Map<String, dynamic>;
    expect(decoded['message'], contains('/items?page=1'));
    expect(details['requestBody'], 'raw-request-body');
    expect(details['response'], 'raw-response-string');
  });

  test('LikeClient GET persists API responses in LikeService.cacheBox when cache is enabled', () async {
    await initTestHive();
    LikeConstants.apply(
      LikeConfig(
        projectName: 'audit_cache_persist',
        baseUrl: 'https://cachepersist.example',
        cacheEnabled: true,
        offlineSyncEnabled: false,
        disableFileLogging: true,
        silentConsole: true,
      ),
    );
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
    await Hive.openBox(LikeConstants.boxEtags);

    final client = LikeClient.scoped(
      const LikeClientConfig(baseUrl: 'https://cachepersist.example'),
    );
    addTearDown(client.dispose);

    client.dio.httpClientAdapter = _FnAdapter(
      (options) async => ResponseBody.fromString(
        jsonEncode({'id': 42, 'name': 'Cached Item'}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
          'etag': ['"v42"'],
        },
      ),
    );

    // 1. Public GET is written to cacheBox and etagBox
    final res = await client.get('/items/42');
    expect(res.isSuccess, isTrue);
    expect(LikeService.cacheBox.length, 1);
    expect(LikeService.etagBox.length, 1);

    // 2. Protected anonymous GET (withAuth: true, no sessionScope) is NOT cached
    final anonRes = await client.get('/private', withAuth: true);
    expect(anonRes.isSuccess, isTrue);
    expect(LikeService.cacheBox.length, 1);

    // 3. Protected scoped GET IS cached under the account scope
    client.setSessionScope(const LikeSessionScope(accountId: 'user-42'));
    final scopedRes = await client.get('/private', withAuth: true);
    expect(scopedRes.isSuccess, isTrue);
    expect(LikeService.cacheBox.length, 2);
  });

  test('LikeNotifierState.dispose prevents stale pipeline updates and cancels active tokens', () async {
    LikeConstants.apply(
      LikeConfig(projectName: 'audit_state_dispose', disableFileLogging: true),
    );
    final engine = LikeEngine();
    addTearDown(engine.dispose);

    var mapperCalls = 0;
    final state = LikeNotifierState<String>(
      mapper: (d) {
        mapperCalls++;
        return d.toString();
      },
    )
      ..endpointPath = '/items'
      ..activeQuery = const {};

    await engine.fetch<String>(
      state: state,
      action: () async => LikeStateResponse.success('initial'),
    );
    final ct = CancelToken();
    state.ct = ct;
    state.dispose();

    expect(state.isDisposed, isTrue);
    expect(state.refreshAction, isNull);
    expect(ct.isCancelled, isTrue);

    LikePipeline().emit(
      'https://api.example:8443/items',
      Response(
        requestOptions: RequestOptions(path: '/items'),
        data: 'should-not-map',
        statusCode: 200,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(mapperCalls, 0);
  });

  test('LikeChangeNotifier handles fetch, fetcher, and CancelToken rotation without autoResync', () async {
    LikeConstants.apply(
      LikeConfig(projectName: 'audit_change_notifier', disableFileLogging: true),
    );
    final provider = _TestLikeChangeNotifier();
    addTearDown(provider.dispose);

    var notifications = 0;
    provider.addListener(() => notifications++);

    // 1. Superseding fetch cancels previous CancelToken
    final firstCompleter = Completer<LikeStateResponse<String>>();
    CancelToken? firstCt;
    final firstFuture = provider.fetch<String>(
      state: provider.itemState,
      action: (ct, _) {
        firstCt = ct;
        return firstCompleter.future;
      },
    );
    final secondResult = await provider.fetch<String>(
      state: provider.itemState,
      action: (_, _) async => LikeStateResponse.success('latest'),
    );
    expect(firstCt!.isCancelled, isTrue);
    expect(secondResult.data, 'latest');

    // Stale completion does not overwrite newer state
    firstCompleter.complete(LikeStateResponse.success('stale'));
    await firstFuture;
    expect(provider.itemState.data, 'latest');
    expect(notifications, greaterThanOrEqualTo(2));

    // 2. Direct fetcher usage
    LikeStateResponse<int>? customState;
    CancelToken? customCt;
    await provider.fetcher<int>(
      ct: customCt,
      onRotate: (next) => customCt = next,
      onUpdate: (s) => customState = s,
      action: (_, _) async => LikeStateResponse.success(42),
    );
    expect(customState?.data, 42);

    // 3. Cancelled LikeApiResult (e.g. from LikeClient) is silently hidden and reverts to previous data
    provider.itemState.value = LikeStateResponse.success('previous-ok');
    final cancelledRes = await provider.fetchResult<String>(
      state: provider.itemState,
      action: (_, _) async => LikeApiResult.error(
        LikeError(message: 'Request cancelled', type: LikeApiErrorType.cancelled),
      ),
    );
    expect(cancelledRes.isSuccess, isTrue);
    expect(provider.itemState.data, 'previous-ok');
    expect(provider.itemState.isError, isFalse);

    // 4. ars.skip skips when state already has success + data, otherwise runs action
    var skipActionCalls = 0;
    final skippedRes = await provider.fetch<String>(
      state: provider.itemState,
      ars: const LikeARS(skip: true),
      action: (_, _) async {
        skipActionCalls++;
        return LikeStateResponse.success('should-not-run');
      },
    );
    expect(skipActionCalls, 0);
    expect(skippedRes.data, 'previous-ok');

    provider.itemState.clear();
    final fetchedWhenIdle = await provider.fetch<String>(
      state: provider.itemState,
      ars: const LikeARS(skip: true),
      action: (_, _) async {
        skipActionCalls++;
        return LikeStateResponse.success('fetched-when-idle');
      },
    );
    expect(skipActionCalls, 1);
    expect(fetchedWhenIdle.data, 'fetched-when-idle');
  });

  test('LikeStateMixin supports ars.skip and silent LikeApiErrorType.cancelled', () async {
    LikeConstants.apply(
      LikeConfig(projectName: 'audit_state_mixin_skip', disableFileLogging: true),
    );
    final provider = _TestLikeStateMixinProvider();
    addTearDown(provider.dispose);

    await provider.fetch<String>(
      state: provider.itemState,
      action: (_, _) async => LikeStateResponse.success('cached-ok'),
    );

    var calls = 0;
    final skipped = await provider.fetch<String>(
      state: provider.itemState,
      ars: const LikeARS(skip: true),
      action: (_, _) async {
        calls++;
        return LikeStateResponse.success('new');
      },
    );
    expect(calls, 0);
    expect(skipped.data, 'cached-ok');

    final cancelled = await provider.fetch<String>(
      state: provider.itemState,
      action: (_, _) async => LikeStateResponse.error(
        LikeError(message: 'Request cancelled', type: LikeApiErrorType.cancelled),
      ),
    );
    expect(cancelled.isSuccess, isTrue);
    expect(provider.itemState.data, 'cached-ok');
  });

  test('LikeChangeNotifier supports keyed state map, getByKey, getPaginatedByKey, and toInitState', () async {
    LikeConstants.apply(
      LikeConfig(projectName: 'audit_keyed_states', disableFileLogging: true),
    );
    final provider = _TestLikeChangeNotifier();
    addTearDown(provider.dispose);

    final postState = provider.getByKey<String>('post:1');
    expect(identical(provider.getByKey<String>('post:1'), postState), isTrue);
    expect(provider.keyedStates.containsKey('post:1'), isTrue);

    await provider.fetch<String>(
      state: postState,
      action: (_, _) async => LikeStateResponse.success('post-1-body'),
    );
    expect(postState.data, 'post-1-body');

    final feedState = provider.getPaginatedByKey<int>('feed', pageSize: 2);
    await feedState.loadCursor(
      action: (cursor, limit) async => LikeApiResult.success(
        const PaginationTool<int>(
          cursorBased: true,
          nextCursor: 'c2',
          listData: [1, 2],
        ),
      ),
    );
    expect(feedState.items, [1, 2]);
    expect(provider.paginatedStates.containsKey('feed'), isTrue);
    expect(provider.keyedStates.containsKey('feed'), isFalse);

    // .toInitState resets a keyed state back to idle
    postState.toInitState();
    expect(postState.isIdle, isTrue);

    // provider.toInitState('user:1') resets keyed state back to idle
    provider.toInitState('feed');
    expect(feedState.isIdle, isTrue);
    expect(feedState.items, isEmpty);
  });

  testWidgets('LikeBuilder skips redundant rebuilds when value is unchanged or selector matches', (tester) async {
    final state = LikeNotifierState<Map<String, Object>>(
      initialValue: LikeStateResponse.success({'title': 'A', 'count': 1}),
    );
    addTearDown(state.dispose);

    var builds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LikeBuilder<Map<String, Object>>(
          observe: () => state,
          selector: (data) => data['title'],
          onSuccess: (data, _, _) {
            builds++;
            return Text(data['title'] as String);
          },
        ),
      ),
    );
    expect(builds, 1);

    // resyncState change does not alter value -> no rebuild
    state.resyncState = LikeResyncState(
      phase: LikeResyncPhase.running,
      trigger: LikeResyncTrigger.manual,
      attempt: 1,
      maxAttempts: 3,
      startedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await tester.pump();
    expect(builds, 1);

    // Changing only 'count' (not 'title') -> selector skips rebuild
    state.value = LikeStateResponse.success({'title': 'A', 'count': 2});
    await tester.pump();
    expect(builds, 1);

    // Changing 'title' -> rebuilds
    state.value = LikeStateResponse.success({'title': 'B', 'count': 2});
    await tester.pump();
    expect(builds, 2);
    expect(find.text('B'), findsOneWidget);
  });

  test('LikeChangeNotifier supports LikeStateResponse directly via fetchResponse and fetchResponseResult', () async {
    final provider = _TestLikeChangeNotifier();
    var profile = LikeStateResponse<String>.idle();
    var notifyCount = 0;
    provider.addListener(() => notifyCount++);

    final observedStates = <LikeState>[];
    final firstResult = await provider.fetchResponse<String>(
      key: 'profile',
      state: profile,
      onUpdate: (next) {
        profile = next;
        observedStates.add(next.state);
      },
      action: (ct, ars) async => LikeStateResponse<String>.success('v1'),
    );

    expect(firstResult.isSuccess, isTrue);
    expect(firstResult.data, 'v1');
    expect(profile.data, 'v1');
    expect(observedStates, [LikeState.loading, LikeState.success]);
    expect(notifyCount, 2);

    // ars.skip should short-circuit and return previous success without calling action
    var skippedActionCalled = false;
    final skippedResult = await provider.fetchResponse<String>(
      key: 'profile',
      state: profile,
      ars: const LikeARS(skip: true),
      onUpdate: (next) => profile = next,
      action: (ct, ars) async {
        skippedActionCalled = true;
        return LikeStateResponse<String>.success('should-not-run');
      },
    );
    expect(skippedActionCalled, isFalse);
    expect(skippedResult.data, 'v1');

    // ars.refresh should emit refreshing('v1') using previousState.data
    final refreshStates = <LikeState>[];
    final secondResult = await provider.fetchResponseResult<String>(
      key: 'profile',
      state: profile,
      ars: const LikeARS(refresh: true),
      onUpdate: (next) {
        profile = next;
        refreshStates.add(next.state);
      },
      action: (ct, ars) async => LikeApiResult<String>.success('v2'),
    );
    expect(secondResult.data, 'v2');
    expect(profile.data, 'v2');
    expect(refreshStates, [LikeState.refreshing, LikeState.success]);

    // Overlapping call cancels previous token and dispose cancels active token
    late CancelToken firstToken;
    final firstCompleter = Completer<LikeStateResponse<String>>();
    final slowFuture = provider.fetchResponse<String>(
      key: 'profile',
      state: profile,
      onUpdate: (next) => profile = next,
      action: (ct, ars) {
        firstToken = ct;
        return firstCompleter.future;
      },
    );

    late CancelToken secondToken;
    final secondCompleter = Completer<LikeStateResponse<String>>();
    final secondFuture = provider.fetchResponse<String>(
      key: 'profile',
      state: profile,
      onUpdate: (next) => profile = next,
      action: (ct, ars) {
        secondToken = ct;
        return secondCompleter.future;
      },
    );

    expect(firstToken.isCancelled, isTrue);
    firstCompleter.complete(LikeStateResponse<String>.success('stale'));
    await slowFuture;
    expect(profile.data, isNot('stale'));

    provider.dispose();
    expect(secondToken.isCancelled, isTrue);
    secondCompleter.complete(LikeStateResponse<String>.success('after-dispose'));
    await secondFuture;
  });

  test('LikeChangeNotifier supports keyedResponses map, getResponseByKey, setResponseByKey, fetchResponseByKey, and toInitState', () async {
    final provider = _TestLikeChangeNotifier();

    expect(provider.keyedResponses, isEmpty);
    final initial = provider.getResponseByKey<String>('user');
    expect(initial.isIdle, isTrue);
    expect(provider.keyedResponses.containsKey('user'), isTrue);

    final result = await provider.fetchResponseByKey<String>(
      key: 'user',
      action: (ct, ars) async => LikeStateResponse<String>.success('Alice'),
    );
    expect(result.isSuccess, isTrue);
    expect(provider.getResponseByKey<String>('user').data, 'Alice');

    final result2 = await provider.fetchResponseResultByKey<int>(
      key: 'count',
      action: (ct, ars) async => LikeApiResult<int>.success(42),
    );
    expect(result2.data, 42);
    expect(provider.getResponseByKey<int>('count').data, 42);

    provider.setResponseByKey<String>('manual', LikeStateResponse<String>.success('ok'));
    expect(provider.getResponseByKey<String>('manual').data, 'ok');

    provider.toInitState('user', 'reset user');
    expect(provider.keyedResponses['user']?.isIdle, isTrue);
    expect(provider.getResponseByKey<String>('user').isIdle, isTrue);
    expect(provider.getResponseByKey<String>('user').message, 'reset user');
    expect(provider.getResponseByKey<int>('count').data, 42);

    provider.toInitState(null, 'reset all');
    expect(provider.getResponseByKey<int>('count').isIdle, isTrue);
    expect(provider.getResponseByKey<String>('manual').isIdle, isTrue);

    provider.dispose();
  });

  test('LikePaginatedResponse works standalone and with LikeChangeNotifier keyedPaginatedResponses', () async {
    // 1. Standalone immutable usage (e.g., Riverpod / Bloc / Cubit)
    var standalone = LikePaginatedResponse<String>.idle(pageSize: 2);
    expect(standalone.isIdle, isTrue);
    standalone = standalone.startLoad(page: 1);
    expect(standalone.isLoading, isTrue);
    standalone = standalone.applyPayload(
      page: 1,
      payload: const PaginationTool<String>(
        page: 1,
        contentLimit: 2,
        totalPages: 2,
        totalContent: 4,
        listData: ['a', 'b'],
      ),
    );
    expect(standalone.isSuccess, isTrue);
    expect(standalone.items, ['a', 'b']);
    expect(standalone.hasMore, isTrue);

    standalone = standalone.startLoad(page: 2);
    expect(standalone.isLoadingMore, isTrue);
    standalone = standalone.applyPayload(
      page: 2,
      payload: const PaginationTool<String>(
        page: 2,
        contentLimit: 2,
        totalPages: 2,
        totalContent: 4,
        listData: ['c', 'd'],
      ),
    );
    expect(standalone.items, ['a', 'b', 'c', 'd']);
    expect(standalone.hasMore, isFalse);

    // 2. LikeChangeNotifier keyedPaginatedResponses (page + cursor)
    final provider = _TestLikeChangeNotifier();
    expect(provider.keyedPaginatedResponses, isEmpty);

    await provider.fetchPaginatedResponseByKey<String>(
      key: 'feed',
      page: 1,
      pageSize: 2,
      action: (page, limit, ct) async => PaginationTool<String>(
        page: page,
        contentLimit: limit,
        totalPages: 2,
        totalContent: 3,
        listData: ['p1', 'p2'],
      ),
    );
    expect(provider.getPaginatedResponseByKey<String>('feed').items, ['p1', 'p2']);

    await provider.fetchPaginatedResponseByKey<String>(
      key: 'feed',
      page: 2,
      pageSize: 2,
      action: (page, limit, ct) async => PaginationTool<String>(
        page: page,
        contentLimit: limit,
        totalPages: 2,
        totalContent: 3,
        listData: ['p3'],
      ),
    );
    expect(provider.getPaginatedResponseByKey<String>('feed').items, ['p1', 'p2', 'p3']);
    expect(provider.getPaginatedResponseByKey<String>('feed').hasMore, isFalse);

    // Cursor mode via fetchPaginatedCursorResponseByKey
    await provider.fetchPaginatedCursorResponseByKey<String>(
      key: 'cursor_feed',
      pageSize: 2,
      refresh: true,
      action: (cursor, limit, ct) async => PaginationTool<String>(
        cursorBased: true,
        cursor: cursor,
        nextCursor: 'c2',
        hasNextOverride: true,
        listData: ['x1', 'x2'],
      ),
    );
    expect(provider.getPaginatedResponseByKey<String>('cursor_feed').nextCursor, 'c2');

    await provider.fetchPaginatedCursorResponseByKey<String>(
      key: 'cursor_feed',
      pageSize: 2,
      action: (cursor, limit, ct) async {
        expect(cursor, 'c2');
        return PaginationTool<String>(
          cursorBased: true,
          cursor: cursor,
          nextCursor: null,
          hasNextOverride: false,
          listData: ['x3'],
        );
      },
    );
    expect(provider.getPaginatedResponseByKey<String>('cursor_feed').items, ['x1', 'x2', 'x3']);
    expect(provider.getPaginatedResponseByKey<String>('cursor_feed').hasMore, isFalse);

    provider.toInitState('feed', 'cleared');
    expect(provider.getPaginatedResponseByKey<String>('feed').isIdle, isTrue);
    expect(provider.getPaginatedResponseByKey<String>('cursor_feed').items, ['x1', 'x2', 'x3']);

    provider.dispose();
  });

  test('LikeChangeNotifier fetcher, fetcherResult, and paginatedFetcher support keyed token rotation', () async {
    final provider = _TestLikeChangeNotifier();
    var snapshot = LikeStateResponse<String>.idle();

    final res = await provider.fetcherResult<String>(
      key: 'profile_fetcher',
      previousState: snapshot,
      onUpdate: (next) => snapshot = next,
      action: (ct, ars) async => LikeApiResult<String>.success('loaded'),
    );
    expect(res.data, 'loaded');
    expect(snapshot.data, 'loaded');

    var paged = LikePaginatedResponse<String>.idle(pageSize: 2);
    paged = await provider.paginatedFetcher<String>(
      key: 'paged_fetcher',
      state: paged,
      page: 1,
      onUpdate: (next) => paged = next,
      action: (ct) async => const PaginationTool<String>(
        page: 1,
        contentLimit: 2,
        totalPages: 1,
        totalContent: 2,
        listData: ['a', 'b'],
      ),
    );
    expect(paged.items, ['a', 'b']);
    expect(paged.hasMore, isFalse);

    provider.dispose();
  });
}

class _TestLikeStateMixinProvider extends ChangeNotifier with LikeStateMixin {
  final itemState = LikeNotifierState<String>();

  @override
  void dispose() {
    itemState.dispose();
    super.dispose();
  }
}

class _TestLikeChangeNotifier extends ChangeNotifier with LikeChangeNotifier {
  final itemState = LikeNotifierState<String>();

  @override
  void dispose() {
    itemState.dispose();
    super.dispose();
  }
}
