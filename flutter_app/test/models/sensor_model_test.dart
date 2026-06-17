import 'package:flutter_test/flutter_test.dart';
import 'package:smartponic_v2/models/sensor_model.dart';

void main() {
  group('SensorModel', () {
    group('fromMap', () {
      test('creates SensorModel with all fields', () {
        final map = <String, dynamic>{
          'pin': 34,
          'sensor': 'DHT22',
          'type': 'temperature',
          'label': 'Air Temp',
        };
        final model = SensorModel.fromMap(map);
        expect(model.pin, equals(34));
        expect(model.sensor, equals('DHT22'));
        expect(model.type, equals('temperature'));
        expect(model.label, equals('Air Temp'));
      });

      test('creates SensorModel with null label', () {
        final map = <String, dynamic>{
          'pin': 32,
          'sensor': 'DS18B20',
          'type': 'temperature',
          'label': null,
        };
        final model = SensorModel.fromMap(map);
        expect(model.pin, equals(32));
        expect(model.sensor, equals('DS18B20'));
        expect(model.type, equals('temperature'));
        expect(model.label, isNull);
      });

      test('creates SensorModel with missing label', () {
        final map = <String, dynamic>{
          'pin': 35,
          'sensor': 'PH4502C',
          'type': 'ph',
        };
        final model = SensorModel.fromMap(map);
        expect(model.pin, equals(35));
        expect(model.sensor, equals('PH4502C'));
        expect(model.type, equals('ph'));
        expect(model.label, isNull);
      });

      test('creates SensorModel with empty string label', () {
        final map = <String, dynamic>{
          'pin': 33,
          'sensor': 'FC28',
          'type': 'moisture',
          'label': '',
        };
        final model = SensorModel.fromMap(map);
        expect(model.pin, equals(33));
        expect(model.sensor, equals('FC28'));
        expect(model.type, equals('moisture'));
        expect(model.label, equals(''));
      });
    });

    group('toMap', () {
      test('converts to map with all fields including label', () {
        final model = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
          label: 'Air Temp',
        );
        final map = model.toMap();
        expect(map['pin'], equals(34));
        expect(map['sensor'], equals('DHT22'));
        expect(map['type'], equals('temperature'));
        expect(map['label'], equals('Air Temp'));
      });

      test('converts to map without label when label is null', () {
        final model = SensorModel(
          pin: 32,
          sensor: 'DS18B20',
          type: 'temperature',
        );
        final map = model.toMap();
        expect(map['pin'], equals(32));
        expect(map['sensor'], equals('DS18B20'));
        expect(map['type'], equals('temperature'));
        expect(map.containsKey('label'), isFalse);
      });

      test('converts to map without label when label is empty string', () {
        final model = SensorModel(
          pin: 33,
          sensor: 'FC28',
          type: 'moisture',
          label: '',
        );
        final map = model.toMap();
        expect(map['pin'], equals(33));
        expect(map['sensor'], equals('FC28'));
        expect(map['type'], equals('moisture'));
        expect(map.containsKey('label'), isFalse);
      });

      test('converts to map without label when label is whitespace only', () {
        final model = SensorModel(
          pin: 33,
          sensor: 'FC28',
          type: 'moisture',
          label: '   ',
        );
        final map = model.toMap();
        expect(map.containsKey('label'), isFalse);
      });
    });

    group('fromMap / toMap round-trip', () {
      test('round-trip preserves all fields with label', () {
        final original = <String, dynamic>{
          'pin': 34,
          'sensor': 'DHT22',
          'type': 'temperature',
          'label': 'Air Temp',
        };
        final model = SensorModel.fromMap(original);
        final result = model.toMap();
        expect(result['pin'], equals(original['pin']));
        expect(result['sensor'], equals(original['sensor']));
        expect(result['type'], equals(original['type']));
        expect(result['label'], equals(original['label']));
      });

      test('round-trip preserves fields without label', () {
        final original = <String, dynamic>{
          'pin': 32,
          'sensor': 'DS18B20',
          'type': 'temperature',
        };
        final model = SensorModel.fromMap(original);
        final result = model.toMap();
        expect(result['pin'], equals(original['pin']));
        expect(result['sensor'], equals(original['sensor']));
        expect(result['type'], equals(original['type']));
        expect(result.containsKey('label'), isFalse);
      });
    });

    group('equality and hashCode', () {
      test('two identical models are equal', () {
        final a = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
          label: 'Air Temp',
        );
        final b = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
          label: 'Air Temp',
        );
        expect(a, equals(b));
        expect(a.hashCode, equals(b.hashCode));
      });

      test('models with different pins are not equal', () {
        final a = SensorModel(pin: 34, sensor: 'DHT22', type: 'temperature');
        final b = SensorModel(pin: 32, sensor: 'DHT22', type: 'temperature');
        expect(a, isNot(equals(b)));
      });

      test('models with different sensors are not equal', () {
        final a = SensorModel(pin: 34, sensor: 'DHT22', type: 'temperature');
        final b = SensorModel(pin: 34, sensor: 'DS18B20', type: 'temperature');
        expect(a, isNot(equals(b)));
      });

      test('models with different types are not equal', () {
        final a = SensorModel(pin: 34, sensor: 'DHT22', type: 'temperature');
        final b = SensorModel(pin: 34, sensor: 'DHT22', type: 'humidity');
        expect(a, isNot(equals(b)));
      });

      test('models with different labels are not equal', () {
        final a = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
          label: 'Air Temp',
        );
        final b = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
          label: 'Water Temp',
        );
        expect(a, isNot(equals(b)));
      });

      test('model with null label and model with empty label are not equal', () {
        final a = SensorModel(pin: 34, sensor: 'DHT22', type: 'temperature');
        final b = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
          label: '',
        );
        expect(a, isNot(equals(b)));
      });
    });

    group('copyWith', () {
      test('copyWith creates an identical copy when no overrides', () {
        final original = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
          label: 'Air Temp',
        );
        final copy = SensorModel(
          pin: original.pin,
          sensor: original.sensor,
          type: original.type,
          label: original.label,
        );
        expect(copy, equals(original));
      });

      test('copyWith changes pin', () {
        final original = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
        );
        final modified = SensorModel(
          pin: 32,
          sensor: original.sensor,
          type: original.type,
          label: original.label,
        );
        expect(modified.pin, equals(32));
        expect(modified.sensor, equals(original.sensor));
        expect(modified.type, equals(original.type));
      });

      test('copyWith adds a label', () {
        final original = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
        );
        final modified = SensorModel(
          pin: original.pin,
          sensor: original.sensor,
          type: original.type,
          label: 'Air Temp',
        );
        expect(modified.label, equals('Air Temp'));
        expect(modified.pin, equals(original.pin));
      });

      test('copyWith removes a label', () {
        final original = SensorModel(
          pin: 34,
          sensor: 'DHT22',
          type: 'temperature',
          label: 'Air Temp',
        );
        final modified = SensorModel(
          pin: original.pin,
          sensor: original.sensor,
          type: original.type,
        );
        expect(modified.label, isNull);
      });
    });
  });
}
