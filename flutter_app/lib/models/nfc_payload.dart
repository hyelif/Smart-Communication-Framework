import 'sensor_config.dart';

class NfcPayload {
  final List<SensorConfig> config;
  final String? securityKey;
  final String? aesKey;
  final String? firmwareVersion;
  final String? variant;

  const NfcPayload({
    required this.config,
    this.securityKey,
    this.aesKey,
    this.firmwareVersion,
    this.variant,
  });

  factory NfcPayload.fromMap(Map<String, dynamic> map) {
    final configList = map['config'] as List<dynamic>? ?? [];
    return NfcPayload(
      config: configList
          .map((e) => SensorConfig.fromMap(e as Map<String, dynamic>))
          .toList(),
      securityKey: map['securityKey'] as String?,
      aesKey: _extractAesKey(map),
      firmwareVersion: map['firmwareVersion'] as String?,
      variant: map['variant'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'config': config.map((s) => s.toMap()).toList(),
      if (securityKey != null) 'securityKey': securityKey,
      if (aesKey != null) 'aesKey': aesKey,
      if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
      if (variant != null) 'variant': variant,
    };
  }

  NfcPayload copyWith({
    List<SensorConfig>? config,
    String? securityKey,
    String? aesKey,
    String? firmwareVersion,
    String? variant,
  }) {
    return NfcPayload(
      config: config ?? this.config,
      securityKey: securityKey ?? this.securityKey,
      aesKey: aesKey ?? this.aesKey,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      variant: variant ?? this.variant,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NfcPayload &&
        _listEquals(other.config, config) &&
        other.securityKey == securityKey &&
        other.aesKey == aesKey &&
        other.firmwareVersion == firmwareVersion &&
        other.variant == variant;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(config),
        securityKey,
        aesKey,
        firmwareVersion,
        variant,
      );

  @override
  String toString() {
    return 'NfcPayload(config: $config, securityKey: $securityKey, '
        'aesKey: $aesKey, firmwareVersion: $firmwareVersion, '
        'variant: $variant)';
  }

  /// Extracts the AES key from either a top-level [aesKey] field or from
  /// the nested [keys.aes128] field (the format used by NfcPayloadService).
  static String? _extractAesKey(Map<String, dynamic> map) {
    final direct = map['aesKey'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;
    final keys = map['keys'] as Map<String, dynamic>?;
    if (keys != null) {
      return keys['aes128'] as String?;
    }
    return null;
  }

  static bool _listEquals(List<SensorConfig> a, List<SensorConfig> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
