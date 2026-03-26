import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://192.168.4.1';

  static Future<Map<String, dynamic>> sendConfig(
    List<Map<String, dynamic>> config,
  ) async {
    final uri = Uri.parse('$baseUrl/config');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'config': config}),
    );

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

  static Future<Map<String, dynamic>> fetchConfig() async {
    final uri = Uri.parse('$baseUrl/config');
    final response = await http.get(uri);

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
