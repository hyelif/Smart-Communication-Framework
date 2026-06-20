import '../services/api_service.dart';

/// Loads a device configuration from an ESP32 node.
///
/// Fetches the current config from the node's /config endpoint
/// using the provided security key.
class LoadDeviceConfigUseCase {
  /// Fetch config from the node secured by [securityKey].
  ///
  /// Returns the config list on success, or throws on failure.
  Future<List<Map<String, dynamic>>> call(String securityKey) async {
    final result = await ApiService.fetchConfig(securityKey);

    if (result['ok'] == true) {
      final data = result['data'];
      if (data is Map<String, dynamic> && data['config'] is List) {
        return (data['config'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
      throw Exception('ESP32 returned invalid config format.');
    }

    throw Exception(ApiService.friendlyApiMessage(result));
  }
}
