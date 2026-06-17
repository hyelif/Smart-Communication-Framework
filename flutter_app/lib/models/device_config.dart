import 'sensor_config.dart';

class DeviceConfig {
  final List<SensorConfig> sensors;
  final String securityKey;
  final String aesKey;
  final String variant;
  final int? nodeId;

  const DeviceConfig({
    required this.sensors,
    required this.securityKey,
    required this.aesKey,
    required this.variant,
    this.nodeId,
  });

  factory DeviceConfig.fromMap(Map<String, dynamic> map) {
    final configList = map['config'] as List<dynamic>? ?? [];
    return DeviceConfig(
      sensors: configList
          .map((e) => SensorConfig.fromMap(e as Map<String, dynamic>))
          .toList(),
      securityKey: map['securityKey'] as String? ?? '',
      aesKey: map['aesKey'] as String? ?? '',
      variant: map['variant'] as String? ?? 'esp32Node30Pin',
      nodeId: map['nodeId'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'config': sensors.map((s) => s.toMap()).toList(),
      'securityKey': securityKey,
      'aesKey': aesKey,
      'variant': variant,
      if (nodeId != null) 'nodeId': nodeId,
    };
  }

  DeviceConfig copyWith({
    List<SensorConfig>? sensors,
    String? securityKey,
    String? aesKey,
    String? variant,
    int? nodeId,
  }) {
    return DeviceConfig(
      sensors: sensors ?? this.sensors,
      securityKey: securityKey ?? this.securityKey,
      aesKey: aesKey ?? this.aesKey,
      variant: variant ?? this.variant,
      nodeId: nodeId ?? this.nodeId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceConfig &&
        _listEquals(other.sensors, sensors) &&
        other.securityKey == securityKey &&
        other.aesKey == aesKey &&
        other.variant == variant &&
        other.nodeId == nodeId;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(sensors),
        securityKey,
        aesKey,
        variant,
        nodeId,
      );

  @override
  String toString() {
    return 'DeviceConfig(sensors: $sensors, securityKey: $securityKey, '
        'aesKey: $aesKey, variant: $variant, nodeId: $nodeId)';
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
