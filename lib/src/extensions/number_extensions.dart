/// Null-safe Number extension utilities available on both `num` and `num?`.
extension LikeNumExtension on num? {
  /// Returns 0 if null, otherwise the number itself.
  num get orZero => this ?? 0;

  /// Returns 0 if null, otherwise the integer value.
  int get intOrZero => this?.toInt() ?? 0;

  /// Returns 0.0 if null, otherwise the double value.
  double get doubleOrZero => this?.toDouble() ?? 0.0;

  /// Formats the number as a string, dropping `.0` if it is an integer.
  ///
  /// Examples:
  /// - `5.0.clean` -> `"5"`
  /// - `5.5.clean` -> `"5.5"`
  /// - `null.clean` -> `"0"`
  String get clean {
    if (this == null) return '0';
    final n = this!;
    if (n == n.toInt()) {
      return n.toInt().toString();
    }
    return n.toString();
  }

  /// Pads integer representation with leading zeroes to reach [width].
  String padLeft(int width) => intOrZero.toString().padLeft(width, '0');

  /// Formats currency with currency symbol.
  String toCurrency({String symbol = '\$'}) => '$symbol${doubleOrZero.toStringAsFixed(2)}';
}
