import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:like/src/services/like_mock_controller.dart';

class LikeMockInterceptor extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final mockCtrl = MockController();
    if (!mockCtrl.isEngineEnabled.value) {
      return handler.next(options);
    }

    final rules = mockCtrl.rules.value;
    if (rules.isEmpty) {
      return handler.next(options);
    }

    final matchingRule = rules.firstWhere(
      (rule) {
        if (!rule.isEnabled) return false;

        // 1. Match method
        if (rule.method != 'ANY' && rule.method != options.method) {
          return false;
        }

        // 2. Match Base URL (Optional)
        if (rule.baseUrlPattern.isNotEmpty) {
          final host = options.uri.host;
          final fullUrl = options.uri.toString();
          if (rule.useRegex) {
            try {
              if (!RegExp(rule.baseUrlPattern).hasMatch(host) &&
                  !RegExp(rule.baseUrlPattern).hasMatch(fullUrl)) {
                return false;
              }
            } catch (e) {
              return false;
            }
          } else {
            if (!host.contains(rule.baseUrlPattern) &&
                !fullUrl.contains(rule.baseUrlPattern)) {
              return false;
            }
          }
        }

        // 3. Match path/pattern
        final path = options.path;
        bool pathMatches = false;
        if (rule.useRegex) {
          try {
            pathMatches = RegExp(rule.pathPattern).hasMatch(path);
          } catch (_) {}
        } else {
          pathMatches =
              path == rule.pathPattern || path.startsWith(rule.pathPattern);
        }

        if (!pathMatches) return false;

        // 4. Match Query Parameters (Optional)
        if (rule.queryParametersPattern.isNotEmpty) {
          final query = options.uri.query;
          if (rule.useRegex) {
            try {
              if (!RegExp(rule.queryParametersPattern).hasMatch(query)) {
                return false;
              }
            } catch (e) {
              return false;
            }
          } else {
            if (!query.contains(rule.queryParametersPattern)) {
              return false;
            }
          }
        }

        // 5. Match Headers (Optional)
        if (rule.headersPattern.isNotEmpty) {
          final headersStr = options.headers.toString();
          if (rule.useRegex) {
            try {
              if (!RegExp(rule.headersPattern).hasMatch(headersStr)) {
                return false;
              }
            } catch (e) {
              return false;
            }
          } else {
            if (!headersStr.contains(rule.headersPattern)) {
              return false;
            }
          }
        }

        // 6. Match Request Body (Optional)
        if (rule.requestBodyPattern.isNotEmpty) {
          final body = options.data?.toString() ?? '';
          if (rule.useRegex) {
            try {
              if (!RegExp(rule.requestBodyPattern).hasMatch(body)) {
                return false;
              }
            } catch (e) {
              return false;
            }
          } else {
            if (!body.contains(rule.requestBodyPattern)) {
              return false;
            }
          }
        }

        return true;
      },
      orElse: () => MockRule(
        id: '',
        pathPattern: '',
        method: '',
        responseBody: '',
        isEnabled: false,
      ),
    );

    if (matchingRule.id.isNotEmpty) {
      dynamic responseData = matchingRule.responseBody;
      try {
        // Attempt to parse JSON response body so Dio handles it as parsed map/list if applicable
        responseData = jsonDecode(matchingRule.responseBody);
      } catch (_) {
        // Keep as string if not valid JSON
      }

      return handler.resolve(
        Response(
          requestOptions: options,
          data: responseData,
          statusCode: matchingRule.statusCode,
          statusMessage: 'OK (MOCKED)',
          extra: Map.from(options.extra)..['isMocked'] = true,
        ),
      );
    }

    return handler.next(options);
  }
}
