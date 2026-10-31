/// Explicit testing surface for exercising the real LIKE networking stack.
/// Import this entrypoint in tests instead of private src paths. Construct a
/// scoped client, replace its Dio HttpClientAdapter, and dispose it per test.
library;

export 'like.dart';
export 'src/client/like_client_factory.dart';
export 'src/client/like_request_registry.dart';
export 'src/interceptors/like_cache_interceptor.dart';
export 'src/interceptors/like_connectivity_interceptor.dart';
export 'src/interceptors/like_etag_interceptor.dart';
export 'src/interceptors/like_offline_sync_interceptor.dart';
export 'src/interceptors/like_pipeline_interceptor.dart';
export 'src/interceptors/like_retry_interceptor.dart';
export 'src/services/like_connectivity_manager.dart';
export 'src/services/like_pipeline.dart';
export 'src/services/like_sync_manager.dart';
