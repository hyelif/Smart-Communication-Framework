import 'package:flutter_test/flutter_test.dart';
import 'package:smartponic_v2/utils/formatters.dart';

void main() {
  group('Formatters', () {
    group('formatTemperature', () {
      test('formats temperature in Celsius (default)', () {
        expect(Formatters.formatTemperature(25.5), equals('25.5°C'));
      });

      test('formats temperature in Fahrenheit', () {
        expect(
          Formatters.formatTemperature(77.0, unit: 'F'),
          equals('77.0°F'),
        );
      });

      test('formats temperature with one decimal place', () {
        expect(Formatters.formatTemperature(25.555), equals('25.6°C'));
      });

      test('formats zero temperature', () {
        expect(Formatters.formatTemperature(0.0), equals('0.0°C'));
      });

      test('formats negative temperature', () {
        expect(Formatters.formatTemperature(-5.3), equals('-5.3°C'));
      });

      test('formats temperature with integer value', () {
        expect(Formatters.formatTemperature(30.0), equals('30.0°C'));
      });
    });

    group('formatPercentage', () {
      test('formats percentage with one decimal', () {
        expect(Formatters.formatPercentage(75.5), equals('75.5%'));
      });

      test('formats percentage rounding', () {
        expect(Formatters.formatPercentage(75.55), equals('75.6%'));
      });

      test('formats zero percent', () {
        expect(Formatters.formatPercentage(0.0), equals('0.0%'));
      });

      test('formats hundred percent', () {
        expect(Formatters.formatPercentage(100.0), equals('100.0%'));
      });
    });

    group('formatPh', () {
      test('formats pH with one decimal', () {
        expect(Formatters.formatPh(7.0), equals('pH 7.0'));
      });

      test('formats acidic pH', () => expect(Formatters.formatPh(4.5), equals('pH 4.5')));

      test('formats alkaline pH', () {
        expect(Formatters.formatPh(9.2), equals('pH 9.2'));
      });

      test('formats pH rounding', () {
        expect(Formatters.formatPh(6.55), equals('pH 6.6'));
      });
    });

    group('formatSensorValue', () {
      test('formats sensor value with two decimals and unit', () {
        expect(
          Formatters.formatSensorValue(123.456, 'ppm'),
          equals('123.46 ppm'),
        );
      });

      test('formats sensor value with different unit', () {
        expect(
          Formatters.formatSensorValue(50.0, 'lux'),
          equals('50.00 lux'),
        );
      });

      test('formats zero sensor value', () {
        expect(
          Formatters.formatSensorValue(0.0, 'mV'),
          equals('0.00 mV'),
        );
      });

      test('formats negative sensor value', () {
        expect(
          Formatters.formatSensorValue(-10.5, '°C'),
          equals('-10.50 °C'),
        );
      });
    });

    group('formatDateTime', () {
      test('formats DateTime to MMM dd, yyyy HH:mm', () {
        final dt = DateTime(2026, 6, 17, 14, 30, 45);
        final formatted = Formatters.formatDateTime(dt);
        expect(formatted, equals('Jun 17, 2026 14:30'));
      });

      test('formats DateTime with single-digit day', () {
        final dt = DateTime(2026, 1, 5, 9, 5);
        final formatted = Formatters.formatDateTime(dt);
        expect(formatted, equals('Jan 05, 2026 09:05'));
      });
    });

    group('formatDate', () {
      test('formats DateTime to MMM dd, yyyy', () {
        final dt = DateTime(2026, 6, 17);
        final formatted = Formatters.formatDate(dt);
        expect(formatted, equals('Jun 17, 2026'));
      });

      test('formats date with single-digit day', () {
        final dt = DateTime(2026, 3, 3);
        final formatted = Formatters.formatDate(dt);
        expect(formatted, equals('Mar 03, 2026'));
      });
    });

    group('formatTime', () {
      test('formats DateTime to HH:mm', () {
        final dt = DateTime(2026, 6, 17, 14, 30);
        final formatted = Formatters.formatTime(dt);
        expect(formatted, equals('14:30'));
      });

      test('formats time with single-digit hour and minute', () {
        final dt = DateTime(2026, 6, 17, 9, 5);
        final formatted = Formatters.formatTime(dt);
        expect(formatted, equals('09:05'));
      });

      test('formats midnight', () {
        final dt = DateTime(2026, 6, 17, 0, 0);
        final formatted = Formatters.formatTime(dt);
        expect(formatted, equals('00:00'));
      });
    });
  });
}
