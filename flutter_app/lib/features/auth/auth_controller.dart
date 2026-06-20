import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/turso_service.dart';
import 'models/user_session.dart';

/// Riverpod provider for the auth controller.
final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController();
});

/// Manages authentication state and session persistence.
///
/// Flow:
/// 1. App starts → [checkSession] loads saved session from SharedPreferences
/// 2. If session exists → restore it (skip login)
/// 3. If no session → show login screen
/// 4. [login] queries Turso, saves session on success
/// 5. [logout] clears session
class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState.unauthenticated()) {
    _init();
  }

  Future<void> _init() async {
    await checkSession();
  }

  static const String _prefsKeyUsername = 'auth_username';
  static const String _prefsKeyUserId = 'auth_user_id';
  static const String _prefsKeyHardwareIds = 'auth_hardware_ids';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Attempt to log in with [username] and [password].
  ///
  /// Queries Turso for a matching user, then loads the user's allowed nodes.
  /// On success, persists the session to SharedPreferences.
  /// On failure, returns an error message.
  Future<String?> login(String username, String password) async {
    // First check Turso connectivity so we give a useful error
    String? connError;
    final connected = await TursoService.checkConnection(
      onError: (msg) => connError = msg,
    );
    if (!connected) {
      return connError ?? 'Cannot reach the database. Check your Turso configuration.';
    }

    final hashed = _hashPassword(password);

    final rows = await TursoService.query(
      'SELECT id, username FROM users WHERE username = ? AND password = ?',
      [username, hashed],
    );

    if (rows.isEmpty) {
      return 'Invalid username or password.';
    }

    final userId = rows[0]['id'] as int;

    // Load allowed nodes for this user
    final nodeRows = await TursoService.query(
      'SELECT hardware_id, label FROM user_nodes WHERE user_id = ?',
      [userId],
    );

    final hardwareIds = nodeRows
        .map((r) => r['hardware_id'] as String)
        .toList();

    // Persist session
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyUsername, username);
    await prefs.setInt(_prefsKeyUserId, userId);
    await prefs.setStringList(_prefsKeyHardwareIds, hardwareIds);

    state = AuthState.authenticated(
      username: username,
      userId: userId,
      allowedHardwareIds: hardwareIds,
    );

    return null; // success
  }

  /// Log out the current user.
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyUsername);
    await prefs.remove(_prefsKeyUserId);
    await prefs.remove(_prefsKeyHardwareIds);

    state = const AuthState.unauthenticated();
  }

  /// Check for an existing session in SharedPreferences.
  ///
  /// Called on app startup to skip the login screen if the user
  /// is already authenticated.
  Future<void> checkSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString(_prefsKeyUsername);
      final userId = prefs.getInt(_prefsKeyUserId);
      final hardwareIds = prefs.getStringList(_prefsKeyHardwareIds);

      if (username != null && userId != null && hardwareIds != null) {
        state = AuthState.authenticated(
          username: username,
          userId: userId,
          allowedHardwareIds: hardwareIds,
        );
      }
    } catch (_) {
      // If SharedPreferences fails, just stay unauthenticated
      state = const AuthState.unauthenticated();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Compute SHA-256 hex digest of [input].
  static String _hashPassword(String input) {
    final digest = SHA256Digest().process(utf8.encode(input));
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
