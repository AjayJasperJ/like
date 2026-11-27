import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';

class _Post {
  final int id;
  final String title;

  const _Post({required this.id, required this.title});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Post && other.id == id && other.title == title;

  @override
  int get hashCode => Object.hash(id, title);
}

class _FakeFeedApi {
  final List<int> requestedPages = [];
  Completer<LikeApiResult<PaginationTool<_Post>>>? pendingCompleter;
  bool failNextRequest = false;

  Future<LikeApiResult<PaginationTool<_Post>>> fetchPosts({
    required int page,
    required int limit,
  }) async {
    requestedPages.add(page);
    if (pendingCompleter != null) {
      final completer = pendingCompleter!;
      pendingCompleter = null;
      return completer.future;
    }
    if (failNextRequest) {
      failNextRequest = false;
      return LikeApiResult.error(
        LikeError(
          message: 'Page $page failed',
          type: LikeApiErrorType.server,
          code: 500,
        ),
      );
    }

    if (page == 1) {
      return LikeApiResult.success(
        const PaginationTool<_Post>(
          page: 1,
          contentLimit: 2,
          totalPages: 2,
          totalContent: 4,
          listData: [
            _Post(id: 1, title: 'Post 1'),
            _Post(id: 2, title: 'Post 2'),
          ],
        ),
      );
    }

    return LikeApiResult.success(
      const PaginationTool<_Post>(
        page: 2,
        contentLimit: 2,
        totalPages: 2,
        totalContent: 4,
        listData: [
          _Post(id: 3, title: 'Post 3'),
          _Post(id: 4, title: 'Post 4'),
        ],
      ),
    );
  }
}

class _FeedProvider extends ChangeNotifier with LikeChangeNotifier {
  final _FakeFeedApi _api;

  _FeedProvider(this._api);

  LikePaginatedResponse<_Post> get feed =>
      getPaginatedResponseByKey<_Post>('feed', pageSize: 2);

  LikeStateResponse<String> get banner => getResponseByKey<String>('banner');

  Future<void> loadPage({int page = 1, bool refresh = false}) {
    return fetchPaginatedResponseByKey<_Post>(
      key: 'feed',
      page: page,
      pageSize: 2,
      refresh: refresh,
      action: (p, limit, ct) => _api.fetchPosts(page: p, limit: limit),
    );
  }

  Future<void> loadBanner() {
    return fetchResponseByKey<String>(
      key: 'banner',
      action: (ct, ars) async => LikeStateResponse<String>.success('Welcome'),
    );
  }
}

