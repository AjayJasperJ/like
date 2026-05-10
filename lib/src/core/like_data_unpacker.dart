/// Defines how raw API responses (envelopes) are parsed and mapped.
abstract class LikeDataUnpacker {
  const LikeDataUnpacker();

  /// Unpacks a raw JSON response into a standardized format.
  LikeUnpackedResponse unpack(dynamic json);
}

/// A standardized container for unpacked API data.
class LikeUnpackedResponse {
  final dynamic data;
  final String message;
  final bool isSuccess;
  final Map<String, dynamic>? errors;

  LikeUnpackedResponse({
    required this.data,
    this.message = '',
    this.isSuccess = true,
    this.errors,
  });
}

/// The default unpacker, assuming a "flat" structure or a common "data" wrapper.
class DefaultLikeUnpacker extends LikeDataUnpacker {
  const DefaultLikeUnpacker();

  @override
  LikeUnpackedResponse unpack(dynamic json) {
    if (json is! Map<String, dynamic>) {
      return LikeUnpackedResponse(data: json);
    }

    // Common patterns: data: {...} or status: "success"
    final data = json['data'] ?? json;
    final message = json['message']?.toString() ?? '';
    final status = json['status']?.toString().toLowerCase();

    return LikeUnpackedResponse(
      data: data,
      message: message,
      isSuccess:
          status == 'success' ||
          status == 'true' ||
          json['success'] == true ||
          status == null,
      errors: json['errors'] is Map<String, dynamic> ? json['errors'] : null,
    );
  }
}
