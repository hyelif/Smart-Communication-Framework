import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// ESP32 node hardware variants.
enum Esp32Variant {
  esp32Node30Pin,
  esp32Node38Pin,
}

/// A structured validation error with a machine-readable [code] and
/// human-readable [message].
class ConfigValidationError {
  final String code;
  final String message;

  const ConfigValidationError({required this.code, required this.message});

  @override
  String toString() => message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConfigValidationError &&
          code == other.code &&
          message == other.message;

  @override
  int get hashCode => Object.hash(code, message);
}

/// Pure validation and normalization logic for ESP32 node configurations.
///
/// All methods are static pure functions suitable for unit testing.
class ConfigValidator {
  ConfigValidator._();

  // ---------------------------------------------------------------------------
  // Pin & slot tables
  // ---------------------------------------------------------------------------

  /// Maximum config slots the firmware supports (38-pin variant).
  static const int maxFirmwareConfigSlots = 24;

  /// 30-pin variant safe pins (LoRa + WiFi I2C).
  static const List<int> firmwareSafePins30Pin = [
    4, 13, 16, 17, 21, 22, 25, 26,
    32, 33, 34, 35, 36, 39,
  ];

  /// 38-pin variant safe pins.
  ///
  /// LoRa RA-02: SCK=18, MISO=19, MOSI=23, CS=5, RST=2
  /// NFC PN532: SDA=21, SCL=22
  /// ADC1 (safe with WiFi): 32, 33, 34, 35, 36, 39
  /// Digital I/O: 12, 13, 15, 16, 17, 25, 26
  static const List<int> firmwareSafePins38Pin = [
    12, 13, 15, 16, 17, // DI: DHT22, Rain, WaterTemp
    25, 26, // DO: Relay
    32, 33, 34, 35, 36, 39, // AI: pH, TDS, Turbidity
  ];

  /// Pins reserved for hardware modules (LoRa + NFC).
  static const List<int> reservedNodePins = [2, 5, 18, 19, 21, 22, 23];

  /// Pin groups by signal type.
  ///
  /// AI: Analog Input for pH, TDS, Turbidity (6 pins)
  /// DI: Digital Input for Rain, DHT22, WaterTemp (5 pins)
  /// DO: Digital Output for Relay (2 pins)
  static const Map<String, List<int>> pinGroups = {
    'AI': [32, 33, 34, 35, 36, 39],
    'DI': [12, 13, 15, 16, 17],
    'DO': [25, 26],
  };

  /// Default pin for each supported sensor.
  static const Map<String, int> defaultSensorPins = {
    'Turbidity': 36, // AI
    'Rain': 12, // DI
    'TDS': 34, // AI
    'pH': 35, // AI
    'DHT22': 16, // DI
    'WaterTemp': 17, // DI
    'Relay': 25, // DO
  };

  /// Required signal type for each supported sensor.
  static const Map<String, String> sensorRequirements = {
    'pH': 'AI',
    'TDS': 'AI',
    'Turbidity': 'AI',
    'Rain': 'DI',
    'DHT22': 'DI',
    'WaterTemp': 'DI',
    'Relay': 'DO',
  };

  /// Maximum config slots per variant.
  static const Map<Esp32Variant, int> variantMaxSlots = {
    Esp32Variant.esp32Node30Pin: 15,
    Esp32Variant.esp32Node38Pin: 24,
  };

  /// Safe pins per variant.
  static const Map<Esp32Variant, List<int>> variantSafePins = {
    Esp32Variant.esp32Node30Pin: firmwareSafePins30Pin,
    Esp32Variant.esp32Node38Pin: firmwareSafePins38Pin,
  };

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns the safe GPIO pins for [variant].
  static List<int> safePinsFor(Esp32Variant variant) =>
      variantSafePins[variant] ?? firmwareSafePins30Pin;

  /// Returns the maximum number of config slots for [variant].
  static int maxSlotsFor(Esp32Variant variant) =>
      variantMaxSlots[variant] ?? 15;

  /// Normalise a sensor name to its canonical form.
  ///
  /// Returns the canonical name if recognised, otherwise returns the trimmed
  /// input unchanged.
  static String canonicalSensorName(String sensor) {
    final normalized = sensor.trim().toUpperCase();
    if (normalized == 'PH') return 'pH';
    if (normalized == 'TDS') return 'TDS';
    if (normalized == 'TURBIDITY') return 'Turbidity';
    if (normalized == 'RAIN') return 'Rain';
    if (normalized == 'DHT22') return 'DHT22';
    if (normalized == 'WATERTEMP') return 'WaterTemp';
    if (normalized == 'RELAY') return 'Relay';
    return sensor.trim();
  }

