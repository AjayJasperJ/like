import '../constants/app_constants.dart';

abstract final class Validators {
  static String? requiredText(String? value, {String label = 'Value'}) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    final valid = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(text);
    return valid ? null : 'Enter a valid email address';
  }

  static String? password(String? value) {
    if ((value ?? '').length < AppConstants.minimumPasswordLength) {
      return 'Use at least ${AppConstants.minimumPasswordLength} characters';
    }
    return null;
  }

  static String? positiveInteger(String? value, {String label = 'Value'}) {
    final number = int.tryParse(value?.trim() ?? '');
    return number != null && number > 0
        ? null
        : '$label must be a positive integer';
  }
}
