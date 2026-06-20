import 'package:flutter_test/flutter_test.dart';
import 'package:smartponic_v2/models/deploy_result.dart';

void main() {
  group('DeployResult', () {
    test('ok factory creates successful result', () {
      final result = DeployResult.ok(message: 'Success', statusCode: 200);
      expect(result.success, isTrue);
      expect(result.message, 'Success');
      expect(result.statusCode, 200);
    });

    test('fail factory creates failed result', () {
      final result = DeployResult.fail(message: 'Error', statusCode: 500);
      expect(result.success, isFalse);
      expect(result.message, 'Error');
      expect(result.statusCode, 500);
    });

    test('ok factory defaults', () {
      final result = DeployResult.ok();
      expect(result.success, isTrue);
      expect(result.message, isNull);
      expect(result.statusCode, isNull);
    });

    test('fail factory defaults', () {
      final result = DeployResult.fail();
      expect(result.success, isFalse);
      expect(result.message, isNull);
      expect(result.statusCode, isNull);
    });
  });
}
