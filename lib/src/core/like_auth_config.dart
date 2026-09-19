import 'dart:async';

/// Configuration for authentication token providers, refresh handlers, and logout callbacks.
///
/// Can be supplied globally via [LikeConfig.authConfig], per-client via
/// [LikeClientConfig.authConfig] or [LikeClient(authConfig: ...)], or via
/// legacy static callbacks on [LikeAuthInterceptor].
class LikeAuthConfig {
  /// Asynchronously fetches the current access token for outgoing requests.
  final FutureOr<String?> Function()? getToken;

  /// Refreshes an expired access token when HTTP 401 Unauthorized is encountered.
  ///
  /// Returns the new access token, or `null` if refresh failed.
  final FutureOr<String?> Function()? refreshToken;

  /// Callback executed when authentication fails fatally or explicit logout is required.
  final FutureOr<void> Function({int? statusCode, bool force})? onLogout;

  /// Asynchronously fetches an API key for endpoints requiring `x-api-key`.
  final FutureOr<String?> Function()? getApiKey;

  const LikeAuthConfig({
    this.getToken,
    this.refreshToken,
    this.onLogout,
    this.getApiKey,
  });

  bool get hasTokenSupplier => getToken != null;

  bool get hasRefreshSupplier => refreshToken != null;

  bool get hasLogoutSupplier => onLogout != null;

  bool get hasApiKeySupplier => getApiKey != null;

  LikeAuthConfig copyWith({
    FutureOr<String?> Function()? getToken,
    FutureOr<String?> Function()? refreshToken,
    FutureOr<void> Function({int? statusCode, bool force})? onLogout,
    FutureOr<String?> Function()? getApiKey,
  }) {
    return LikeAuthConfig(
      getToken: getToken ?? this.getToken,
      refreshToken: refreshToken ?? this.refreshToken,
      onLogout: onLogout ?? this.onLogout,
      getApiKey: getApiKey ?? this.getApiKey,
    );
  }

  @override
  String toString() {
    return 'LikeAuthConfig('
        'hasTokenSupplier: $hasTokenSupplier, '
        'hasRefreshSupplier: $hasRefreshSupplier, '
        'hasLogoutSupplier: $hasLogoutSupplier, '
        'hasApiKeySupplier: $hasApiKeySupplier'
        ')';
  }
}