void main() {
  testWidgets(
    'Provider + Selector + LikePaginatedResponse handles page 1, page 2, error retry, refresh, and selector isolation',
    (tester) async {
      final api = _FakeFeedApi();
      final provider = _FeedProvider(api);
      var selectorBuilds = 0;

      await tester.pumpWidget(
        ChangeNotifierProvider<_FeedProvider>.value(
          value: provider,
          child: MaterialApp(
            home: Scaffold(
              body: Selector<_FeedProvider, LikePaginatedResponse<_Post>>(
                selector: (_, p) => p.feed,
                builder: (context, feedState, _) {
                  selectorBuilds++;
                  return Column(
                    children: [
                      LikeStateResponseBuilder<List<_Post>>(
                        response: feedState.response,
                        onIdle: () => const Text('feed-idle'),
                        onLoading: () => const Text('feed-loading'),
                        onError: (err) => Text('feed-error:${err.message}'),
                        onSuccess: (items, isRefreshing, _) => Column(
                          children: [
                            if (isRefreshing) const Text('feed-refreshing'),
                            for (final post in items) Text(post.title),
                            if (feedState.isLoadingMore)
                              const Text('loading-more'),
                            if (feedState.loadMoreError != null)
                              Text(
                                'load-more-error:${feedState.loadMoreError!.message}',
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Initial idle state
      expect(find.text('feed-idle'), findsOneWidget);
      expect(selectorBuilds, 1);

      // 1. Page 1 in-flight -> loading
      final page1Completer = Completer<LikeApiResult<PaginationTool<_Post>>>();
      api.pendingCompleter = page1Completer;
      final page1Future = provider.loadPage(page: 1);
      await tester.pump();
      expect(find.text('feed-loading'), findsOneWidget);
      expect(selectorBuilds, 2);

      // Complete Page 1 -> success with 2 items, hasMore == true
      page1Completer.complete(
        LikeApiResult.success(
          const PaginationTool<_Post>(
            page: 1,
            contentLimit: 2,
            totalPages: 2,
            totalContent: 4,
            listData: [
              _Post(id: 1, title: 'Post 1'),
              _Post(id: 2, title: 'Post 2'),
            ],
          ),
        ),
      );
      await page1Future;
      await tester.pump();

      expect(find.text('Post 1'), findsOneWidget);
      expect(find.text('Post 2'), findsOneWidget);
      expect(provider.feed.hasMore, isTrue);
      expect(provider.feed.currentPage, 1);
      expect(selectorBuilds, 3);

      // 2. Unrelated key update (banner) must NOT rebuild the feed Selector
      await provider.loadBanner();
      await tester.pump();
      expect(provider.banner.data, 'Welcome');
      expect(selectorBuilds, 3);

      // 3. Page 2 failure keeps Page 1 items visible and sets loadMoreError
      api.failNextRequest = true;
      await provider.loadPage(page: 2);
      await tester.pump();
      expect(find.text('Post 1'), findsOneWidget);
      expect(find.text('Post 2'), findsOneWidget);
      expect(find.text('load-more-error:Page 2 failed'), findsOneWidget);
      expect(provider.feed.hasMore, isTrue);
      final buildsBeforePage2Retry = selectorBuilds;

      // 4. Page 2 in-flight -> shows loading-more while keeping Page 1 items
      final page2Completer = Completer<LikeApiResult<PaginationTool<_Post>>>();
      api.pendingCompleter = page2Completer;
      final page2Future = provider.loadPage(page: 2);
      await tester.pump();
      expect(find.text('Post 1'), findsOneWidget);
      expect(find.text('Post 2'), findsOneWidget);
      expect(find.text('loading-more'), findsOneWidget);
      expect(selectorBuilds, buildsBeforePage2Retry + 1);

      // Complete Page 2 -> 4 items total, hasMore == false
      page2Completer.complete(
        LikeApiResult.success(
          const PaginationTool<_Post>(
            page: 2,
            contentLimit: 2,
            totalPages: 2,
            totalContent: 4,
            listData: [
              _Post(id: 3, title: 'Post 3'),
              _Post(id: 4, title: 'Post 4'),
            ],
          ),
        ),
      );
      await page2Future;
      await tester.pump();

      expect(find.text('Post 1'), findsOneWidget);
      expect(find.text('Post 2'), findsOneWidget);
      expect(find.text('Post 3'), findsOneWidget);
      expect(find.text('Post 4'), findsOneWidget);
      expect(find.text('loading-more'), findsNothing);
      expect(provider.feed.hasMore, isFalse);
      expect(provider.feed.currentPage, 2);

      // 5. Page 3 when hasMore == false should short-circuit (0 API calls, 0 rebuilds)
      final callsBeforePage3 = api.requestedPages.length;
      final buildsBeforePage3 = selectorBuilds;
      await provider.loadPage(page: 3);
      await tester.pump();
      expect(api.requestedPages.length, callsBeforePage3);
      expect(selectorBuilds, buildsBeforePage3);

      // 6. Refresh (page 1, refresh: true) shows refreshing sticky data then resets to 2 items
      final refreshCompleter =
          Completer<LikeApiResult<PaginationTool<_Post>>>();
      api.pendingCompleter = refreshCompleter;
      final refreshFuture = provider.loadPage(page: 1, refresh: true);
      await tester.pump();
      expect(find.text('feed-refreshing'), findsOneWidget);
      expect(find.text('Post 4'), findsOneWidget);

      refreshCompleter.complete(
        LikeApiResult.success(
          const PaginationTool<_Post>(
            page: 1,
            contentLimit: 2,
            totalPages: 2,
            totalContent: 4,
            listData: [
              _Post(id: 1, title: 'Post 1'),
              _Post(id: 2, title: 'Post 2'),
            ],
          ),
        ),
      );
      await refreshFuture;
      await tester.pump();

      expect(find.text('Post 1'), findsOneWidget);
      expect(find.text('Post 2'), findsOneWidget);
      expect(find.text('Post 3'), findsNothing);
      expect(provider.feed.currentPage, 1);
      expect(provider.feed.hasMore, isTrue);

      provider.dispose();
    },
  );
}
