import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_constants.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:like/src/services/like_mock_controller.dart';

class LikeMockInterceptor extends Interceptor {
  final Map<String, int> _uses = {};
  Object? _rulesIdentity;
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final mockCtrl = MockController();
    if (kReleaseMode ||
        !LikeConstants.mockEnabled ||
        !mockCtrl.isEngineEnabled.value) {
      return handler.next(options);
    }

    final rules = mockCtrl.rules.value;
    if (!identical(_rulesIdentity, rules)) {
      _uses.clear();
      _rulesIdentity = rules;
    }
    if (rules.isEmpty) {
      return handler.next(options);
    }

    final matchingRule = rules.firstWhere(
      (rule) {
        if (!rule.isEnabled ||
            (rule.maxUses > 0 && (_uses[rule.id] ?? 0) >= rule.maxUses)) {
          return false;
        }

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
      options.extra['like.synthetic'] = true;
      _uses[matchingRule.id] = (_uses[matchingRule.id] ?? 0) + 1;
      try {
        if (options.cancelToken?.isCancelled == true) {
          throw options.cancelToken!.cancelError!;
        }
        if (matchingRule.delayMs > 0) {
          await Future.any<void>([
            Future<void>.delayed(Duration(milliseconds: matchingRule.delayMs)),
            if (options.cancelToken != null)
              options.cancelToken!.whenCancel.then<void>(
                (error) => throw error,
              ),
          ]);
        }
        final failure = matchingRule.failure;
        if (failure != LikeMockFailure.none) {
          handler.reject(
            DioException(
              requestOptions: options,
              type: failure == LikeMockFailure.offline
                  ? DioExceptionType.connectionError
                  : failure == LikeMockFailure.timeout
                  ? DioExceptionType.receiveTimeout
                  : DioExceptionType.cancel,
              message: 'Synthetic test failure',
            ),
            true,
          );
          return;
        }
      } on DioException catch (error) {
        handler.reject(error, true);
        return;
      }

      dynamic responseData = matchingRule.responseBody;
      try {
        // Attempt to parse JSON response body so Dio handles it as parsed map/list if applicable
        responseData = jsonDecode(matchingRule.responseBody);
      } catch (_) {
        // Keep as string if not valid JSON
      }

      final response = Response(
        requestOptions: options,
        data: responseData,
        statusCode: matchingRule.statusCode,
        statusMessage: 'MOCKED',
        headers: Headers.fromMap(
          matchingRule.responseHeaders.map(
            (key, value) => MapEntry(key, [value]),
          ),
        ),
        extra: Map<String, dynamic>.from(options.extra)..['isMocked'] = true,
      );
      if (!(options.validateStatus(matchingRule.statusCode))) {
        handler.reject(
          DioException.badResponse(
            statusCode: matchingRule.statusCode,
            requestOptions: options,
            response: response,
          ),
          true,
        );
      } else {
        handler.resolve(response, true);
      }
      return;
    }

    return handler.next(options);
  }
}
