import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

/// Native (mobile/desktop) implementation of SSL configuration.
///
/// Uses [IOHttpClientAdapter] to configure SSL pinning and certificate
/// validation on the underlying [HttpClient].
void setupSSL(
  Dio dio, {
  required bool verifySSL,
  required String sslCertSha256,
}) {
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) {
      // 1. Resolve request-scoped overrides from Zone, falling back to client-level defaults
      final bool effectiveVerifySSL =
          Zone.current[#verifySSL] as bool? ?? verifySSL;
      final String effectiveSha =
          Zone.current[#sslCertSha256] as String? ?? sslCertSha256;

      if (!effectiveVerifySSL) {
        return true; // SSL verification explicitly disabled
      }

      // No pin provided: allow in debug, block in release
      if (effectiveSha.isEmpty) return kDebugMode;

      final certSha256 = sha256
          .convert(cert.der)
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(':')
          .toLowerCase();

      return certSha256 == effectiveSha.toLowerCase();
    };
    return client;
  };
}
