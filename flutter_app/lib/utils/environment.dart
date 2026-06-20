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

  /// Turso database HTTP API endpoint.
  ///
  /// Format: `https://[db-name]-[org].turso.io/v2/pipeline`
  final String tursoUrl;

  /// Read-only Turso API token (for login + data viewing).
  final String tursoReadToken;

  /// Write Turso API token (for relay commands).
  final String tursoWriteToken;

  /// Whether this profile targets a production environment.
  final bool isProduction;

  const EnvironmentConfig({
    required this.apiBaseUrl,
    required this.nfcConfigUrl,
    required this.tursoUrl,
    required this.tursoReadToken,
    required this.tursoWriteToken,
    required this.isProduction,
  });

  // ---------------------------------------------------------------------------
  // Built-in profiles
  // ---------------------------------------------------------------------------

  /// Development profile -- direct ESP32 access point + Turso dev database.
  ///
  /// Connects to the node's own Wi-Fi AP at the default ESP32 address.
  /// Turso tokens are hardcoded for development convenience.
  /// Override any field with `--dart-define` (see doc comment above).
  static const EnvironmentConfig dev = EnvironmentConfig(
    apiBaseUrl: 'http://192.168.4.1',
    nfcConfigUrl: 'http://192.168.4.1/nfc',
    tursoUrl: 'https://smartponic-db-hyelif.aws-ap-northeast-1.turso.io/v2/pipeline',
    tursoReadToken: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODE4OTAyMjMsImlkIjoiMDE5ZWQ0ZWYtMmMwMS03Nzk5LTg1YWItYmI2ZDNiYjQ0NTFlIiwicmlkIjoiNDBmY2YyOWYtYmFlZC00OGNjLThkNmQtNzM0ODg3N2NlYTQ5In0.jO6yq10BZC5xWiPpLP1x3YpaMFauW3SsDkEECBKkKKJv8WO9aX1V2J0PKg2WrydzuJbl2uxgZULsQe7nHqx0BA',
    tursoWriteToken: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODE4OTAyMjMsImlkIjoiMDE5ZWQ0ZWYtMmMwMS03Nzk5LTg1YWItYmI2ZDNiYjQ0NTFlIiwicmlkIjoiNDBmY2YyOWYtYmFlZC00OGNjLThkNmQtNzM0ODg3N2NlYTQ5In0.jO6yq10BZC5xWiPpLP1x3YpaMFauW3SsDkEECBKkKKJv8WO9aX1V2J0PKg2WrydzuJbl2uxgZULsQe7nHqx0BA',
    isProduction: false,
  );

  /// Staging profile -- local development server.
  static const EnvironmentConfig staging = EnvironmentConfig(
    apiBaseUrl: 'http://192.168.1.100:8080',
    nfcConfigUrl: 'http://192.168.1.100:8080/nfc',
    tursoUrl: 'https://smartponic-db-hyelif.aws-ap-northeast-1.turso.io/v2/pipeline',
    tursoReadToken: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODE4OTAyMjMsImlkIjoiMDE5ZWQ0ZWYtMmMwMS03Nzk5LTg1YWItYmI2ZDNiYjQ0NTFlIiwicmlkIjoiNDBmY2YyOWYtYmFlZC00OGNjLThkNmQtNzM0ODg3N2NlYTQ5In0.jO6yq10BZC5xWiPpLP1x3YpaMFauW3SsDkEECBKkKKJv8WO9aX1V2J0PKg2WrydzuJbl2uxgZULsQe7nHqx0BA',
    tursoWriteToken: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODE4OTAyMjMsImlkIjoiMDE5ZWQ0ZWYtMmMwMS03Nzk5LTg1YWItYmI2ZDNiYjQ0NTFlIiwicmlkIjoiNDBmY2YyOWYtYmFlZC00OGNjLThkNmQtNzM0ODg3N2NlYTQ5In0.jO6yq10BZC5xWiPpLP1x3YpaMFauW3SsDkEECBKkKKJv8WO9aX1V2J0PKg2WrydzuJbl2uxgZULsQe7nHqx0BA',
    isProduction: false,
  );

  /// Production profile -- remote server.
  ///
  /// In production, pass tokens via `--dart-define` instead of hardcoding.
  static const EnvironmentConfig prod = EnvironmentConfig(
    apiBaseUrl: 'https://api.smartponic.example.com',
    nfcConfigUrl: 'https://api.smartponic.example.com/nfc',
    tursoUrl: 'https://smartponic-db-hyelif.aws-ap-northeast-1.turso.io/v2/pipeline',
    tursoReadToken: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODE4OTAyMjMsImlkIjoiMDE5ZWQ0ZWYtMmMwMS03Nzk5LTg1YWItYmI2ZDNiYjQ0NTFlIiwicmlkIjoiNDBmY2YyOWYtYmFlZC00OGNjLThkNmQtNzM0ODg3N2NlYTQ5In0.jO6yq10BZC5xWiPpLP1x3YpaMFauW3SsDkEECBKkKKJv8WO9aX1V2J0PKg2WrydzuJbl2uxgZULsQe7nHqx0BA',
    tursoWriteToken: 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODE4OTAyMjMsImlkIjoiMDE5ZWQ0ZWYtMmMwMS03Nzk5LTg1YWItYmI2ZDNiYjQ0NTFlIiwicmlkIjoiNDBmY2YyOWYtYmFlZC00OGNjLThkNmQtNzM0ODg3N2NlYTQ5In0.jO6yq10BZC5xWiPpLP1x3YpaMFauW3SsDkEECBKkKKJv8WO9aX1V2J0PKg2WrydzuJbl2uxgZULsQe7nHqx0BA',
    isProduction: true,
  );

  // ---------------------------------------------------------------------------
  // dart-define keys
  // ---------------------------------------------------------------------------

  static const String _envKey = 'SMARTPONIC_ENV';
  static const String _apiUrlKey = 'SMARTPONIC_API_BASE_URL';
  static const String _nfcUrlKey = 'SMARTPONIC_NFC_CONFIG_URL';
  static const String _tursoUrlKey = 'SMARTPONIC_TURSO_URL';
  static const String _tursoReadKey = 'SMARTPONIC_TURSO_READ_TOKEN';
  static const String _tursoWriteKey = 'SMARTPONIC_TURSO_WRITE_TOKEN';

  /// The active environment configuration.
  ///
  /// Resolution order:
  /// 1. `SMARTPONIC_ENV` dart-define (`"dev"`, `"staging"`, or `"prod"`).
  /// 2. Individual `SMARTPONIC_API_BASE_URL` / `SMARTPONIC_NFC_CONFIG_URL`
  ///    overrides (partial overrides merge with the profile selected by
  ///    `SMARTPONIC_ENV`, or [dev] if unset).
  /// 3. Defaults to [dev].
  static EnvironmentConfig get current {
    const env = String.fromEnvironment(_envKey, defaultValue: 'dev');
    final base = switch (env) {
      'staging' => staging,
      'prod' => prod,
      _ => dev,
    };

    const apiOverride = String.fromEnvironment(_apiUrlKey, defaultValue: '');
    const nfcOverride = String.fromEnvironment(_nfcUrlKey, defaultValue: '');
    const tursoOverride = String.fromEnvironment(_tursoUrlKey, defaultValue: '');
    const readOverride = String.fromEnvironment(_tursoReadKey, defaultValue: '');
    const writeOverride = String.fromEnvironment(_tursoWriteKey, defaultValue: '');

    if (apiOverride.isEmpty && nfcOverride.isEmpty &&
        tursoOverride.isEmpty && readOverride.isEmpty && writeOverride.isEmpty) {
      return base;
    }

    return EnvironmentConfig(
      apiBaseUrl: apiOverride.isNotEmpty ? apiOverride : base.apiBaseUrl,
      nfcConfigUrl: nfcOverride.isNotEmpty ? nfcOverride : base.nfcConfigUrl,
      tursoUrl: tursoOverride.isNotEmpty ? tursoOverride : base.tursoUrl,
      tursoReadToken: readOverride.isNotEmpty ? readOverride : base.tursoReadToken,
      tursoWriteToken: writeOverride.isNotEmpty ? writeOverride : base.tursoWriteToken,
      isProduction: base.isProduction,
    );
  }
}
