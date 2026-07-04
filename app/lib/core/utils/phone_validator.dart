class PhoneValidationResult {

  const PhoneValidationResult({
    required this.isValid,
    this.formattedNumber,
    this.errorMessage,
  });
  final bool isValid;
  final String? formattedNumber;
  final String? errorMessage;
}

class PhoneValidator {
  /// Validates and cleans a phone number input string.
  /// Prepends '+' if it is not present, cleans spaces/hyphens/parentheses,
  /// validates that it only contains digits after '+', does not start with 0,
  /// and is between 7 and 15 digits in length (standard E.164 phone numbers).
  static PhoneValidationResult validate(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const PhoneValidationResult(
        isValid: false,
        errorMessage: 'Phone number cannot be empty.',
      );
    }

    // Clean formatting characters: spaces, hyphens, parentheses
    String cleaned = trimmed.replaceAll(RegExp(r'[\s\-()]+'), '');

    // Ensure it starts with '+'
    if (!cleaned.startsWith('+')) {
      cleaned = '+$cleaned';
    }

    // Extract digits after the '+'
    final digits = cleaned.substring(1);
    if (digits.isEmpty) {
      return const PhoneValidationResult(
        isValid: false,
        errorMessage: 'Phone number must contain digits.',
      );
    }

    // Check if the remaining characters are numeric only
    if (!RegExp(r'^\d+$').hasMatch(digits)) {
      return const PhoneValidationResult(
        isValid: false,
        errorMessage: 'Phone number must contain only digits.',
      );
    }

    // E.164 country codes cannot start with 0
    if (digits.startsWith('0')) {
      return const PhoneValidationResult(
        isValid: false,
        errorMessage: 'Invalid country code. Country codes cannot start with 0.',
      );
    }

    // E.164 numbers are minimum 7 and maximum 15 digits including country code
    if (digits.length < 7) {
      return const PhoneValidationResult(
        isValid: false,
        errorMessage: 'Phone number is too short (minimum 7 digits including country code).',
      );
    }

    if (digits.length > 15) {
      return const PhoneValidationResult(
        isValid: false,
        errorMessage: 'Phone number is too long (maximum 15 digits including country code).',
      );
    }

    return PhoneValidationResult(
      isValid: true,
      formattedNumber: cleaned,
    );
  }
}
