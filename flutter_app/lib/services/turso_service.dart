import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/environment.dart';

// ---------------------------------------------------------------------------
// Exception
// ---------------------------------------------------------------------------

/// Categorised error from the Turso pipeline API.
///
/// Callers should catch this and map [type] to a user-facing message:
/// - [TursoErrorType.auth] → "Invalid credentials. Check your Turso token."
/// - [TursoErrorType.network] → "Cannot reach database. Check your connection."
/// - [TursoErrorType.timeout] → "Database is slow. Try again."
/// - [TursoErrorType.sql] → "A database error occurred."
/// - [TursoErrorType.parse] → "Unexpected response from database."
class TursoException implements Exception {
  final TursoErrorType type;
  final String message;
  final String? detail;

  const TursoException({
    required this.type,
    required this.message,
    this.detail,
  });

  @override
  String toString() => 'TursoException($type): $message${detail != null ? ' ($detail)' : ''}';
}

enum TursoErrorType { auth, network, timeout, sql, parse, unknown }

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

/// HTTP client for the Turso (libSQL) database pipeline API.
///
/// Uses two API tokens:
/// - [readToken] — for SELECT queries (login, data viewing)
/// - [writeToken] — for INSERT/UPDATE/DELETE (relay commands)
///
/// ## Error handling
/// All public methods throw [TursoException] on failure. Callers should
/// catch it and map [TursoException.type] to a user-facing message.
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

  /// Dispose the underlying HTTP client. Call on app shutdown.
  static void dispose() {
    _client.close();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Check whether the Turso API is reachable and the tokens work.
  ///
  /// Runs `SELECT 1` and returns `true` on success.
  /// The [onError] callback receives the failure reason if any.
  static Future<bool> checkConnection({void Function(String)? onError}) async {
    final token = _readToken;
    if (token.isEmpty) {
      onError?.call(
        'Turso read token is empty. Pass --dart-define=SMARTPONIC_TURSO_READ_TOKEN=...',
      );
      return false;
    }
    if (_baseUrl.isEmpty) {
      onError?.call(
        'Turso URL is empty. Pass --dart-define=SMARTPONIC_TURSO_URL=...',
      );
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

      if (response.statusCode == 200) return true;

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
  /// Throws [TursoException] on failure.
  static Future<List<Map<String, dynamic>>> query(
    String sql, [
    List<dynamic>? args,
  ]) async {
    final response = await _pipeline(sql, args, useWriteToken: false);
    return _parseRows(response);
  }

  /// Execute an INSERT/UPDATE/DELETE and return the last inserted row ID,
  /// or `null` if no row was inserted.
  /// Throws [TursoException] on failure.
  static Future<int?> execute(
    String sql, [
    List<dynamic>? args,
  ]) async {
    final response = await _pipeline(sql, args, useWriteToken: true);

    final raw = response['last_insert_rowid'];
    if (raw == null) return null;
    if (raw is int) return raw;
    return int.tryParse(raw.toString());
  }

  // ---------------------------------------------------------------------------
  // Pipeline request
  // ---------------------------------------------------------------------------

  /// Send a single-statement pipeline request to Turso.
  ///
  /// Returns the first result's `response` object.
  /// Throws [TursoException] on any failure.
  static Future<Map<String, dynamic>> _pipeline(
    String sql,
    List<dynamic>? args, {
    required bool useWriteToken,
  }) async {
    final token = useWriteToken ? _writeToken : _readToken;
    if (token.isEmpty) {
      final kind = useWriteToken ? 'write' : 'read';
      throw TursoException(
        type: TursoErrorType.auth,
        message: 'No Turso $kind token configured.',
        detail: 'Pass --dart-define=SMARTPONIC_TURSO_${kind.toUpperCase()}_TOKEN=...',
      );
    }

    final body = _buildRequestBody(sql, args);
    String? lastError;

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
            .timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) {
            throw TursoException(
              type: TursoErrorType.parse,
              message: 'Unexpected response format from Turso.',
            );
          }

          final results = decoded['results'] as List<dynamic>?;
          if (results == null || results.isEmpty) {
            throw TursoException(
              type: TursoErrorType.parse,
              message: 'Empty response from Turso.',
            );
          }

          final first = results[0];
          if (first is! Map<String, dynamic>) {
            throw TursoException(
              type: TursoErrorType.parse,
              message: 'Unexpected result format from Turso.',
            );
          }

          if (first['type'] == 'error') {
            final errMsg = first['response']?.toString() ?? 'Unknown SQL error';
            throw TursoException(
              type: TursoErrorType.sql,
              message: 'Database error.',
              detail: errMsg,
            );
          }

          final result = first['response']?['result'];
          if (result is! Map<String, dynamic>) {
            // This can happen for INSERT/UPDATE — the result may be
            // {"type": "ok", "response": {"last_insert_rowid": ...}}
            // where the top-level response IS the result.
            final topResult = first['response'];
            if (topResult is Map<String, dynamic>) {
              return topResult;
            }
            throw TursoException(
              type: TursoErrorType.parse,
              message: 'Unexpected result structure from Turso.',
            );
          }

          return result;
        }

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw TursoException(
            type: TursoErrorType.auth,
            message: 'Turso authentication failed.',
            detail: 'HTTP ${response.statusCode}',
          );
        }

        if (response.statusCode < 500) {
          throw TursoException(
            type: TursoErrorType.sql,
            message: 'Turso returned HTTP ${response.statusCode}.',
            detail: response.body,
          );
        }

        // Server error (5xx) — retry
        lastError = 'Turso returned HTTP ${response.statusCode}';
      } on TursoException {
        rethrow;
      } on http.ClientException catch (e) {
        lastError = 'Network error: $e';
      } catch (e) {
        if (e is TimeoutException) {
          lastError = 'Request timed out after 5s.';
        } else {
          lastError = 'Unexpected error: $e';
        }
      }

      if (attempt < _maxRetries - 1) {
        await Future.delayed(_retryDelay * (attempt + 1)); // exponential: 500ms, 1s
      }
    }

    // All retries exhausted
    final isTimeout = lastError?.contains('timed out') ?? false;
    final isNetwork = lastError?.contains('Network error') ?? false;
    throw TursoException(
      type: isTimeout
          ? TursoErrorType.timeout
          : (isNetwork ? TursoErrorType.network : TursoErrorType.unknown),
      message: lastError ?? 'Request failed after $_maxRetries attempts.',
    );
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
    return {'type': 'text', 'value': value.toString()};
  }

  // ---------------------------------------------------------------------------
  // Response parser
  // ---------------------------------------------------------------------------

  /// Parse the `result` object from a Turso pipeline response into
  /// a list of column-keyed maps.
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
  static dynamic _convertValue(Map<String, dynamic> typed) {
    final type = typed['type'] as String?;
    final value = typed['value'];
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
