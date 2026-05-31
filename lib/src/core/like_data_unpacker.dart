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

    // If the "data" key explicitly exists (even if its value is null), retrieve it.
    // Otherwise, treat the entire JSON envelope as the data block.
    final data = json.containsKey('data') ? json['data'] : json;
    final message = json['message']?.toString() ?? '';

    // Check success status robustly
    bool isSuccess = true;
    if (json.containsKey('success')) {
      final successVal = json['success'];
      if (successVal is bool) {
        isSuccess = successVal;
      } else if (successVal != null) {
        final lower = successVal.toString().toLowerCase();
        isSuccess = lower == 'true' || lower == 'success' || lower == 'ok';
      }
    } else if (json.containsKey('status')) {
      final statusVal = json['status'];
      if (statusVal != null) {
        final lower = statusVal.toString().toLowerCase();
        isSuccess = lower == 'success' || lower == 'ok' || lower == 'true';
      }
    }

    return LikeUnpackedResponse(
      data: data,
      message: message,
      isSuccess: isSuccess,
      errors: json['errors'] is Map<String, dynamic> ? json['errors'] : null,
    );
  }
}
