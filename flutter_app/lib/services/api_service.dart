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
}
