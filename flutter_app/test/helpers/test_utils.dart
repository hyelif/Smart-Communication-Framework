import 'package:flutter_test/flutter_test.dart';

/// Extension on [TestWidgetsTestBinding] to pump and settle with a timeout.
extension PumpSafe on WidgetTester {
  Future<void> pumpAndSettleSafe([Duration timeout = const Duration(seconds: 5)]) {
    return pumpingUntil(timeout, (_) => false);
  }

  Future<void> pumpingUntil(
    Duration timeout,
    bool Function(Duration elapsed) shouldStop,
  ) async {
    final start = DateTime.now();
    while (true) {
      await pump();
      final elapsed = DateTime.now().difference(start);
      if (shouldStop(elapsed) || elapsed > timeout) break;
    }
  }
}

/// Creates a mock config list for testing.
Map<String, dynamic> mockSensorConfig({
  int pin = 35,
  String sensor = 'pH',
  String type = 'AI',
  String? label,
}) {
  final map = <String, dynamic>{
    'pin': pin,
    'sensor': sensor,
    'type': type,
  };
  if (label != null) map['label'] = label;
  return map;
}

/// Creates a full mock config list with [count] sensors.
List<Map<String, dynamic>> mockConfigList({int count = 3}) {
  final sensors = [
    {'pin': 35, 'sensor': 'pH', 'type': 'AI'},
    {'pin': 34, 'sensor': 'TDS', 'type': 'AI'},
    {'pin': 16, 'sensor': 'DHT22', 'type': 'DI'},
    {'pin': 25, 'sensor': 'Relay', 'type': 'DO', 'label': 'Water Pump'},
    {'pin': 12, 'sensor': 'Rain', 'type': 'DI'},
  ];
  return sensors.take(count).map((s) => Map<String, dynamic>.from(s)).toList();
}
