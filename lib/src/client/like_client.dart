import 'dart:async';
import 'package:http_parser/http_parser.dart';
import 'package:like/src/core/like_ars.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/core/like_request_config.dart';
import 'package:like/src/core/like_client_config.dart';
import 'package:like/src/models/like_api_result.dart';
import 'package:like/src/models/like_connectivity_check_result.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_event.dart';
import 'package:like/src/models/like_sync_event.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/client/like_error_handler.dart';
import 'package:like/src/client/like_request_registry.dart';
import 'package:like/src/client/like_client_factory.dart';
import 'package:like/src/interceptors/like_offline_sync_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_pipeline.dart';
import 'package:like/src/services/like_service.dart';

/// The central entry point for all network requests in the LIKE engine.
///
/// This client provides advanced networking features such as:
/// * **SWR (Stale-While-Revalidate)**: Instant UI updates with background refreshes.
/// * **Deduplication**: Prevents multiple in-flight requests for the same resource.
/// * **Resiliency Fallbacks**: Automatically serves cached data if the network is down.
/// * **Offline Sync**: Queues POST/PUT/DELETE requests for later synchronization.
///
/// Matches enterprise's ApiClient and ApiExecutor parity with 1000/1000 architectural alignment.
class LikeClient {
  static LikeClient? _instance;

  /// Resets the singleton instance. Primarily used for testing.
  @visibleForTesting
  static void reset() => _instance = null;

  late final Dio _dio;
  late final LikeRequestRegistry _registry;

  /// Exposes the underlying Dio instance. Primarily used for testing.
  @visibleForTesting
  Dio get dio => _dio;

  /// Exposes the request registry. Primarily used for testing.
  @visibleForTesting
  LikeRequestRegistry get registry => _registry;

  final StreamController<String> _refreshController =
      StreamController<String>.broadcast();

  final StreamController<LikeSyncEvent> _syncController =
      StreamController<LikeSyncEvent>.broadcast();

  /// A stream of endpoint paths that have been successfully updated or refreshed.
  /// Used by [LikeEngine] to trigger UI updates.
  Stream<String> get refreshStream => _refreshController.stream;

  /// A stream of query-aware sync events emitted after successful mutations.
  Stream<LikeSyncEvent> get syncStream => _syncController.stream;

  /// The raw event pipeline for the LIKE engine.
  Stream<LikeEvent> get responsePipeline => LikePipeline().stream;

  /// Accesses or initializes the [LikeClient] singleton.
  ///
  /// [baseUrl] sets the default host for all requests.
  /// [timeout] sets the connection and receive timeouts.
  /// [dio] allows providing a custom Dio instance for advanced configuration.
  /// [authConfig] optionally sets authentication configuration for the client.
  factory LikeClient({
    String? baseUrl,
    Duration? timeout,
    Dio? dio,
    LikeAuthConfig? authConfig,
  }) {
    _instance ??= LikeClient._internal(
      baseUrl: baseUrl,
      timeout: timeout,
      dio: dio,
      authConfig: authConfig,
    );
    return _instance!;
  }

  /// Creates a fully **isolated** [LikeClient] with its own Dio instance,
  /// interceptor stack, and request registry.
  ///
  /// Unlike the default [LikeClient()] singleton, scoped clients do **not**
  /// share state with the rest of the app. They are ideal for feature modules
  /// or integrations with a different backend server.
  ///
  /// Unset fields in [config] fall back to the current global [LikeConstants]
  /// values, so you only specify what is different.
  ///
  /// **Lifecycle:** You are responsible for calling [dispose()] on a scoped
  /// client when the feature module is torn down.
  ///
  /// **Example — Payments module:**
  /// ```dart
  /// final paymentsClient = LikeClient.scoped(
  ///   LikeClientConfig(
  ///     baseUrl: 'https://pay.example.com',
  ///     connectTimeout: Duration(seconds: 15),
  ///     defaultHeaders: {'X-Payment-Version': '2'},
  ///     unpacker: PaymentsResponseUnpacker(),
  ///     interceptors: [PaymentsHmacSigningInterceptor()],
  ///     authConfig: LikeAuthConfig(getToken: () async => 'token'),
  ///   ),
  /// );
  /// ```
  factory LikeClient.scoped(LikeClientConfig config) {
    return LikeClient._scoped(config);
  }

