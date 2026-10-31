import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';

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
