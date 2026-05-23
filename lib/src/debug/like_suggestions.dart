import 'package:flutter/foundation.dart';

class LikeSuggestion {
  final String name;
  final String type; // 'Widget', 'Method', 'Class', 'Mixin'
  final String useCase;
  final String description;
  final String code;

  const LikeSuggestion({
    required this.name,
    required this.type,
    required this.useCase,
    required this.description,
    required this.code,
  });
}

bool _hasPrintedSuggestion = false;

void printRandomSuggestion() {
  if (_hasPrintedSuggestion) return;
  _hasPrintedSuggestion = true;
  final random = DateTime.now().millisecond;
  final index = random % _suggestions.length;
  final suggestion = _suggestions[index];
  final separator = '\x1B[90m${'─' * 70}\x1B[0m';
  debugPrint(separator);
  debugPrint('\x1B[1m\x1B[32m🚀 [LIKE] Initialization successful!\x1B[0m');
  debugPrint(separator);
  debugPrint('\x1B[1m\x1B[33m💡 Suggestion of the Debug:\x1B[0m');
  debugPrint(separator);
  debugPrint(
      '\x1B[1m\x1B[36m🚀 ${suggestion.name}\x1B[0m  \x1B[90m(${suggestion.type})\x1B[0m');
  debugPrint(
      '\x1B[1m\x1B[32m💡 Use Case:\x1B[0m \x1B[32m${suggestion.useCase}\x1B[0m');
  debugPrint(
      '\x1B[1m\x1B[34m📝 What it does:\x1B[0m ${suggestion.description}');
  debugPrint(separator);
  debugPrint('\x1B[1m\x1B[35m💻 How to Use:\x1B[0m');
  for (final line in suggestion.code.split('\n')) {
    debugPrint('\x1B[90m  $line\x1B[0m');
  }
  debugPrint(separator);
}