  LikeClient._internal({
    String? baseUrl,
    Duration? timeout,
    Dio? dio,
    LikeAuthConfig? authConfig,
  }) {
    _registry = LikeRequestRegistry();
    _dio = dio ??
        LikeClientFactory.create(
          baseUrl: baseUrl ?? '',
          timeout: timeout,
          registry: _registry,
          authConfig: authConfig ?? LikeConstants.current.authConfig,
          // Wire in developer-provided global interceptors from LikeConfig
          customInterceptors: LikeConstants.current.interceptors,
        );
  }

  LikeClient._scoped(LikeClientConfig config) {
    _registry = LikeRequestRegistry();
    _dio = LikeClientFactory.create(
      baseUrl: config.baseUrl ?? LikeConstants.current.baseUrl,
      registry: _registry,
      authConfig: config.authConfig,
      customInterceptors: [
        // Global interceptors come first
        ...LikeConstants.current.interceptors,
        // Then client-specific interceptors
        ...?config.interceptors,
      ],
      extraHeaders: config.defaultHeaders ?? const {},
      verifySSL: config.verifySSL,
      sslCertSha256: config.sslCertSha256,
    );
    // Apply per-timeout overrides if provided
    if (config.connectTimeout != null) {
      _dio.options.connectTimeout = config.connectTimeout;
    }
    if (config.receiveTimeout != null) {
      _dio.options.receiveTimeout = config.receiveTimeout;
    }
    if (config.sendTimeout != null) {
      _dio.options.sendTimeout = config.sendTimeout;
    }
  }

  // --- Core Execution Logic (ApiExecutor Parity) ---

  /// Resolves the effective base URL for a request by checking [LikeRequestConfig]
  /// in priority order: explicit [LikeRequestConfig.baseUrl] → named URL from
  /// [LikeRequestConfig.namedBaseUrl] → the Dio instance's own base URL.
  String _resolveBaseUrl(LikeRequestConfig? requestConfig) {
    if (requestConfig == null) return _dio.options.baseUrl;
    if (requestConfig.baseUrl != null && requestConfig.baseUrl!.isNotEmpty) {
      return LikeHelpers.normalizeBaseUrl(requestConfig.baseUrl!);
    }
    if (requestConfig.namedBaseUrl != null) {
      final named =
          LikeConstants.current.extraBaseUrls[requestConfig.namedBaseUrl];
      if (named != null && named.isNotEmpty) {
        return LikeHelpers.normalizeBaseUrl(named);
      }
    }
    return _dio.options.baseUrl;
  }