  /// Normalise a raw config list: canonicalise sensor names, set expected
  /// types, and strip unknown keys.
  static List<Map<String, dynamic>> normalizedFirmwareConfig(
    List<Map<String, dynamic>> config,
  ) {
    return config.map((item) {
      final sensor = canonicalSensorName(item['sensor']?.toString() ?? '');
      final expectedType = sensorRequirements[sensor];
      final normalized = <String, dynamic>{
        'pin': item['pin'],
        'sensor': sensor,
        'type': expectedType ?? item['type']?.toString().toUpperCase(),
      };
      final label = item['label']?.toString().trim();
      if (label != null && label.isNotEmpty) {
        normalized['label'] = label;
      }
      return normalized;
    }).toList();
  }

  /// Validate a config list against the given [variant].
  ///
  /// Returns a list of [ConfigValidationError]s. An empty list means the
  /// config is valid.
  static List<ConfigValidationError> firmwareConfigErrors(
    List<Map<String, dynamic>> config, {
    Esp32Variant variant = Esp32Variant.esp32Node30Pin,
  }) {
    final errors = <ConfigValidationError>[];
    final usedPins = <int>{};
    final safePins = safePinsFor(variant);
    final maxSlots = maxSlotsFor(variant);

    if (config.isEmpty) {
      errors.add(const ConfigValidationError(
        code: 'empty_config',
        message: 'Add at least one GPIO node before deploying.',
      ));
    }

    if (config.length > maxSlots) {
      errors.add(ConfigValidationError(
        code: 'too_many_slots',
        message: 'ESP32 firmware supports only $maxSlots GPIO config slots.',
      ));
    }

    for (final item in config) {
      final pin = item['pin'];
      final sensor = item['sensor']?.toString() ?? '';
      final type = item['type']?.toString().toUpperCase() ?? '';

      if (pin is! int) {
        errors.add(ConfigValidationError(
          code: 'invalid_pin',
          message: '$sensor has an invalid GPIO pin.',
        ));
        continue;
      }

      if (!safePins.contains(pin)) {
        errors.add(ConfigValidationError(
          code: 'unsafe_pin',
          message: 'GPIO $pin is not accepted by the ESP32 node firmware.',
        ));
      }

      if (reservedNodePins.contains(pin)) {
        errors.add(ConfigValidationError(
          code: 'reserved_pin',
          message: 'GPIO $pin is reserved by LoRa/NFC hardware on this node.',
        ));
      }

      if (!usedPins.add(pin)) {
        errors.add(ConfigValidationError(
          code: 'duplicate_pin',
          message: 'GPIO $pin is assigned more than once.',
        ));
      }

      if (!sensorRequirements.containsKey(sensor)) {
        errors.add(ConfigValidationError(
          code: 'unsupported_sensor',
          message: '$sensor is not a supported firmware sensor type.',
        ));
        continue;
      }

      final expectedType = sensorRequirements[sensor]!;
      if (type != expectedType) {
        errors.add(ConfigValidationError(
          code: 'wrong_type',
          message: '$sensor must use $expectedType, not $type.',
        ));
      }

      final validPins = pinGroups[expectedType] ?? const <int>[];
      if (!validPins.contains(pin)) {
        errors.add(ConfigValidationError(
          code: 'pin_type_mismatch',
          message: 'GPIO $pin cannot be used as $expectedType for $sensor.',
        ));
      }
    }

    return errors;
  }

  /// Deep-compare two config lists using [mapEquals].
  static bool sameConfig(
    List<Map<String, dynamic>> left,
    List<Map<String, dynamic>> right,
  ) {
    if (identical(left, right)) return true;
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (!mapEquals(left[i], right[i])) return false;
    }
    return true;
  }

  /// Map a component name to a Material [IconData].
  static IconData componentIcon(String component) {
    final normalized = component.toLowerCase();
    if (normalized.contains('pump')) return Icons.water_rounded;
    if (normalized.contains('valve')) return Icons.tune_rounded;
    if (normalized.contains('relay')) return Icons.toggle_on_rounded;
    if (normalized.contains('temp')) return Icons.thermostat_rounded;
    if (normalized.contains('ph')) return Icons.science_outlined;
    if (normalized.contains('tds')) return Icons.opacity_rounded;
    if (normalized.contains('turbidity')) return Icons.water_drop_outlined;
    return Icons.sensors_outlined;
  }
}
