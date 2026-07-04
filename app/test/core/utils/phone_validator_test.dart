import 'package:aerodrive/core/utils/phone_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneValidator Tests', () {
    test('Empty input is invalid', () {
      final result = PhoneValidator.validate('');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('cannot be empty'));
    });

    test('Spaces and common formatting characters are cleaned', () {
      final result = PhoneValidator.validate('+1 (234) 567-8900');
      expect(result.isValid, isTrue);
      expect(result.formattedNumber, '+12345678900');
    });

    test('Leading plus sign is added if missing', () {
      final result = PhoneValidator.validate('12345678900');
      expect(result.isValid, isTrue);
      expect(result.formattedNumber, '+12345678900');
    });

    test('Non-digit characters after plus are invalid', () {
      final result = PhoneValidator.validate('+123456a7890');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('only digits'));
    });

    test('Country code starting with 0 is invalid', () {
      final result = PhoneValidator.validate('+0123456789');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('Country codes cannot start with 0'));
    });

    test('Too short phone number is invalid', () {
      final result = PhoneValidator.validate('+12345');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('too short'));
    });

    test('Too long phone number is invalid', () {
      final result = PhoneValidator.validate('+1234567890123456');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('too long'));
    });

    test('Valid standard E.164 phone numbers', () {
      expect(PhoneValidator.validate('+1234567890').isValid, isTrue);
      expect(PhoneValidator.validate('+447911123456').isValid, isTrue);
      expect(PhoneValidator.validate('+2348031234567').isValid, isTrue);
    });
  });
}
