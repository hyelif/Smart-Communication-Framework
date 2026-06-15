class AppConstants {
  // API
  static const String defaultApiUrl = 'http://192.168.1.100';
  static const int defaultApiPort = 80;
  static const int apiTimeout = 30000;

  // Storage Keys
  static const String keyApiUrl = 'api_url';
  static const String keyApiPort = 'api_port';
  static const String keyApiKey = 'api_key';
  static const String keyPairedDevices = 'paired_devices';
  static const String keySensorConfigs = 'sensor_configs';
  static const String keySettings = 'app_settings';

  // LoRa
  static const int defaultLoRaFrequency = 915;
  static const int defaultLoRaTxPower = 20;
  static const int defaultLoRaSpreadingFactor = 7;

  // Sensor Types
  static const String sensorTypeTemp = 'temperature';
  static const String sensorTypeHumidity = 'humidity';
  static const String sensorTypePh = 'ph';
  static const String sensorTypeTds = 'tds';
  static const String sensorTypeWaterLevel = 'water_level';

  // NFC
  static const String nfcDeviceIdPrefix = 'SMARTPONIC:';
}