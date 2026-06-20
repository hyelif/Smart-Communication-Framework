import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/environment.dart';

/// HTTP client for the Turso (libSQL) database pipeline API.
///
/// Uses two API tokens:
/// - [readToken] — for SELECT queries (login, data viewing)
/// - [writeToken] — for INSERT/UPDATE/DELETE (relay commands)
///
/// Turso pipeline endpoint: `POST /v2/pipeline`
///
/// ## Usage
/// ```dart
/// final rows = await TursoService.query(
///   'SELECT * FROM users WHERE username = ?',
///   ['admin'],
/// );
///
/// final id = await TursoService.execute(
///   'INSERT INTO relay_commands (hardware_id, relay_id, action, status) '
///   'VALUES (?, ?, ?, ?)',
///   ['abc123', 0, 'ON', 'pending'],
/// );
/// ```
class TursoService {
  TursoService();

  static final http.Client _client = http.Client();

  static const int _maxRetries = 2;
  static const Duration _retryDelay = Duration(milliseconds: 500);

  /// Base URL for the Turso pipeline API.
  static String get _baseUrl => EnvironmentConfig.current.tursoUrl;

  /// Read-only token for SELECT queries.
  static String get _readToken => EnvironmentConfig.current.tursoReadToken;

  /// Write token for INSERT/UPDATE/DELETE.
  static String get _writeToken => EnvironmentConfig.current.tursoWriteToken;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Check whether the Turso API is reachable and the tokens work.
  ///
  /// Runs `SELECT 1` and returns `true` on success.
  /// The [error] out parameter receives the failure reason if any.
  static Future<bool> checkConnection({void Function(String)? onError}) async {
    // First try a raw HTTP call to capture the exact error
    final token = _readToken;
    if (token.isEmpty) {
      onError?.call('Turso read token is empty.');
      return false;
    }
    if (_baseUrl.isEmpty) {
      onError?.call('Turso URL is empty.');
      return false;
    }

    try {
      final response = await _client
          .post(
            Uri.parse(_baseUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: '{"requests":[{"type":"execute","stmt":{"sql":"SELECT 1 AS ok"}}]}',
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true;
      }

      onError?.call(
        'Turso returned HTTP ${response.statusCode}: ${response.body}',
      );
      return false;
    } catch (e) {
      onError?.call('Network error: $e');
      return false;
    }
  }

  /// Execute a SELECT query and return the result rows.
  ///
  /// Each row is a `Map<String, dynamic>` keyed by column name.
  /// Returns an empty list on error or no results.
  static Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? args,
  ]) async {
    final response = await _pipeline(sql, args, useWriteToken: false);
    if (response == null) return [];

    return _parseRows(response);
  }

  /// Execute an INSERT/UPDATE/DELETE and return the last inserted row ID,
  /// or `null` if no row was inserted.
  static Future<int?> execute(
    String sql, [
    List<dynamic>? args,
  ]) async {
    final response = await _pipeline(sql, args, useWriteToken: true);
    if (response == null) return null;

    return response['last_insert_rowid'] as int?;
  }

  // ---------------------------------------------------------------------------
  // Pipeline request
  // ---------------------------------------------------------------------------

  /// Send a single-statement pipeline request to Turso.
  ///
  /// Returns the first result's `response` object, or `null` on failure.
  static Future<Map<String, dynamic>?> _pipeline(
    String sql,
    List<dynamic>? args, {
    required bool useWriteToken,
  }) async {
    final token = useWriteToken ? _writeToken : _readToken;
    if (token.isEmpty) {
      // ignore: avoid_print
      print('[TursoService] No ${useWriteToken ? 'write' : 'read'} token configured');
      return null;
    }

    final body = _buildRequestBody(sql, args);

    for (var attempt = 0; attempt < _maxRetries; attempt++) {
      try {
        final response = await _client
            .post(
              Uri.parse(_baseUrl),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          final results = decoded['results'] as List<dynamic>?;
          if (results == null || results.isEmpty) return null;

          final first = results[0] as Map<String, dynamic>;
          if (first['type'] == 'error') {
            // ignore: avoid_print
            print('[TursoService] SQL error: ${first['response']}');
            return null;
          }

          return first['response']?['result'] as Map<String, dynamic>?;
        }

        if (response.statusCode < 500) {
          // Client error — no point retrying
          // ignore: avoid_print
          print('[TursoService] HTTP ${response.statusCode}: ${response.body}');
          return null;
        }
      } catch (e) {
        // ignore: avoid_print
        print('[TursoService] Attempt $attempt failed: $e');
      }

      if (attempt < _maxRetries - 1) {
        await Future.delayed(_retryDelay);
      }
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Request builder
  // ---------------------------------------------------------------------------

  /// Build the Turso pipeline JSON body for a single statement.
  static Map<String, dynamic> _buildRequestBody(
    String sql,
    List<dynamic>? args,
  ) {
    final stmt = <String, dynamic>{'sql': sql};

    if (args != null && args.isNotEmpty) {
      stmt['args'] = args.map(_toTypedArg).toList();
    }

    return {
      'requests': [
        {
          'type': 'execute',
          'stmt': stmt,
        },
      ],
    };
  }

  /// Convert a Dart value to a Turso typed argument.
  ///
  /// Turso requires ALL `value` fields to be JSON strings, even for
  /// integers and reals. The `type` discriminator tells the server how
  /// to interpret the string.
  static Map<String, dynamic> _toTypedArg(dynamic value) {
    if (value == null) {
      return {'type': 'null', 'value': null};
    }
    if (value is int) {
      return {'type': 'integer', 'value': value.toString()};
    }
    if (value is double) {
      return {'type': 'real', 'value': value.toString()};
    }
    if (value is bool) {
      return {'type': 'integer', 'value': value ? '1' : '0'};
    }
    // Default to text for String and everything else
    return {'type': 'text', 'value': value.toString()};
  }

  // ---------------------------------------------------------------------------
  // Response parser
  // ---------------------------------------------------------------------------

  /// Parse the `result` object from a Turso pipeline response into
  /// a list of column-keyed maps.
  ///
  /// Turso returns rows as arrays of typed objects:
  /// ```json
  /// {"cols": [{"name": "id"}, {"name": "username"}],
  ///  "rows": [[{"type": "integer", "value": "1"}, {"type": "text", "value": "admin"}]]}
  /// ```
  /// The `value` is always a JSON string — this method converts it to the
  /// appropriate Dart type (int, double, or String) based on the `type` field.
  static List<Map<String, dynamic>> _parseRows(
    Map<String, dynamic> result,
  ) {
    final cols = (result['cols'] as List<dynamic>?)
            ?.map((c) => (c as Map<String, dynamic>)['name'] as String)
            .toList() ??
        [];
    final rows = (result['rows'] as List<dynamic>?) ?? [];

    return rows.map((row) {
      final values = row as List<dynamic>;
      final map = <String, dynamic>{};
      for (var i = 0; i < cols.length && i < values.length; i++) {
        final typed = values[i] as Map<String, dynamic>;
        map[cols[i]] = _convertValue(typed);
      }
      return map;
    }).toList();
  }

  /// Convert a typed Turso value to the appropriate Dart type.
  ///
  /// Turso always encodes `value` as a JSON string, even for integers and
  /// reals. This method converts based on the `type` discriminator.
  static dynamic _convertValue(Map<String, dynamic> typed) {
    final type = typed['type'] as String?;
    final value = typed['value'];
    // value can be null (for SQL NULL)
    if (value == null) return null;

    switch (type) {
      case 'integer':
        return int.tryParse(value.toString()) ?? value;
      case 'real':
        return double.tryParse(value.toString()) ?? value;
      default:
        return value.toString();
    }
  }
}
