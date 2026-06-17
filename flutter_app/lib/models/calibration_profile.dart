class CalibrationProfile {
  final String sensorKey;
  final double? thresholdMin;
  final double? thresholdMax;
  final double? calibrationA;
  final double? calibrationB;
  final double? calibrationC;

  const CalibrationProfile({
    required this.sensorKey,
    this.thresholdMin,
    this.thresholdMax,
    this.calibrationA,
    this.calibrationB,
    this.calibrationC,
  });

  factory CalibrationProfile.fromMap(String key, Map<String, dynamic> map) {
    return CalibrationProfile(
      sensorKey: key,
      thresholdMin: _toDouble(map['threshold_min']),
      thresholdMax: _toDouble(map['threshold_max']),
      calibrationA: _toDouble(map['calibration_a']) ?? 1.0,
      calibrationB: _toDouble(map['calibration_b']) ?? 0.0,
      calibrationC: _toDouble(map['calibration_c']) ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sensor_key': sensorKey,
      if (thresholdMin != null) 'threshold_min': thresholdMin,
      if (thresholdMax != null) 'threshold_max': thresholdMax,
      if (calibrationA != null) 'calibration_a': calibrationA,
      if (calibrationB != null) 'calibration_b': calibrationB,
      if (calibrationC != null) 'calibration_c': calibrationC,
    };
  }

  CalibrationProfile copyWith({
    String? sensorKey,
    double? thresholdMin,
    double? thresholdMax,
    double? calibrationA,
    double? calibrationB,
    double? calibrationC,
  }) {
    return CalibrationProfile(
      sensorKey: sensorKey ?? this.sensorKey,
      thresholdMin: thresholdMin ?? this.thresholdMin,
      thresholdMax: thresholdMax ?? this.thresholdMax,
      calibrationA: calibrationA ?? this.calibrationA,
      calibrationB: calibrationB ?? this.calibrationB,
      calibrationC: calibrationC ?? this.calibrationC,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CalibrationProfile &&
        other.sensorKey == sensorKey &&
        other.thresholdMin == thresholdMin &&
        other.thresholdMax == thresholdMax &&
        other.calibrationA == calibrationA &&
        other.calibrationB == calibrationB &&
        other.calibrationC == calibrationC;
  }

  @override
  int get hashCode => Object.hash(
        sensorKey,
        thresholdMin,
        thresholdMax,
        calibrationA,
        calibrationB,
        calibrationC,
      );

  @override
  String toString() {
    return 'CalibrationProfile(sensorKey: $sensorKey, '
        'thresholdMin: $thresholdMin, thresholdMax: $thresholdMax, '
        'calibrationA: $calibrationA, calibrationB: $calibrationB, '
        'calibrationC: $calibrationC)';
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
