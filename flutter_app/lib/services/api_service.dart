import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://192.168.4.1';
  static const String _nodeKeyHeader = 'X-Node-Key';

  static String friendlyConnectionMessage([Object? error]) {
    final message = error?.toString().toLowerCase() ?? '';
    if (message.contains('socketexception') ||
        message.contains('clientexception') ||
        message.contains('failed host lookup') ||
        message.contains('connection refused') ||
        message.contains('connection closed') ||
        message.contains('timed out')) {
      return 'ESP32 not connected. Join the node Wi-Fi and try again.';
    }

    return 'ESP32 is unavailable right now. Try again in a moment.';
  }

  static String friendlyApiMessage(Map<String, dynamic> result) {
    final statusCode = result['statusCode'];
    final body = result['body']?.toString().toLowerCase() ?? '';

    if (statusCode == 401) {
      return 'Security key is required to access this node.';
    }

    if (statusCode == 403) {
      if (body.contains('key_not_configured')) {
        return 'This node is not locked yet. Deploy once with a security key first.';
      }
      return 'Security key is incorrect for this node.';
    }

    return 'ESP32 is unavailable right now. Try again in a moment.';
  }

  static Future<Map<String, dynamic>> sendConfig(
    List<Map<String, dynamic>> config,
    String securityKey,
  ) async {
    final uri = Uri.parse('$baseUrl/config');

    final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            _nodeKeyHeader: securityKey,
          },
          body: jsonEncode({'config': config}),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      return {
        'ok': true,
        'statusCode': response.statusCode,
        'body': response.body,
      };
    }

    return {
      'ok': false,
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }

  static Future<Map<String, dynamic>> fetchConfig(String securityKey) async {
    final uri = Uri.parse('$baseUrl/config');
    final response = await http.get(
      uri,
      headers: {_nodeKeyHeader: securityKey},
    ).timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      return {
        'ok': false,
        'statusCode': response.statusCode,
        'body': response.body,
      };
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return {
        'ok': true,
        'statusCode': response.statusCode,
        'data': decoded,
      };
    }

    return {
      'ok': false,
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }

  static Future<Map<String, dynamic>> sendConfigWithMetadata(
    Map<String, dynamic> configWithMetadata,
    String securityKey,
  ) async {
    final uri = Uri.parse('$baseUrl/config');
    final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            _nodeKeyHeader: securityKey,
          },
          body: jsonEncode(configWithMetadata),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      return {
        'ok': true,
        'statusCode': response.statusCode,
        'body': response.body,
      };
    }

    return {
      'ok': false,
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }

  static Future<Map<String, dynamic>> fetchHealth() async {
    final uri = Uri.parse('$baseUrl/health');
    final response = await http
        .get(uri)
        .timeout(const Duration(seconds: 5));

    if (response.statusCode != 200) {
      return {
        'ok': false,
        'statusCode': response.statusCode,
        'body': response.body,
      };
    }

    final decoded = jsonDecode(response.body);

    if (decoded is Map<String, dynamic>) {
      return {
        'ok': true,
        'statusCode': response.statusCode,
        'data': decoded,
      };
    }

    return {
      'ok': false,
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }

  // Dashboard API (PHP server - different network from ESP32 node AP)
  // NOTE:
  // - On a real phone, "localhost" means the phone itself (connection refused).
  // - Use your PC/XAMPP IP on the same Wi-Fi network (example: 172.20.10.2).
  // - Path matches HQ firmware: http://<PC-IP>/smartponic/*.php (no "/php" folder).
  static const String dashboardBaseUrl = String.fromEnvironment(
    'SMARTPONIC_DASHBOARD_BASE_URL',
    defaultValue: 'http://172.20.10.2/smartponic',
  );

  static Future<Map<String, dynamic>> fetchCalibrationProfiles() async {
    // Fetch profiles from dashboard_data.php (node_id=1 by default)
    final uri = Uri.parse('$dashboardBaseUrl/dashboard_data.php?node_id=1&range=24h');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      return {
        'ok': false,
        'statusCode': response.statusCode,
        'body': response.body,
      };
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic> && decoded['status'] == 'success') {
      return {
        'ok': true,
        'statusCode': response.statusCode,
        'profiles': decoded['profiles'] ?? {},
      };
    }

    return {
      'ok': false,
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }

  static Future<Map<String, dynamic>> saveCalibrationProfiles(
    Map<String, dynamic> profiles,
  ) async {
    final uri = Uri.parse('$dashboardBaseUrl/dashboard_manage.php');
    final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'sync_profiles',
            'node_id': 1,
            'profiles': profiles,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return {
        'ok': true,
        'statusCode': response.statusCode,
        'profiles': decoded['profiles'] ?? {},
      };
    }

    return {
      'ok': false,
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }

  static Future<Map<String, dynamic>> saveNodeLocation({
    required double latitude,
    required double longitude,
    double? distance,
    int nodeId = 1,
  }) async {
    final uri = Uri.parse('$dashboardBaseUrl/dashboard_manage.php');
    final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': 'save_node_location',
            'node_id': nodeId,
            'latitude': latitude,
            'longitude': longitude,
            'distance': distance,
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      return {
        'ok': true,
        'statusCode': response.statusCode,
        'node': decoded['node'] ?? {},
      };
    }

    return {
      'ok': false,
      'statusCode': response.statusCode,
      'body': response.body,
    };
  }
}
