import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';
import 'package:like/src/services/like_pipeline.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../mocks/mocks.dart';

// 1. Model definitions matching the MealDB API schema
class Meal {
  final String id;
  final String name;
  final String category;
  final String area;
  final String thumbnail;

  Meal({
    required this.id,
    required this.name,
    required this.category,
    required this.area,
    required this.thumbnail,
  });

  factory Meal.fromJson(Map<String, dynamic> json) {
    return Meal(
      id: json['idMeal'] as String? ?? '',
      name: json['strMeal'] as String? ?? '',
      category: json['strCategory'] as String? ?? '',
      area: json['strArea'] as String? ?? '',
      thumbnail: json['strMealThumb'] as String? ?? '',
    );
  }
}

class MealResponse {
  final List<Meal> meals;

  MealResponse({required this.meals});

  factory MealResponse.fromJson(Map<String, dynamic> json) {
    final list = json['meals'] as List?;
    return MealResponse(
      meals: list == null
          ? []
          : list.map((m) => Meal.fromJson(m as Map<String, dynamic>)).toList(),
    );
  }
}

// 2. A real-world ChangeNotifier Provider representing a Meal catalog feature
class MealProvider extends ChangeNotifier {
  final LikeEngine engine = LikeEngine();
  final mealsState = LikeNotifierState<MealResponse>(
    mapper: (json) => MealResponse.fromJson(json as Map<String, dynamic>),
  );

  Future<void> fetchMeals(String searchKeyword) async {
    await engine.fetch<MealResponse>(
      state: mealsState,
      action: () async {
        // In a real app this would call the MealDB API:
        // https://www.themealdb.com/api/json/v1/1/search.php?s=searchKeyword
        // We simulate the API client returning the standard MealDB response:
        return LikeStateResponse<MealResponse>.success(
          MealResponse(meals: [
            Meal(
              id: '52771',
              name: 'Spaghetti Arrabiata',
              category: 'Vegetarian',
              area: 'Italian',
              thumbnail:
                  'https://www.themealdb.com/images/media/meals/ustqqw1468250487.jpg',
            ),
          ]),
        );
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MealDB API Pipeline & Mixin Integration', () {
    late MealProvider provider;

    setUpAll(() async {
      setupMocks();
      await initTestHive();
      await Hive.openBox(LikeConstants.boxApiCache);
      await Hive.openBox(LikeConstants.boxCacheMetadata);
      await Hive.openBox(LikeConstants.boxEtags);
      await Hive.openBox(LikeConstants.boxOfflineQueue);
    });

    setUp(() {
      provider = MealProvider();
    });

    tearDown(() {
      provider.engine.dispose();
      provider.dispose();
    });

    test(
        'should successfully fetch, map, and synchronize MealDB API response using pipeline',
        () async {
      // 1. Initial fetch of Spaghetti
      await provider.fetchMeals('Arrabiata');

      // Verify the state is success and parses the MealDB schema correctly
      expect(provider.mealsState.isSuccess, true);
      expect(provider.mealsState.data!.meals.length, 1);

      final spaghetti = provider.mealsState.data!.meals.first;
      expect(spaghetti.id, '52771');
      expect(spaghetti.name, 'Spaghetti Arrabiata');
      expect(spaghetti.category, 'Vegetarian');
      expect(spaghetti.area, 'Italian');

      // 2. Configure active path & query representing the active MealDB request
      provider.mealsState.endpointPath = '/api/json/v1/1/search.php';
      provider.mealsState.activeQuery = {'s': 'Arrabiata'};

      // 3. Emit a new response on the pipeline (e.g. from a background sync or mutation)
      // containing an updated list of meals matching the MealDB JSON payload structure.
      final mealDbPayload = {
        'meals': [
          {
            'idMeal': '52771',
            'strMeal': 'Spaghetti Arrabiata (Extra Spicy)',
            'strCategory': 'Vegetarian',
            'strArea': 'Italian',
            'strMealThumb':
                'https://www.themealdb.com/images/media/meals/ustqqw1468250487.jpg'
          },
          {
            'idMeal': '52800',
            'strMeal': 'Lasagna',
            'strCategory': 'Pasta',
            'strArea': 'Italian',
            'strMealThumb':
                'https://www.themealdb.com/images/media/meals/lasagna.jpg'
          }
        ]
      };

      LikePipeline().emit(
        'GET:/api/json/v1/1/search.php',
        Response(
          requestOptions: RequestOptions(
            path: '/api/json/v1/1/search.php',
            queryParameters: {'s': 'Arrabiata'},
          ),
          data: mealDbPayload,
        ),
      );

      // Await pipeline event delivery
      await Future.delayed(Duration.zero);

      // Verify the provider's state was automatically updated with the mapped data
      expect(provider.mealsState.isSuccess, true);
      expect(provider.mealsState.data!.meals.length, 2);

      final meal1 = provider.mealsState.data!.meals[0];
      final meal2 = provider.mealsState.data!.meals[1];

      expect(meal1.name, 'Spaghetti Arrabiata (Extra Spicy)');
      expect(meal2.name, 'Lasagna');
      expect(meal2.category, 'Pasta');
    });
  });
}
