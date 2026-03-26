class SensorModel {
  final int pin;
  final String sensor;
  final String type;

  SensorModel({
    required this.pin,
    required this.sensor,
    required this.type,
  });

  factory SensorModel.fromMap(Map<String, dynamic> map) {
    return SensorModel(
      pin: map['pin'] as int,
      sensor: map['sensor'] as String,
      type: map['type'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'pin': pin,
      'sensor': sensor,
      'type': type,
    };
  }
}
