class SensorModel {
  final int pin;
  final String sensor;
  final String type;
  final String? label;

  SensorModel({
    required this.pin,
    required this.sensor,
    required this.type,
    this.label,
  });

  factory SensorModel.fromMap(Map<String, dynamic> map) {
    return SensorModel(
      pin: map['pin'] as int,
      sensor: map['sensor'] as String,
      type: map['type'] as String,
      label: map['label'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'pin': pin,
      'sensor': sensor,
      'type': type,
    };
    if (label != null && label!.trim().isNotEmpty) {
      map['label'] = label!;
    }
    return map;
  }
}
