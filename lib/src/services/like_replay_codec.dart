import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

abstract interface class LikeReplayCodec {
  Future<Map<String, dynamic>> encode(Object? body);
  Object? decode(Map body);
}

/// Snapshots multipart bytes so replay does not depend on a temporary file path.
class DefaultLikeReplayCodec implements LikeReplayCodec {
  final int maximumBytes;
  const DefaultLikeReplayCodec({this.maximumBytes = 10 * 1024 * 1024});

  @override
  Future<Map<String, dynamic>> encode(Object? body) async {
    if (body is FormData) {
      var total = 0;
      final files = <Map<String, dynamic>>[];
      for (final part in body.files) {
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in part.value.clone().finalize()) {
          total += chunk.length;
          if (total > maximumBytes) throw StateError('Offline upload exceeds byte limit');
          bytes.add(chunk);
        }
        files.add({'field': part.key, 'filename': part.value.filename,
          'contentType': part.value.contentType?.toString(), 'bytes': bytes.takeBytes()});
      }
      return {'format': 1, 'kind': 'multipart',
        'fields': body.fields.map((e) => [e.key, e.value]).toList(), 'files': files};
    }
    return {'format': 1, 'kind': 'value', 'value': _value(body)};
  }

  Object? _value(Object? value) {
    if (value == null || value is String || value is num || value is bool || value is Uint8List) return value;
    if (value is List) return value.map(_value).toList();
    if (value is Map && value.keys.every((key) => key is String)) {
      return value.map((key, item) => MapEntry(key as String, _value(item)));
    }
    throw ArgumentError('Offline bodies must be serializable values or FormData');
  }

  @override
  Object? decode(Map body) {
    if (body['format'] != 1) throw StateError('Unsupported offline body format');
    if (body['kind'] == 'value') return _value(body['value']);
    if (body['kind'] != 'multipart') throw StateError('Unsupported offline body kind');
    final form = FormData();
    for (final field in body['fields'] as List) {
      form.fields.add(MapEntry(field[0] as String, field[1] as String));
    }
    for (final file in body['files'] as List) {
      form.files.add(MapEntry(file['field'] as String,
        MultipartFile.fromBytes(List<int>.from(file['bytes'] as List),
          filename: file['filename'] as String?,
          contentType: file['contentType'] == null ? null : MediaType.parse(file['contentType'] as String))));
    }
    return form;
  }
}
