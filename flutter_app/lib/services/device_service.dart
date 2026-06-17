import '../services/api_service.dart';

class DeviceService {
  /// Fetch live sensor data from the ESP32 node.
  /// Returns a list of sensor config maps from the node's /config endpoint.
  Future<List<Map<String, dynamic>>> fetchLiveSensors() async {
    try {
      final result = await ApiService.fetchConfig('');
      if (result['ok'] == true && result['data'] != null) {
        final data = result['data'];
        if (data is Map<String, dynamic> && data['config'] is List) {
          return (data['config'] as List)
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      }
    } catch (_) {
      // Node not reachable — return empty list
    }
    return [];
  }
}