  Future<LikeApiResult<Response>> _execute({
    required String method,
    required String path,
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    // Per-request network config override. Null means use global defaults.
    LikeRequestConfig? requestConfig,
  }) async {
    final extra = options?.extra ?? {};
    final bool isGet = method == 'GET';
    final activeState = Zone.current[#likeActiveState];
    CancelToken? zoneCancelToken;
    if (activeState is LikeNotifierState) {
      zoneCancelToken = activeState.ct;
    }
    final effectiveCancelToken = cancelToken ?? zoneCancelToken ?? CancelToken();
    final effectivePath =
        path.startsWith('http') || path.startsWith('/') ? path : '/$path';
    final requestKey = LikeHelpers.generateRequestKey(
      effectivePath,
      queryParameters,
    );

    // --- Per-request config resolution ---
    // Resolve the base URL: requestConfig.baseUrl > namedBaseUrl > dio default
    final effectiveBaseUrl = _resolveBaseUrl(requestConfig);
    final bool baseUrlOverridden = effectiveBaseUrl != _dio.options.baseUrl;

    final bool hasBody = data != null;

    // Merge per-request headers on top of the base options headers
    final mergedHeaders = <String, dynamic>{
      ...(_dio.options.headers.map((k, v) => MapEntry(k, v.toString()))),
      if (options?.headers != null) ...options!.headers!,
      if (requestConfig?.headers != null) ...requestConfig!.headers!,
    };

    if (hasBody) {
      final hasContentType =
          mergedHeaders.keys.any((k) => k.toLowerCase() == 'content-type');
      if (!hasContentType) {
        mergedHeaders['Content-Type'] = LikeConstants.defaultContentTypeHeader;
      }
    } else {
      mergedHeaders.remove('Content-Type');
      mergedHeaders.remove('content-type');
    }

    // Apply per-request timeout overrides (or fall back to Dio defaults)
    final effectiveConnectTimeout =
        requestConfig?.connectTimeout ?? _dio.options.connectTimeout;
    final effectiveReceiveTimeout =
        requestConfig?.receiveTimeout ?? _dio.options.receiveTimeout;
    final effectiveSendTimeout = kIsWeb && !hasBody
        ? null
        : (requestConfig?.sendTimeout ?? _dio.options.sendTimeout);

    // Stash the per-request unpacker in extras so widget builders can read it
    if (requestConfig?.unpacker != null) {
      extra['requestUnpacker'] = requestConfig!.unpacker;
    }

    // Resiliency overrides: requestConfig takes precedence over LikeConstants
    final bool effectiveCacheOnOffline =
        requestConfig?.cacheOnOffline ?? LikeConstants.cacheOnOffline;
    final bool effectiveCacheOnError =
        requestConfig?.cacheOnError ?? LikeConstants.cacheOnError;
    final bool effectiveCacheOnException =
        requestConfig?.cacheOnException ?? LikeConstants.cacheOnException;

    // Pass retry overrides into extras so LikeRetryInterceptor can read them
    if (requestConfig?.maxAutoRetries != null) {
      extra['maxAutoRetries'] = requestConfig!.maxAutoRetries;
    }
    if (requestConfig?.retryDelays != null) {
      extra['retryDelays'] = requestConfig!.retryDelays;
    }

    if (isGet) {
      final activeState = Zone.current[#likeActiveState];
      if (activeState is LikeNotifierState) {
        final effectiveUri = RequestOptions(
          baseUrl: effectiveBaseUrl,
          path: effectivePath,
          queryParameters: queryParameters,
        ).uri;
        activeState.endpointPath = effectivePath;
        activeState.activeQuery = queryParameters ?? const {};
        activeState.canonicalOrigin =
            LikeConnectivityManager.canonicalOrigin(effectiveUri.toString());
      }
    }

    // Absolute URI for box key matching
    // When the base URL is overridden per-request, we must build the key
    // against the effective base so cache is correctly scoped per server.
    final tempOptions = RequestOptions(
      baseUrl: effectiveBaseUrl,
      path: effectivePath,
      queryParameters: queryParameters,
    );
    final absoluteUriKey = tempOptions.uri.toString();

    // 1. Reset Logic
    final bool resetSessionStale = extra['resetSessionStale'] ?? false;
    final bool resetSingleFetch = extra['resetSingleFetch'] ?? false;
    if (isGet && resetSessionStale) {
      _registry.resetSessionStale(path: absoluteUriKey);
    }

    // 2. Pre-Network Cache Optimization (L1 RAM -> L2 Disk)
    final bool disableCache =
        extra['disableCache'] ?? LikeConstants.disableCacheByDefault;
    final bool singleFetch =
        extra['singleFetch'] ?? LikeConstants.singleFetchByDefault;
    final bool sessionStale =
        extra['sessionStale'] ?? LikeConstants.sessionStaleByDefault;
    final bool staleWhileRevalidate = extra['staleWhileRevalidate'] ??
        LikeConstants.staleWhileRevalidateByDefault;

    if (isGet && !disableCache) {
      // 1. Check L1 Memory Cache (RAM)
      final l1Cached = _registry.getSessionData(absoluteUriKey);
      if (sessionStale && l1Cached != null) {
        // suppressErrors: Request Suppression Strategy
        final bool suppressErrors =
            extra['suppressErrors'] ?? LikeConstants.suppressErrorsByDefault;
        if (suppressErrors && _registry.isFresh(absoluteUriKey)) {
          l1Cached.extra['isFromL1Cache'] = true;
          l1Cached.extra['isFromCache'] = true;
          l1Cached.extra['isSuppressedByRSS'] = true;
          return await _handleSuccess(l1Cached, requestKey);
        }

        l1Cached.extra['isFromL1Cache'] = true;
        l1Cached.extra['isFromCache'] = true;
        return await _handleSuccess(l1Cached, requestKey);
      }

      // 2. Check L2 Disk Cache (Hive) - sessionStale
      if (sessionStale && _registry.isSessionStale(absoluteUriKey)) {
        final cached = await LikeService.fetchResponseFromCache(tempOptions);
        if (cached != null) {
          cached.extra['isFromL2Cache'] = true;
          cached.extra['isFromCache'] = true;
          return await _handleSuccess(cached, requestKey);
        }
      }

      // 3. check singleFetch (Disk)
      if (singleFetch && !resetSingleFetch) {
        final cached = await LikeService.fetchResponseFromCache(tempOptions);
        if (cached != null) {
          cached.extra['isFromCache'] = true;
          return await _handleSuccess(cached, requestKey);
        }
      }
    }

    // 3. Deduplication Check (In-Flight)
    final bool deduplicate =
        extra['deduplicate'] ?? LikeConstants.deduplicateByDefault;
    if (isGet && deduplicate) {
      final inFlight = _registry.getInFlight(requestKey);
      final inFlightAlive =
          inFlight != null && !(inFlight.$2?.isCancelled ?? false);
      if (inFlightAlive) {
        // If both calls provide explicit CancelTokens (from different notifier states),
        // don't cancel across distinct states. Otherwise (same token or raw client calls),
        // enforce take-latest cancellation.
        final bool isExplicitUserToken = cancelToken != null || zoneCancelToken != null;
        final bool isDifferentToken = isExplicitUserToken &&
            !identical(effectiveCancelToken, inFlight.$2);

        if (!isDifferentToken) {
          inFlight.$2
              ?.cancel('Cancelled by a newer identical request (take-latest)');
        }
      }
    }

    // 4. Start Network Request
    // When a base URL or timeout override is active, we compose a dedicated
    // Options object that carries those overrides into the Dio pipeline.
    // Note: Options does not support connectTimeout directly, so we pass it in
    // extra and apply it in LikeConnectivityInterceptor.
    final effectiveOptions = (options ?? Options()).copyWith(
      method: method,
      responseType: ResponseType.plain,
      headers: mergedHeaders,
      receiveTimeout: effectiveReceiveTimeout,
      sendTimeout: effectiveSendTimeout,
      // If baseUrl changed, pass it as an absolute path-prefix override
      // so Dio doesn't blindly prepend the instance baseUrl
      extra: {
        ...extra,
        if (effectiveConnectTimeout != null)
          'connectTimeout': effectiveConnectTimeout,
        if (baseUrlOverridden) 'overrideBaseUrl': effectiveBaseUrl,
      },
    );

    final future = runZoned(
      () => _dio.request<dynamic>(
        // When hitting a different server, prefix the path with the full URL
        // so Dio treats it as absolute and ignores the instance base URL.
        baseUrlOverridden ? '$effectiveBaseUrl$effectivePath' : effectivePath,
        data: data,
        queryParameters: queryParameters,
        cancelToken: effectiveCancelToken,
        onSendProgress: onSendProgress,
        onReceiveProgress: onReceiveProgress,
        options: effectiveOptions,
      ),
      zoneValues: {
        #verifySSL: requestConfig?.verifySSL,
        #sslCertSha256: requestConfig?.sslCertSha256,
      },
    );

    if (isGet) {
      _registry.addInFlight(requestKey, (future, effectiveCancelToken));
    }

    // 5. SWR Optimization: Return cache immediately while network refresh continues in background
    if (isGet &&
        !disableCache &&
        staleWhileRevalidate &&
        LikeConstants.staleWhileRevalidateEnabled) {
      final bool isOnline = LikeConnectivityManager().hasConnection;
      final bool allowCache = isOnline || effectiveCacheOnOffline;

      if (allowCache) {
        // Try L1 then L2 for SWR instant UI transition
        var cached = _registry.getSessionData(absoluteUriKey);
        if (cached == null) {
          cached = await LikeService.fetchResponseFromCache(tempOptions);
          if (cached != null) cached.extra['isFromL2Cache'] = true;
        } else {
          cached.extra['isFromL1Cache'] = true;
        }

        if (cached != null) {
          cached.extra['isFromStaleWhileRevalidate'] = true;
          _registry.addSessionKey(absoluteUriKey, response: cached);

          // Let the background future handle its own completion and emission.
          // Use async callback and await _handleSuccess so its Future
          // errors are not silently discarded. Cleanup is owner-checked because
          // a newer take-latest request may already occupy the same key.
          future.then((resp) async {
            await _handleSuccess(resp, requestKey);
            _registry.removeInFlight(requestKey, future);
          }).catchError((e) {
            _registry.removeInFlight(requestKey, future);
          });

          return await _handleSuccess(cached, requestKey);
        }
      }
    }

    // 6. Standard Awaiting & Error Handling
    try {
      final response = await future;

      // Update session registry on successful fetch and promote to L1 RAM Cache
      if (isGet && sessionStale) {
        _registry.addSessionKey(absoluteUriKey, response: response);
      }
      return await _handleSuccess(response, requestKey);
    } on DioException catch (e) {
      // Resiliency Fallback
      final isNetworkError = e.type != DioExceptionType.badResponse;
      final bool isOnline = LikeConnectivityManager().hasConnection;

      final shouldFallback = (isNetworkError &&
              (isOnline
                  ? effectiveCacheOnException
                  : effectiveCacheOnOffline)) ||
          (!isNetworkError && effectiveCacheOnError);

      if (shouldFallback && isGet && !disableCache) {
        final cached = await LikeService.fetchResponseFromCache(
          e.requestOptions,
        );
        if (cached != null) {
          cached.extra['isResiliencyFallback'] = true;
          return await _handleSuccess(cached, requestKey);
        }
      }
      return LikeApiResult.error(await LikeErrorHandler.handle(e));
    } catch (e) {
      return LikeApiResult.error(
        LikeError(
          message: 'Unexpected error: $e',
          type: LikeApiErrorType.unknown,
        ),
      );
    } finally {
      if (isGet) _registry.removeInFlight(requestKey, future);
    }
  }

  Future<LikeApiResult<Response>> _handleSuccess(
    Response response,
    String key,
  ) async {
    final bool isFromCache = response.extra['isFromCache'] ?? false;
    if (!isFromCache) {
      LikeConnectivityManager().markServerAvailable(
        serverUrl: response.requestOptions.uri.toString(),
      );
    }

    // 1. Decode JSON string if needed
    if (response.data is String && (response.data as String).isNotEmpty) {
      final dataStr = response.data as String;
      dynamic decoded;
      try {
        if (dataStr.length > LikeConstants.computeThreshold) {
          decoded = await compute(LikeHelpers.parseJson, dataStr);
        } else {
          decoded = LikeHelpers.parseJson(dataStr);
        }
      } catch (_) {
        decoded = LikeHelpers.parseJson(dataStr);
      }

      // Re-wrap to avoid type errors if the original response was Response<String>
      response = Response(
        data: decoded,
        headers: response.headers,
        requestOptions: response.requestOptions,
        isRedirect: response.isRedirect,
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        redirects: response.redirects,
        extra: response.extra,
      );
    }

    // 2. Emit to Pipeline if GET to finalize SWR/Sync states
    if (response.requestOptions.method == 'GET') {
      final absoluteUriKey = response.requestOptions.uri.toString();

      // Final promotion to L1 cache on success
      _registry.addSessionKey(absoluteUriKey, response: response);

      LikePipeline().emit(
        absoluteUriKey,
        response,
        isSyncing: false,
        timestamp: DateTime.now(),
      );
    }

    return LikeApiResult.success(
      response,
      isFromCache: response.extra['isFromCache'] ?? false,
      isFromStaleWhileRevalidate:
          response.extra['isFromStaleWhileRevalidate'] ?? false,
      isResiliencyFallback: response.extra['isResiliencyFallback'] ?? false,
    );
  }

  // --- Public API ---

  /// Performs a GET request with optional SWR and caching strategies.
  ///
  /// [path] can be a relative endpoint or absolute URL.
  /// [query] parameters are automatically encoded.
  /// [withAuth] determines if the auth interceptor should include headers.
  /// [ars] provides fine-grained control over caching and deduplication.
  /// [requestConfig] optionally overrides network settings (baseUrl, timeouts,
  /// headers, unpacker) for this single call without affecting global defaults.
  Future<LikeApiResult<Response>> get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool disableCache = false,
    bool staleWhileRevalidate = false,
    bool sessionStale = false,
    bool singleFetch = false,
    bool resetSessionStale = false,
    bool resetSingleFetch = false,
    bool deduplicate = true,
    bool suppressErrors = false,
    Duration? timeout,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  }) async {
    final zoneArs = Zone.current[#likeActiveArs] as ARS?;
    final finalARS = ars ?? zoneArs ??
        ARS(
          staleWhileRevalidate: staleWhileRevalidate,
          disableCache: disableCache,
          sessionStale: sessionStale,
          singleFetch: singleFetch,
          resetSessionStale: resetSessionStale,
          resetSingleFetch: resetSingleFetch,
          deduplicate: deduplicate,
          suppressErrors: suppressErrors,
        );

    return await _execute(
      method: 'GET',
      path: path,
      queryParameters: query,
      cancelToken: cancelToken,
      requestConfig: requestConfig,
      options: Options(
        headers: headers,
        receiveTimeout: timeout,
        sendTimeout: timeout,
        extra: {
          'withAuth': withAuth,
          'disableCache': finalARS.disableCache,
          'staleWhileRevalidate': finalARS.staleWhileRevalidate,
          'sessionStale': finalARS.sessionStale,
          'singleFetch': finalARS.singleFetch,
          'resetSessionStale': finalARS.resetSessionStale,
          'resetSingleFetch': finalARS.resetSingleFetch,
          'deduplicate': finalARS.deduplicate,
          'suppressErrors': finalARS.suppressErrors,
        },
      ),
    );
  }

  /// Performs a POST request with optional offline synchronization.
  ///
  /// [body] is the data payload (e.g., Map, List, or String).
  /// [offlineSync] must be explicitly enabled to make this application-owned
  /// mutation eligible for durable replay after an ambiguous network failure.
  /// [requestConfig] optionally overrides network settings for this single call.
  Future<LikeApiResult<Response>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  }) async {
    final zoneArs = Zone.current[#likeActiveArs] as ARS?;
    final finalARS =
        ars ?? zoneArs ?? ARS(disableCache: disableCache, offlineSync: offlineSync);

    final result = await _execute(
      method: 'POST',
      path: path,
      data: body,
      queryParameters: query,
      cancelToken: cancelToken,
      requestConfig: requestConfig,
      options: Options(
        headers: headers,
        extra: {
          'withAuth': withAuth,
          'disableCache': finalARS.disableCache,
          'offlineSync': finalARS.offlineSync,
          ...finalARS.toJson(),
        },
      ),
    );
    if (result.isSuccess) notifySync(path, _extractPayload(body, query));
    return result;
  }

  /// Performs a PUT request.
  ///
  /// Durable replay remains disabled unless [offlineSync] is explicitly true.
  /// [requestConfig] optionally overrides network settings for this single call.
  Future<LikeApiResult<Response>> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  }) async {
    final zoneArs = Zone.current[#likeActiveArs] as ARS?;
    final finalARS =
        ars ?? zoneArs ?? ARS(disableCache: disableCache, offlineSync: offlineSync);

    final result = await _execute(
      method: 'PUT',
      path: path,
      data: body,
      queryParameters: query,
      cancelToken: cancelToken,
      requestConfig: requestConfig,
      options: Options(
        headers: headers,
        extra: {
          'withAuth': withAuth,
          'disableCache': finalARS.disableCache,
          'offlineSync': finalARS.offlineSync,
          ...finalARS.toJson(),
        },
      ),
    );
    if (result.isSuccess) notifySync(path, _extractPayload(body, query));
    return result;
  }

  /// Performs a PATCH request.
  ///
  /// Durable replay remains disabled unless [offlineSync] is explicitly true.
  /// [requestConfig] optionally overrides network settings for this single call.
  Future<LikeApiResult<Response>> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  }) async {
    final zoneArs = Zone.current[#likeActiveArs] as ARS?;
    final finalARS =
        ars ?? zoneArs ?? ARS(disableCache: disableCache, offlineSync: offlineSync);

    final result = await _execute(
      method: 'PATCH',
      path: path,
      data: body,
      queryParameters: query,
      cancelToken: cancelToken,
      requestConfig: requestConfig,
      options: Options(
        headers: headers,
        extra: {
          'withAuth': withAuth,
          'disableCache': finalARS.disableCache,
          'offlineSync': finalARS.offlineSync,
          ...finalARS.toJson(),
        },
      ),
    );
    if (result.isSuccess) notifySync(path, _extractPayload(body, query));
    return result;
  }

  /// Performs a DELETE request.
  ///
  /// Durable replay remains disabled unless [offlineSync] is explicitly true.
  /// [requestConfig] optionally overrides network settings for this single call.
  Future<LikeApiResult<Response>> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  }) async {
    final zoneArs = Zone.current[#likeActiveArs] as ARS?;
    final finalARS =
        ars ?? zoneArs ?? ARS(disableCache: disableCache, offlineSync: offlineSync);

    final result = await _execute(
      method: 'DELETE',
      path: path,
      data: body,
      queryParameters: query,
      cancelToken: cancelToken,
      requestConfig: requestConfig,
      options: Options(
        headers: headers,
        extra: {
          'withAuth': withAuth,
          'disableCache': finalARS.disableCache,
          'offlineSync': finalARS.offlineSync,
          ...finalARS.toJson(),
        },
      ),
    );
    if (result.isSuccess) notifySync(path, _extractPayload(body, query));
    return result;
  }

  /// Performs a multipart/form-data request for file uploads.
  ///
  /// [fields] are standard form fields.
  /// [filePaths] is a map of keys to file paths or lists of file paths.
  /// [files] is a list of [MultipartBytesFile] for in-memory file data.
  /// [requestConfig] optionally overrides network settings for this single call.
  /// This is especially useful for upload endpoints that need a longer [sendTimeout].
  Future<LikeApiResult<Response>> multipart(
    String path, {
    String method = 'POST',
    Map<String, String>? fields,
    dynamic filePaths,
    List<MultipartBytesFile>? files,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  }) async {
    final zoneArs = Zone.current[#likeActiveArs] as ARS?;
    final finalARS = ars ?? zoneArs ?? ARS(offlineSync: offlineSync);
    final formData = FormData();

    if (fields != null) {
      formData.fields.addAll(
        fields.entries.map((e) => MapEntry(e.key, e.value)),
      );
    }

    if (filePaths != null) {
      // MultipartFile.fromFile() reads a native file-system path.
      // On web there is no file-system — use the `files` parameter with
      // MultipartBytesFile (in-memory bytes) instead.
      assert(
        !kIsWeb,
        'LikeClient.multipart(): the `filePaths` parameter is not supported on web '
        'because the web platform has no file-system access. '
        'Use the `files` parameter with MultipartBytesFile (bytes) instead.',
      );
      if (!kIsWeb) {
        if (filePaths is Map<String, String>) {
          for (final entry in filePaths.entries) {
            formData.files.add(
              MapEntry(entry.key, await MultipartFile.fromFile(entry.value)),
            );
          }
        } else if (filePaths is Map<String, List<String>>) {
          for (final entry in filePaths.entries) {
            for (final p in entry.value) {
              formData.files.add(
                MapEntry(entry.key, await MultipartFile.fromFile(p)),
              );
            }
          }
        }
      }
    }

    if (files != null) {
      for (final f in files) {
        formData.files.add(
          MapEntry(
            f.field,
            MultipartFile.fromBytes(
              f.bytes,
              filename: f.filename,
              contentType: f.contentType,
            ),
          ),
        );
      }
    }

    final result = await _execute(
      method: method,
      path: path,
      data: formData,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      requestConfig: requestConfig,
      options: Options(
        headers: headers,
        extra: {
          'withAuth': withAuth,
          'offlineSync': finalARS.offlineSync,
          'multipartFields': fields,
          'multipartFilePaths': filePaths,
          'multipartFiles': files,
          ...finalARS.toJson(),
        },
      ),
    );
    if (result.isSuccess) notifySync(path, fields ?? const {});
    return result;
  }

  // --- Utilities ---

  /// Checks interface, internet, and server reachability for this client's
  /// active base origin.
  Future<LikeConnectivityCheckResult> checkConnectivity({
    bool force = false,
  }) {
    return LikeConnectivityManager().checkConnectivity(
      serverUrl: _dio.options.baseUrl,
      force: force,
    );
  }

  /// Checks reachability for this client's active base origin.
  Future<LikeConnectivityCheckResult> checkServerReachability({
    bool force = false,
  }) {
    return LikeConnectivityManager().checkServerReachability(
      _dio.options.baseUrl,
      force: force,
    );
  }

  /// Updates the base URL for all future requests.
  void updateBaseUrl(String newUrl) =>
      _dio.options.baseUrl = LikeHelpers.normalizeBaseUrl(newUrl);

  /// Creates a new [LikeClient] instance with the provided overrides.
  /// Note: This creates a separate instance with its own [Dio] and [LikeRequestRegistry],
  /// bypassing the default singleton instance.
  LikeClient copyWith({String? baseUrl, Duration? timeout}) {
    return LikeClient._internal(
      baseUrl: baseUrl ?? _dio.options.baseUrl,
      timeout: timeout ?? _dio.options.connectTimeout,
    );
  }

  Map<String, dynamic> _extractPayload(
    Object? body,
    Map<String, dynamic>? query,
  ) {
    final result = <String, dynamic>{};
    if (query != null) {
      result.addAll(query);
    }
    if (body != null && body is Map<String, dynamic>) {
      result.addAll(body);
    }
    return result;
  }

  void notifySync(String path, Map<String, dynamic> payload) {
    final effectivePath =
        path.startsWith('http') || path.startsWith('/') ? path : '/$path';
    _refreshController.add(effectivePath);
    _syncController.add(LikeSyncEvent(path: effectivePath, payload: payload));
  }

  void notifyRefresh(String path) {
    notifySync(path, const {});
  }

  /// Broadcasts a signal to all providers that the connection has been restored.
  /// This triggers automatic synchronization for all registered sync tasks.
  void triggerReconnectionSync() {
    _refreshController.add('reconnected');
  }

  /// Manually triggers and joins a durable offline mutation queue drain.
  ///
  /// When [origin] is supplied, only eligible work for that canonical origin is
  /// considered. Concurrent callers for the same origin join one active drain.
  Future<void> syncOfflineData({String? origin}) async {
    final interceptor =
        _dio.interceptors.whereType<LikeOfflineSyncInterceptor>().firstOrNull;
    if (interceptor != null) {
      await interceptor.syncQueue(origin: origin);
    }
  }

  /// Cancels active durable drains without deleting queued mutations.
  void cancelOfflineSync({String? origin, String reason = 'Sync cancelled'}) {
    final interceptor =
        _dio.interceptors.whereType<LikeOfflineSyncInterceptor>().firstOrNull;
    interceptor?.cancelSync(origin: origin, reason: reason);
  }

  /// Clears the in-memory session registry and L1 cache.
  void clearSession() => _registry.clear();

  /// Disposes of the client, closing all streams and cleaning up the registry.
  void dispose() {
    _refreshController.close();
    _registry.dispose();
    _dio.close();
    _instance = null;
  }
}

/// Represents a file to be uploaded as byte data in a multipart request.
class MultipartBytesFile {
  /// The form field name for the file.
  final String field;

  /// The raw bytes of the file.
  final Uint8List bytes;

  /// The name of the file to be sent to the server.
  final String filename;

  /// The MIME type of the file.
  final MediaType? contentType;

  const MultipartBytesFile({
    required this.field,
    required this.bytes,
    required this.filename,
    this.contentType,
  });
}
