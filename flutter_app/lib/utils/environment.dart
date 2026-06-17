/// Environment configuration profiles for the SmartPonic app.
///
/// Three built-in profiles are available:
/// - [dev]: Direct ESP32 access point (default).
/// - [staging]: Local development server.
/// - [prod]: Remote production server.
///
/// Override at compile time with `--dart-define`:
/// ```sh
/// flutter run --dart-define=SMARTPONIC_ENV=staging
/// flutter run --dart-define=SMARTPONIC_API_BASE_URL=http://10.0.0.1
/// ```
class EnvironmentConfig {
  /// Base URL for the ESP32 node API (e.g. `http://192.168.4.1`).
  final String apiBaseUrl;

  /// Base URL for NFC configuration endpoint.
  final String nfcConfigUrl;

  /// Whether this profile targets a production environment.
  final bool isProduction;

  const EnvironmentConfig({
    required this.apiBaseUrl,
    required this.nfcConfigUrl,
    required this.isProduction,
  });

  // ---------------------------------------------------------------------------
  // Built-in profiles
  // ---------------------------------------------------------------------------

  /// Development profile -- direct ESP32 access point.
  ///
  /// Connects to the node's own Wi-Fi AP at the default ESP32 address.
  static const EnvironmentConfig dev = EnvironmentConfig(
    apiBaseUrl: 'http://192.168.4.1',
    nfcConfigUrl: 'http://192.168.4.1/nfc',
    isProduction: false,
  );

  /// Staging profile -- local development server.
  ///
  /// Use when running a PHP/XAMPP backend on the same LAN.
  static const EnvironmentConfig staging = EnvironmentConfig(
    apiBaseUrl: 'http://192.168.1.100:8080',
    nfcConfigUrl: 'http://192.168.1.100:8080/nfc',
    isProduction: false,
  );

  /// Production profile -- remote server.
  ///
  /// Replace the URLs below with your actual production endpoints.
  static const EnvironmentConfig prod = EnvironmentConfig(
    apiBaseUrl: 'https://api.smartponic.example.com',
    nfcConfigUrl: 'https://api.smartponic.example.com/nfc',
    isProduction: true,
  );

  // ---------------------------------------------------------------------------
  // dart-define keys
  // ---------------------------------------------------------------------------

  static const String _envKey = 'SMARTPONIC_ENV';
  static const String _apiUrlKey = 'SMARTPONIC_API_BASE_URL';
  static const String _nfcUrlKey = 'SMARTPONIC_NFC_CONFIG_URL';

  /// The active environment configuration.
  ///
  /// Resolution order:
  /// 1. `SMARTPONIC_ENV` dart-define (`"dev"`, `"staging"`, or `"prod"`).
  /// 2. Individual `SMARTPONIC_API_BASE_URL` / `SMARTPONIC_NFC_CONFIG_URL`
  ///    overrides (partial overrides merge with the profile selected by
  ///    `SMARTPONIC_ENV`, or [dev] if unset).
  /// 3. Defaults to [dev].
  static EnvironmentConfig get current {
    final env = String.fromEnvironment(_envKey, defaultValue: 'dev');
    final base = switch (env) {
      'staging' => staging,
      'prod' => prod,
      _ => dev,
    };

    final apiOverride = String.fromEnvironment(_apiUrlKey, defaultValue: '');
    final nfcOverride = String.fromEnvironment(_nfcUrlKey, defaultValue: '');

    if (apiOverride.isEmpty && nfcOverride.isEmpty) {
      return base;
    }

    return EnvironmentConfig(
      apiBaseUrl: apiOverride.isNotEmpty ? apiOverride : base.apiBaseUrl,
      nfcConfigUrl: nfcOverride.isNotEmpty ? nfcOverride : base.nfcConfigUrl,
      isProduction: base.isProduction,
    );
  }
}
