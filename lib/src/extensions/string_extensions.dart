/// Null-safe String extension utilities available on both `String` and `String?`.
extension LikeStringExtension on String? {
  /// Whether the string is null, empty, or whitespace only.
  bool get isNullOrEmpty {
    return this == null || this!.trim().isEmpty;
  }

  /// Whether the string is non-null and not empty/whitespace.
  bool get isNotNullOrEmpty => !isNullOrEmpty;

  /// Capitalizes the first letter of the string safely. Returns empty string `""` if null/empty.
  ///
  /// Example: `"hello".capitalize` -> `"Hello"`, `null.capitalize` -> `""`
  String get capitalize {
    if (isNullOrEmpty) return '';
    final str = this!.trim();
    if (str.isEmpty) return '';
    return '${str[0].toUpperCase()}${str.substring(1)}';
  }

  /// Capitalizes the first letter of each word in the string safely.
  ///
  /// Example: `"hello world".titleCase` -> `"Hello World"`
  String get titleCase {
    if (isNullOrEmpty) return '';
    return this!.trim().split(' ').map((word) => word.capitalize).join(' ');
  }

  /// Whether the string is a valid email address.
  bool get isEmail {
    if (isNullOrEmpty) return false;
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(this!.trim());
  }

  /// Whether the string is a valid URL.
  bool get isUrl {
    if (isNullOrEmpty) return false;
    final uri = Uri.tryParse(this!.trim());
    return uri != null && uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Returns the capitalized string or [fallback] if null/empty.
  String capitalizeOr(String fallback) {
    if (isNullOrEmpty) return fallback;
    return capitalize;
  }
}
