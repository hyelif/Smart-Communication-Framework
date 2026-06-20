import '../utils/config_validator.dart';

/// Validates a node configuration against ESP32 firmware constraints.
///
/// Delegates to [ConfigValidator] for the actual validation logic.
/// Returns a list of [ConfigValidationError]s; an empty list means valid.
class ValidateConfigurationUseCase {
  /// Validate [config] against the given ESP32 [variant].
  ///
  /// Returns an empty list if the configuration is valid.
  List<ConfigValidationError> call(
    List<Map<String, dynamic>> config, {
    Esp32Variant variant = Esp32Variant.esp32Node30Pin,
  }) {
    return ConfigValidator.firmwareConfigErrors(
      config,
      variant: variant,
    );
  }

  /// Normalize a config list to its canonical form.
  List<Map<String, dynamic>> normalize(
    List<Map<String, dynamic>> config,
  ) {
    return ConfigValidator.normalizedFirmwareConfig(config);
  }

  /// Deep-compare two config lists.
  bool sameConfig(
    List<Map<String, dynamic>> left,
    List<Map<String, dynamic>> right,
  ) {
    return ConfigValidator.sameConfig(left, right);
  }
}