const List<LikeSuggestion> _suggestions = [
  LikeSuggestion(
    name: 'Like',
    type: 'Widget',
    useCase: 'App Core Initialization',
    description:
        'The root-level wrapper widget that configures base URLs, JWT token callbacks, offline synchronization, automated haptic alerts, and developer devtool overlays.',
    code: '''Like(
  baseUrl: 'https://www.themealdb.com',
  getToken: () => storage.read('jwt_token'),
  refreshToken: () => auth.refreshSession(),
  devTool: (child) => LikeDevTool(child: child),
  child: const MyApp(),
)''',
  ),
  LikeSuggestion(
    name: 'LikeBuilder<T>',
    type: 'Widget',
    useCase: 'Reactive State Binding',
    description:
        'Binds dynamic network and cache states seamlessly to Flutter widgets. Automatically manages transitions between loading, SWR cache, success, and error states without manually handling booleans.',
    code: '''LikeBuilder<List<Meal>>(
  observe: () => mealProvider.mealsResponse,
  onSuccess: (meals, isRefreshing, isFromSWR) => MealList(meals),
  onLoading: () => const LoadingIndicator(),
  onError: (err) => Text('Error: \${err.message}'),
)''',
  ),
  LikeSuggestion(
    name: 'LikeSliverBuilder<T>',
    type: 'Widget',
    useCase: 'Sliver Layout Pattern Matching',
    description:
        'The sliver variant of LikeBuilder. Resolves asynchronous state changes and renders matching lists or grids of sliver widgets inside CustomScrollViews.',
    code: '''LikeSliverBuilder<List<Meal>>(
  observe: () => mealProvider.mealsResponse,
  onSuccess: (meals, isRefreshing, isFromSWR) => [
    SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => MealCard(meals[index]),
        childCount: meals.length,
      ),
    ),
  ],
  onLoading: () => [
    const SliverToBoxAdapter(child: Spinner()),
  ],
)''',
  ),
  LikeSuggestion(
    name: 'LikeSelector<T, S>',
    type: 'Widget',
    useCase: 'Fine-Grained Performance Optimization',
    description:
        'Filters state mutations to optimize performance. Rebuilds only when the specific property or slice you select from the model changes, avoiding full-screen redraws.',
    code: '''LikeSelector<User, String>(
  observe: () => provider.userState,
  selector: (state) => state.data?.avatarUrl ?? '',
  builder: (context, avatarUrl, child) => Avatar(avatarUrl),
)''',
  ),
  LikeSuggestion(
    name: 'LikeSelectorSliver<T, S>',
    type: 'Widget',
    useCase: 'Performance Optimized Sliver Rebuilding',
    description:
        'The sliver version of LikeSelector. Redraws list segments inside a CustomScrollView only when the observed property transitions.',
    code: '''LikeSelectorSliver<List<Meal>, int>(
  observe: () => provider.mealsState,
  selector: (meals) => meals.length,
  onSuccess: (count, isRefreshing, isSWR) => [
    SliverToBoxAdapter(child: Text('Total meals: \$count')),
  ],
)''',
  ),
  LikeSuggestion(
    name: 'LikeMultiBuilder',
    type: 'Widget',
    useCase: 'Multiple Requests Coordinator',
    description:
        'Unifies multiple concurrent network requests (e.g. Profile + Feed + Settings) into a single cohesive UI flow. Listens and rebuilds on any combined notifier updates.',
    code: '''LikeMultiBuilder(
  observe: [profileState, notificationState],
  builder: (context) => Dashboard(
    profile: profileState.value.data,
    notifications: notificationState.value.data,
  ),
)''',
  ),
  LikeSuggestion(
    name: 'LikeMultiSliverBuilder',
    type: 'Widget',
    useCase: 'Coordinate Multiple Sliver States',
    description:
        'Coordinates and renders multiple concurrent network state models inside a CustomScrollView, triggering a rebuild on any update.',
    code: '''LikeMultiSliverBuilder(
  observe: [featuredMeals, recommendedMeals],
  builder: (context) => [
    FeaturedSliverList(meals: featuredMeals.value.data),
    RecommendedSliverGrid(meals: recommendedMeals.value.data),
  ],
)''',
  ),
  LikeSuggestion(
    name: 'LikeWhen<T>',
    type: 'Widget',
    useCase: 'Pattern Matching UI',
    description:
        'Enables quick, zero-boilerplate pattern matching for any LikeStateResponse<T> state snapshot. Extremely useful for clean, inline build returns in nested widgets.',
    code: '''LikeWhen(
  response: provider.myResponse,
  onSuccess: (data) => DataWidget(data),
  onLoading: () => const Spinner(),
  onError: (error) => Text(error.message),
)''',
  ),
  LikeSuggestion(
    name: 'LikeCacheImage',
    type: 'Widget',
    useCase: 'Secure Offline Image Rendering',
    description:
        'Transparently handles secure local caching for remote images. Files are written using per-device 256-bit AES-CBC encryption with unique per-file IVs. Cleans tracking queries automatically.',
    code: '''LikeCacheImage(
  imageUrl: 'https://api.com/image.jpg?auth=xyz',
  width: 120,
  height: 120,
  fit: BoxFit.cover,
)''',
  ),
  LikeSuggestion(
    name: 'LikeClient',
    type: 'Class',
    useCase: 'Custom API Requests execution',
    description:
        'The core HTTP networking engine. Combines custom retry logic, offline syncing, SWR cache checks, and automatic request registries.',
    code: '''final client = LikeClient();
final result = await client.get<Meal>(
  '/random.php',
  unpack: (json) => Meal.fromJson(json),
);''',
  ),
  LikeSuggestion(
    name: 'LikeService',
    type: 'Class',
    useCase: 'Central Cache & Pipeline management',
    description:
        'Provides programmatic controls for manual offline outbox synchronization, database wipes, or diagnostic telemetry logs.',
    code: '''// Wipes all Hive persistent states cleanly
await LikeService.clearCache();

// Force immediate syncing process
await LikeService.triggerManualSync();''',
  ),
  LikeSuggestion(
    name: 'LikePipeline',
    type: 'Class',
    useCase: 'Cross-Viewport Stream Synchronization',
    description:
        'A global reactive stream bus that dispatches data mutations to automatically refresh identical API models rendered in detached viewports.',
    code: '''// Instantly synchronizes all viewports listening to /meals
LikePipeline.dispatch(
  LikeEvent.success('/meals', updatedMealsList),
);''',
  ),
  LikeSuggestion(
    name: 'LikeConnectivityManager',
    type: 'Class',
    useCase: 'Real-time Connection & Server Pings',
    description:
        'Monitors physical network states and actively pings the target API server to determine true, resilient availability.',
    code: '''final manager = LikeConnectivityManager();
bool isOnline = manager.hasConnection;

manager.connectionChange.listen((online) {
  debugPrint('Resilient online status: \$online');
});''',
  ),
  LikeSuggestion(
    name: 'LikeOfflineSyncManager',
    type: 'Class',
    useCase: 'Inspect Offline Sync Outbox',
    description:
        'Queries and controls the offline-buffered POST/PUT request queues. Tasks automatically execute sequentially upon connection recovery.',
    code: '''final manager = LikeOfflineSyncManager();
List<LikeSyncTask> pending = manager.getPendingTasks();
debugPrint('Pending offline syncs: \${pending.length}');''',
  ),
  LikeSuggestion(
    name: 'LikeLogger',
    type: 'Class',
    useCase: 'Debugging Network Operations',
    description:
        'A high-fidelity console logger that records detailed HTTP states, timing metrics, and offline outbox synchronizations to memory or local text files.',
    code: '''LikeLogger.info('Manual database flush executed.');
LikeLogger.error('API responded with non-JSON format.');''',
  ),
  LikeSuggestion(
    name: 'AppCacheManager',
    type: 'Class',
    useCase: 'Persistent Disk Storage Optimization',
    description:
        'Manages disk space utilization. Automatically purges encrypted image files and stale JSON documents when device directories fill up.',
    code: '''// Wipes specific cached URL results
await AppCacheManager.remove('/meals');
// Cleans all image cache binaries
await AppCacheManager.clear();''',
  ),
  LikeSuggestion(
    name: 'MockController',
    type: 'Class',
    useCase: 'Local Mock Staging & Testing',
    description:
        'Intercepts real outgoing network traffic to immediately serve pre-registered mock JSON files, bypassing server calls completely.',
    code: '''final mocks = MockController();
mocks.registerMock(
  path: '/meals',
  method: 'GET',
  response: {'meals': []},
);''',
  ),
  LikeSuggestion(
    name: 'LikeAutoReconnectMixin',
    type: 'Mixin',
    useCase: 'Automatic Page Revalidation',
    description:
        'A convenient State mixin for pages that need to automatically trigger data re-validation or refresh fetches when internet goes back online.',
    code: '''class _FeedState extends State<Feed> with LikeAutoReconnectMixin {
  @override
  void onReconnect() {
    mealProvider.fetchMeals(); // Fetches new meals!
  }

  @override
  Widget build(BuildContext context) => const Text('Connected List');
}''',
  ),
  LikeSuggestion(
    name: 'updateNotifier',
    type: 'Method',
    useCase: 'Automated POST/PUT Mutation Side Effects',
    description:
        'Executes mutations. Automatically triggers floating animated alerts, schedules system haptics, updates caches, and handles callback states.',
    code: '''await updateNotifier<Meal>(
  action: () => api.postMeal(newMeal),
  successMessage: 'Meal successfully posted!',
  onSuccess: (meal) => navigateBack(),
);''',
  ),
  LikeSuggestion(
    name: 'likeWhenNotifier',
    type: 'Method',
    useCase: 'Silent Mutation execution',
    description:
        'Runs backend POST/PUT operations silently in the background, suppressing automatic UI notifications and vibration triggers.',
    code: '''await likeWhenNotifier<void>(
  action: () => api.logTelemetry(event),
  onSuccess: (_) => debugPrint('Telemetry reported successfully.'),
);''',
  ),
  LikeSuggestion(
    name: 'ARS',
    type: 'Class',
    useCase: 'API Endpoint Cache Configurations',
    description:
        'Defines request strategies (Auto-Revalidate-Sync) governing cache expiry, offline storage bypass, or immediate revalidation.',
    code: '''final option = ARS(
  strategy: CacheStrategy.swr,
  cacheExpiry: const Duration(days: 7),
  forceRefresh: true,
);''',
  ),
  LikeSuggestion(
    name: 'LikeConfig',
    type: 'Class',
    useCase: 'API Client Configuration Setup',
    description:
        'Wraps fundamental options for the client factory covering timeouts, base URLs, retry timings, and outbox behaviors.',
    code: '''final config = LikeConfig(
  connectTimeout: const Duration(seconds: 15),
  maxRetries: 3,
  enableOfflineQueue: true,
);''',
  ),
];
