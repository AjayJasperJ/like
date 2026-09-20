import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';

Future<void> initTestHive() async {
  final temp = Directory.systemTemp.createTempSync('hive_test');
  Hive.init(temp.path);
}

void setupMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async {
      if (methodCall.method == 'getApplicationDocumentsDirectory' ||
          methodCall.method == 'getTemporaryDirectory' ||
          methodCall.method == 'getApplicationSupportDirectory') {
        return Directory.systemTemp.path;
      }
      return null;
    },
  );
  messenger.setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/connectivity_status'),
    MockStreamHandler.inline(
      onListen: (arguments, events) {},
      onCancel: (arguments) {},
    ),
  );
}

// --- 1. Models ---
class Meal {
  final String id;
  final String name;

  Meal({required this.id, required this.name});

  factory Meal.fromJson(Map<String, dynamic> json) {
    return Meal(
      id: json['idMeal'] as String? ?? '',
      name: json['strMeal'] as String? ?? '',
    );
  }
}

class MealResponse {
  final List<Meal> meals;
  MealResponse({required this.meals});

  factory MealResponse.fromJson(Map<String, dynamic> json) {
    return MealResponse(
      meals: (json['meals'] as List?)
              ?.map((e) => Meal.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

// --- 2. Service ---
class MealService extends BaseApiService {
  Future<ApiResult<Response>> searchMeals(String query) {
    return get(
      '/search',
      query: {'s': query},
      withAuth: false,
    );
  }
}

// --- 3. Repository ---
class MealRepository {
  final MealService service;
  MealRepository(this.service);

  Future<ApiResult<MealResponse>> searchMeals(String query) {
    return service.searchMeals(query).mapAsync(
        (json) => MealResponse.fromJson(json as Map<String, dynamic>));
  }
}

// --- 4. Provider ---
class MealProvider extends ChangeNotifier {
  final LikeEngine engine = LikeEngine();
  final MealRepository repository;
  final mealsState = NotifierState<MealResponse>();

  MealProvider(this.repository);

  Future<void> searchMeals(String query) async {
    await engine.fetch<MealResponse>(
      state: mealsState,
      action: () async {
        final result = await repository.searchMeals(query);
        return result.toStateResponse();
      },
    );
  }
}

// --- 5. UI Application ---
class MealApp extends StatelessWidget {
  const MealApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(title: const Text('Meals (Flow)')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                key: const Key('searchInput'),
                decoration: const InputDecoration(
                  labelText: 'Search Meals',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (val) {
                  context.read<MealProvider>().searchMeals(val);
                },
              ),
            ),
            Expanded(
              child: LikeBuilder<MealResponse>(
                observe: () => context.read<MealProvider>().mealsState,
                onLoading: () => const Center(
                  child: CircularProgressIndicator(key: Key('loadingSpinner')),
                ),
                onError: (error) => Center(
                  child: Text(
                    'Error: ${error.message}',
                    key: const Key('errorText'),
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                onSuccess: (data, _, __) => ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: data.meals.length,
                  itemBuilder: (ctx, idx) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.fastfood)),
                      title: Text(data.meals[idx].name),
                    ),
                  ),
                ),
                onIdle: () => const Center(
                  child: Text('Initial State'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _E2EMockInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.path == '/search') {
      final query = options.queryParameters['s'];

      if (query == 'Pizza') {
        return handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'meals': [
                {'idMeal': '1', 'strMeal': 'Margherita Pizza'}
              ]
            },
          ),
        );
      } else if (query == 'Pasta') {
        return handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'meals': [
                {'idMeal': '2', 'strMeal': 'Spaghetti Carbonara'}
              ]
            },
          ),
        );
      } else {
        return handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'meals': []},
          ),
        );
      }
    }
    return handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
      ),
    );
  }
}

// --- 6. The E2E Test ---
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    setupMocks();
    await initTestHive();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  setUp(() async {
    LikeClient.reset();
    await LikeConnectivityManager().reset();
    LikeConnectivityManager().debugConfigure(
      interfaceCheck: () async => [ConnectivityResult.wifi],
      internetCheck: (host, timeout) async => true,
      serverCheck: (host, port, timeout) async => true,
    );

    final mockDio = Dio(BaseOptions(baseUrl: 'http://test.api'))
      ..interceptors.add(_E2EMockInterceptor());
    LikeClient(dio: mockDio);

    await LikeService.init(
      config: LikeConfig(
        projectName: 'e2e_test',
        baseUrl: 'http://test.api',
      ),
    );
  });

  testWidgets(
      'E2E Flow: Validates UI Updates, API Parsing, and Request Cancellation',
      (WidgetTester tester) async {
    final service = MealService();
    final repository = MealRepository(service);
    final provider = MealProvider(repository);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MealApp(),
      ),
    );

    expect(find.text('Initial State'), findsOneWidget);

    // Initiate and join only the Dio operations in the real async zone. Widget
    // pumping stays in fake async, avoiding cross-zone timers and broad wrappers.
    await tester.runAsync(() async {
      final pizza = provider.searchMeals('Pizza');
      final pasta = provider.searchMeals('Pasta');
      await Future.wait<void>([pizza, pasta]);
    });
    await tester.pump();

    expect(find.byKey(const Key('loadingSpinner')), findsNothing);
    expect(find.text('Spaghetti Carbonara'), findsOneWidget);
    expect(find.text('Margherita Pizza'), findsNothing);
    expect(provider.mealsState.isSuccess, true);
    expect(provider.mealsState.data?.meals.length, 1);
    expect(provider.mealsState.data?.meals.first.name, 'Spaghetti Carbonara');
  });
}
