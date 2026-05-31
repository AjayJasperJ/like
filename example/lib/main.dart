import 'package:flutter/material.dart';
import 'package:like/like.dart';
import 'package:provider/provider.dart';
import 'services/todo_service.dart';
import 'repositories/todo_repository.dart';
import 'providers/todo_provider.dart';
import 'ui/todo_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LikeService.init(
      config: LikeConfig(
    projectName: 'example_app',
    unpacker: const CustomLikeUnpacker(),
    baseUrl: 'https://jsonplaceholder.typicode.com',
  ));
  runApp(const LikeExampleApp());
}

class LikeExampleApp extends StatelessWidget {
  const LikeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Instantiate the generic network layer services and repositories
    final todoService = TodoService();
    final todoRepository = TodoRepository(todoService);

    return MultiProvider(
      providers: [
        // 2. Register the provider using standard ChangeNotifierProvider
        ChangeNotifierProvider(create: (_) => TodoProvider(todoRepository)),
      ],
      // 3. Wrap your root app in the 'Like' widget to initialize the engine
      child: Like(
        child: MaterialApp(
          title: 'LIKE Zero-Config Demo',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
          ),
          home: const TodoListScreen(),
        ),
      ),
    );
  }
}

/// Example of a Custom Data Unpacker.
/// To use this, change [unpacker] inside [LikeConfig] above to: `const CustomLikeUnpacker()`
class CustomLikeUnpacker extends LikeDataUnpacker {
  const CustomLikeUnpacker();

  @override
  LikeUnpackedResponse unpack(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return LikeUnpackedResponse(data: json);
    }

    // Custom envelope keys mapping:
    final data =
        json.containsKey('response_payload') ? json['response_payload'] : json;
    final message = json['msg']?.toString() ?? '';
    final isSuccess = json['status_code'] == 200 || json['success'] == true;
    final errors = json['error_details'] is Map<String, dynamic>
        ? json['error_details']
        : null;

    return LikeUnpackedResponse(
      data: data,
      message: message,
      isSuccess: isSuccess,
      errors: errors,
    );
  }
}
