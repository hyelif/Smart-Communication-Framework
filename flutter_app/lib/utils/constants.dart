import 'environment.dart';

/// Application-wide constants for the SmartPonic system.
///
/// All values are immutable. Use [EnvironmentConfig] for environment-specific
/// settings such as API base URLs.
class AppConstants {
  // ---------------------------------------------------------------------------
  // API
  // ---------------------------------------------------------------------------

  /// Default HTTP port for ESP32 node communication.
  static const int defaultApiPort = 80;

  /// Maximum time (in milliseconds) to wait for an API response.
  ///
  /// Unit: milliseconds.
  static const int apiTimeout = 30000;

  // ---------------------------------------------------------------------------
  // Storage keys (SharedPreferences)
  // ---------------------------------------------------------------------------

  /// Key for the persisted API base URL override.
  static const String keyApiUrl = 'api_url';

  /// Key for the persisted API port override.
  static const String keyApiPort = 'api_port';

  /// Key for the persisted node security key.
  static const String keyApiKey = 'api_key';

  /// Key for the list of paired device identifiers.
  static const String keyPairedDevices = 'paired_devices';

  /// Key for the list of saved sensor configurations.
  static const String keySensorConfigs = 'sensor_configs';

  /// Key for general app settings map.
  static const String keySettings = 'app_settings';

  // ---------------------------------------------------------------------------
  // LoRa radio configuration
  // ---------------------------------------------------------------------------

  /// Default LoRa frequency in MHz (e.g. 915 for US/AU, 868 for EU, 923 for
  /// Asia).
  ///
  /// Unit: MHz.
  static const int defaultLoRaFrequency = 915;

  /// Default LoRa transmit power in dBm.
  ///
  /// Unit: dBm.
  static const int defaultLoRaTxPower = 20;

  /// Default LoRa spreading factor (SF7-SF12).
  ///
  /// Higher values increase range but reduce data rate.
  static const int defaultLoRaSpreadingFactor = 7;

  /// Region-aware LoRa frequency presets.
  ///
  /// Each entry maps a region code to its standard centre frequency in MHz.
  ///
  /// Units: MHz.
  static const Map<String, int> loRaRegionFrequencies = {
    'US': 915, // Americas, Australia
    'EU': 868, // Europe
    'IN': 865, // India
    'AS': 923, // Asia (Japan, Singapore, Thailand)
    'CN': 470, // China
    'RU': 864, // Russia
    'KR': 921, // South Korea
  };

  // ---------------------------------------------------------------------------
  // Sensor type identifiers
  // ---------------------------------------------------------------------------

  /// Sensor type key for temperature.
  ///
  /// Unit: degrees Celsius.
  static const String sensorTypeTemp = 'temperature';

  /// Sensor type key for humidity.
  ///
  /// Unit: relative humidity percent (0-100 %RH).
  static const String sensorTypeHumidity = 'humidity';

  /// Sensor type key for pH level.
  ///
  /// Unit: pH scale (0-14).
  static const String sensorTypePh = 'ph';

  /// Sensor type key for total dissolved solids.
  ///
  /// Unit: ppm (parts per million).
  static const String sensorTypeTds = 'tds';

  /// Sensor type key for water level.
  ///
  /// Unit: centimetres (cm) or discrete level index.
  static const String sensorTypeWaterLevel = 'water_level';

  // ---------------------------------------------------------------------------
  // NFC
  // ---------------------------------------------------------------------------

  /// Prefix prepended to device identifiers in NFC NDEF records.
  static const String nfcDeviceIdPrefix = 'SMARTPONIC:';

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// Private constructor to prevent instantiation.
  AppConstants._();
}
