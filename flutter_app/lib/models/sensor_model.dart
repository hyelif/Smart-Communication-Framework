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
    final map = <String, dynamic>{
      'pin': pin,
      'sensor': sensor,
      'type': type,
    };
    if (label != null && label!.trim().isNotEmpty) {
      map['label'] = label!;
    }
    return map;
  }

  SensorModel copyWith({
    int? pin,
    String? sensor,
    String? type,
    String? label,
  }) {
    return SensorModel(
      pin: pin ?? this.pin,
      sensor: sensor ?? this.sensor,
      type: type ?? this.type,
      label: label ?? this.label,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SensorModel &&
        other.pin == pin &&
        other.sensor == sensor &&
        other.type == type &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(pin, sensor, type, label);

  @override
  String toString() {
    return 'SensorModel(pin: $pin, sensor: $sensor, type: $type, label: $label)';
  }
}
