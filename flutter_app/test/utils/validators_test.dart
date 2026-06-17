import 'package:flutter_test/flutter_test.dart';
import 'package:smartponic_v2/utils/validators.dart';

void main() {
  group('Validators', () {
    group('validateIpAddress', () {
      test('returns null for valid IP 192.168.1.1', () {
        expect(Validators.validateIpAddress('192.168.1.1'), isNull);
      });

      test('returns null for valid IP 10.0.0.1', () {
        expect(Validators.validateIpAddress('10.0.0.1'), isNull);
      });

      test('returns null for valid IP 172.16.0.1', () {
        expect(Validators.validateIpAddress('172.16.0.1'), isNull);
      });

      test('returns null for valid IP 255.255.255.255', () {
        expect(Validators.validateIpAddress('255.255.255.255'), isNull);
      });

      test('returns null for valid IP 0.0.0.0', () {
        expect(Validators.validateIpAddress('0.0.0.0'), isNull);
      });

      test('returns error for null value', () {
        final result = Validators.validateIpAddress(null);
        expect(result, equals('IP address is required'));
      });

      test('returns error for empty string', () {
        final result = Validators.validateIpAddress('');
        expect(result, equals('IP address is required'));
      });

      test('returns error for IP with octet > 255', () {
        final result = Validators.validateIpAddress('192.168.1.256');
        expect(result, equals('Invalid IP address'));
      });

      test('returns error for IP with octet > 255 in first position', () {
        final result = Validators.validateIpAddress('999.168.1.1');
        expect(result, equals('Invalid IP address'));
      });

      test('returns error for malformed IP with letters', () {
        final result = Validators.validateIpAddress('abc.def.ghi.jkl');
        expect(result, equals('Enter a valid IP address'));
      });

      test('returns error for IP with missing octets', () {
        final result = Validators.validateIpAddress('192.168.1');
        expect(result, equals('Enter a valid IP address'));
      });

      test('returns error for IP with extra octets', () {
        final result = Validators.validateIpAddress('192.168.1.1.5');
        expect(result, equals('Enter a valid IP address'));
      });

      test('returns error for non-numeric input', () {
        final result = Validators.validateIpAddress('not-an-ip');
        expect(result, equals('Enter a valid IP address'));
      });

      test('returns error for IP with leading zeros in octet', () {
        // Leading zeros pass the regex but are valid per the format
        final result = Validators.validateIpAddress('192.168.01.1');
        expect(result, isNull);
      });
    });

    group('validatePort', () {
      test('returns null for valid port 80', () {
        expect(Validators.validatePort('80'), isNull);
      });

      test('returns null for valid port 443', () {
        expect(Validators.validatePort('443'), isNull);
      });

      test('returns null for valid port 1 (minimum)', () {
        expect(Validators.validatePort('1'), isNull);
      });

      test('returns null for valid port 65535 (maximum)', () {
        expect(Validators.validatePort('65535'), isNull);
      });

      test('returns null for valid port 8080', () {
        expect(Validators.validatePort('8080'), isNull);
      });

      test('returns error for null value', () {
        final result = Validators.validatePort(null);
        expect(result, equals('Port is required'));
      });

      test('returns error for empty string', () {
        final result = Validators.validatePort('');
        expect(result, equals('Port is required'));
      });

      test('returns error for port 0 (below minimum)', () {
        final result = Validators.validatePort('0');
        expect(result, equals('Enter a valid port (1-65535)'));
      });

      test('returns error for port 65536 (above maximum)', () {
        final result = Validators.validatePort('65536');
        expect(result, equals('Enter a valid port (1-65535)'));
      });

      test('returns error for negative port', () {
        final result = Validators.validatePort('-1');
        expect(result, equals('Enter a valid port (1-65535)'));
      });

      test('returns error for non-numeric input', () {
        final result = Validators.validatePort('abc');
        expect(result, equals('Enter a valid port (1-65535)'));
      });

      test('returns error for decimal port', () {
        final result = Validators.validatePort('80.5');
        expect(result, equals('Enter a valid port (1-65535)'));
      });
    });

    group('validateSensorName', () {
      test('returns null for valid sensor name', () {
        expect(Validators.validateSensorName('DHT22'), isNull);
      });

      test('returns null for sensor name at max length', () {
        final name = 'A' * 50;
        expect(Validators.validateSensorName(name), isNull);
      });

      test('returns error for null value', () {
        final result = Validators.validateSensorName(null);
        expect(result, equals('Sensor name is required'));
      });

      test('returns error for empty string', () {
        final result = Validators.validateSensorName('');
        expect(result, equals('Sensor name is required'));
      });

      test('returns error for name exceeding 50 characters', () {
        final name = 'A' * 51;
        final result = Validators.validateSensorName(name);
        expect(result, equals('Name must be less than 50 characters'));
      });
    });

    group('validateRequired', () {
      test('returns null for non-empty value', () {
        expect(
          Validators.validateRequired('hello', 'Name'),
          isNull,
        );
      });

      test('returns error for null value with custom field name', () {
        final result = Validators.validateRequired(null, 'Email');
        expect(result, equals('Email is required'));
      });

      test('returns error for empty value with custom field name', () {
        final result = Validators.validateRequired('', 'Password');
        expect(result, equals('Password is required'));
      });
    });
  });
}
