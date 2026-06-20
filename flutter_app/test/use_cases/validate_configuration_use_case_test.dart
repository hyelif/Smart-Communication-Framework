import 'package:flutter_test/flutter_test.dart';
import 'package:smartponic_v2/use_cases/validate_configuration_use_case.dart';

void main() {
  late ValidateConfigurationUseCase useCase;

  setUp(() {
    useCase = ValidateConfigurationUseCase();
  });

  group('ValidateConfigurationUseCase', () {
    test('returns empty errors for valid config', () {
      final config = [
        {'pin': 35, 'sensor': 'pH', 'type': 'AI'},
        {'pin': 34, 'sensor': 'TDS', 'type': 'AI'},
        {'pin': 16, 'sensor': 'DHT22', 'type': 'DI'},
      ];

      final errors = useCase(config);
      expect(errors, isEmpty);
    });

    test('returns error for empty config', () {
      final errors = useCase([]);
      expect(errors, isNotEmpty);
      expect(errors.first.code, 'empty_config');
    });

    test('returns error for duplicate pins', () {
      final config = [
        {'pin': 35, 'sensor': 'pH', 'type': 'AI'},
        {'pin': 35, 'sensor': 'TDS', 'type': 'AI'},
      ];

      final errors = useCase(config);
      expect(errors.any((e) => e.code == 'duplicate_pin'), isTrue);
    });

    test('returns error for unsupported sensor', () {
      final config = [
        {'pin': 35, 'sensor': 'UnknownSensor', 'type': 'AI'},
      ];

      final errors = useCase(config);
      expect(errors.any((e) => e.code == 'unsupported_sensor'), isTrue);
    });

    test('returns error for wrong pin type', () {
      final config = [
        {'pin': 25, 'sensor': 'pH', 'type': 'AI'}, // GPIO 25 is DO, not AI
      ];

      final errors = useCase(config);
      expect(errors.any((e) => e.code == 'pin_type_mismatch'), isTrue);
    });

    test('normalize canonicalizes sensor names', () {
      final config = [
        {'pin': 35, 'sensor': 'Ph', 'type': 'AI'},
        {'pin': 34, 'sensor': 'tds', 'type': 'AI'},
      ];

      final normalized = useCase.normalize(config);
      expect(normalized[0]['sensor'], 'pH');
      expect(normalized[1]['sensor'], 'TDS');
    });

    test('sameConfig returns true for identical configs', () {
      final a = [
        {'pin': 35, 'sensor': 'pH', 'type': 'AI'},
      ];
      final b = [
        {'pin': 35, 'sensor': 'pH', 'type': 'AI'},
      ];

      expect(useCase.sameConfig(a, b), isTrue);
    });

    test('sameConfig returns false for different configs', () {
      final a = [
        {'pin': 35, 'sensor': 'pH', 'type': 'AI'},
      ];
      final b = [
        {'pin': 34, 'sensor': 'TDS', 'type': 'AI'},
      ];

      expect(useCase.sameConfig(a, b), isFalse);
    });
  });
}
