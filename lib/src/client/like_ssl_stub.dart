import 'package:dio/dio.dart';

/// Web stub for SSL configuration.
///
/// On web the browser enforces TLS/SSL natively — no Dio adapter
/// configuration is needed or possible. This stub satisfies the import
/// so the package compiles on web without referencing `dart:io`.
void setupSSL(
  Dio dio, {
  required bool verifySSL,
  required String sslCertSha256,
}) {
  // No-op on web. Browser handles all TLS.
}
