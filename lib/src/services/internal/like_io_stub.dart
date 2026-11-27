import 'dart:async';
import 'dart:typed_data';

/// Web/non-IO stub matching the `dart:io` symbols referenced by LIKE.
///
/// On `dart:io` platforms, conditional imports resolve directly to `dart:io`.
class SocketException implements Exception {
  final String message;
  const SocketException([this.message = '']);
}

class HandshakeException implements Exception {
  final String message;
  const HandshakeException([this.message = '']);
}

class HttpException implements Exception {
  final String message;
  const HttpException([this.message = '']);
}

class OSError implements Exception {
  final String message;
  final int errorCode;
  const OSError([this.message = '', this.errorCode = 0]);
}

class InternetAddress {
  final String address;
  const InternetAddress(this.address);

  List<int> get rawAddress => const <int>[];

  static Future<List<InternetAddress>> lookup(String host) async =>
      const <InternetAddress>[];
}

class HttpClientResponse {
  int get statusCode => 503;
}

class HttpClientRequest {
  bool followRedirects = true;
  Future<HttpClientResponse> close() async => HttpClientResponse();
}

class HttpClient {
  Duration? connectionTimeout;

  Future<HttpClientRequest> openUrl(String method, Uri url) {
    throw UnsupportedError('HttpClient is not supported on Web.');
  }

  void close({bool force = false}) {}
}

class Socket {
  static Future<Socket> connect(
    dynamic host,
    int port, {
    Duration? timeout,
  }) {
    throw UnsupportedError('Socket.connect is not supported on Web.');
  }

  void destroy() {}
}

class FileMode {
  static const write = FileMode._(0);
  static const append = FileMode._(1);
  final int _value;
  const FileMode._(this._value);
  @override
  int get hashCode => _value;
  @override
  bool operator ==(Object other) => other is FileMode && other._value == _value;
}

class FileSystemEntity {
  final String path;
  const FileSystemEntity(this.path);
}

class File extends FileSystemEntity {
  const File(super.path);

  Future<bool> exists() async => false;
  Future<File> create({bool recursive = false}) async => this;
  Future<void> setLastModified(DateTime time) async {}
  Future<int> length() async => 0;
  int lengthSync() => 0;
  DateTime lastModifiedSync() => DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> delete() async {}
  Future<List<String>> readAsLines() async => const <String>[];
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async =>
      this;
}

class Directory extends FileSystemEntity {
  const Directory(super.path);

  Future<bool> exists() async => false;
  Stream<FileSystemEntity> list({bool recursive = false}) =>
      const Stream<FileSystemEntity>.empty();
}

class WebSocket {
  static const int connecting = 0;
  static const int open = 1;
  static const int closing = 2;
  static const int closed = 3;

  int get readyState => closed;

  static Future<WebSocket> connect(String url) {
    throw UnsupportedError('dart:io WebSocket is not supported on Web.');
  }

  void add(dynamic data) {}

  Future<void> close([int? code, String? reason]) async {}

  StreamSubscription<dynamic> listen(
    void Function(dynamic event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      const Stream<dynamic>.empty().listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}
