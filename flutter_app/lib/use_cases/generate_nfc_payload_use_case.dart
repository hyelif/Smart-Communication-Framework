import '../models/nfc_payload.dart';
import '../services/nfc_payload_service.dart';
import '../services/storage_service.dart';
import '../utils/config_validator.dart';

/// Generates an NFC payload for configuration deployment.
///
/// Builds the config with metadata (GPS, calibration, keys),
/// encrypts it, and returns an [NfcPayload] ready for NFC writing.
class GenerateNfcPayloadUseCase {
  /// Build and encrypt an NFC payload.
  ///
  /// [config] is the raw config list.
  /// [securityKey] is the node security key.
  /// [aesKey] is the AES encryption key (must be 16 characters).
  /// [latitude] and [longitude] are optional GPS coordinates.
  ///
  /// Throws [FormatException] if [aesKey] is invalid.
  /// Throws [Exception] if config is empty or invalid.
  Future<NfcPayload> call({
    required List<Map<String, dynamic>> config,
    required String securityKey,
    required String aesKey,
    double latitude = 0.0,
    double longitude = 0.0,
  }) async {
    if (config.isEmpty) {
      throw Exception('No configuration to deploy.');
    }

    // Validate AES key
    final validatedAesKey = NfcPayloadService.validateAesKey(aesKey);

    // Normalize config
    final normalizedConfig = ConfigValidator.normalizedFirmwareConfig(config);

    // Build config with metadata
    final configWithMetadata = <String, dynamic>{
      'config': normalizedConfig,
      'latitude': latitude,
      'longitude': longitude,
    };

    // Attach calibration profiles if available
    try {
      final profiles = await StorageService.loadCalibrationProfiles();
      if (profiles.isNotEmpty) {
        configWithMetadata['calibration'] = profiles;
      }
    } catch (_) {
      // Non-fatal
    }

    // Attach keys
    configWithMetadata['keys'] = {
      'aes128': validatedAesKey,
      'auth': NfcPayloadService.defaultAuthKey,
    };

    // Build firmware payload and encrypt
    final firmwarePayload = NfcPayloadService.withFirmwareFields(
      configPayload: configWithMetadata,
      securityKey: securityKey,
      aesKey: validatedAesKey,
    );

    final encryptedBytes = NfcPayloadService.buildEncryptedPayload(
      configPayload: firmwarePayload,
      aesKey: validatedAesKey,
    );

    return NfcPayload(
      configWithMetadata: configWithMetadata,
      securityKey: securityKey,
      aesKey: validatedAesKey,
      encryptedBytes: encryptedBytes,
    );
  }
}
