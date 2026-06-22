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
    // Use microtask to avoid blocking the constructor. The listener in
    // DeviceListController/HomeController will fire when state changes.
    Future.microtask(() => checkSession());
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
    try {
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
    } on TursoException catch (e) {
      return _tursoErrorMessage(e);
    } catch (e) {
      return 'Login error: ${e.toString()}';
    }
  }

  /// Claim a node by hardware ID for the current user.
  ///
  /// Checks if the node exists in the `nodes` table, then links it
  /// to this user via `user_nodes`. Returns `null` on success, or an
  /// error message on failure.
  Future<String?> claimNode(String hardwareId) async {
    if (!state.isLoggedIn) return 'Not logged in.';
    if (state.allowedHardwareIds.contains(hardwareId)) {
      return 'Node already linked to your account.';
    }

    try {
      // Check if node exists in the nodes table
      final rows = await TursoService.query(
        'SELECT hardware_id FROM nodes WHERE hardware_id = ?',
        [hardwareId],
      );
      if (rows.isEmpty) {
        return 'Node not found. Check the hardware ID and try again.';
      }

      // Remove node from any previous owner, then link to current user.
      // This ensures a node can only be claimed by one account at a time.
      await TursoService.execute(
        'DELETE FROM user_nodes WHERE hardware_id = ?',
        [hardwareId],
      );
      final id = await TursoService.execute(
        'INSERT INTO user_nodes (user_id, hardware_id) VALUES (?, ?)',
        [state.userId, hardwareId],
      );
      if (id == null) return 'Failed to claim node.';

      // Update local state
      final updatedIds = [...state.allowedHardwareIds, hardwareId];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKeyHardwareIds, updatedIds);

      state = state.copyWith(allowedHardwareIds: updatedIds);

      return null; // success
    } catch (e) {
      return 'Error claiming node: ${e.toString()}';
    }
  }

  /// Re-fetch the user's allowed hardware IDs from Turso.
  ///
  /// Call this before loading the device list to ensure the list is
  /// up-to-date (e.g. after another user claimed a node that was
  /// previously linked to this account).
  Future<void> refreshHardwareIds() async {
    if (!state.isLoggedIn || state.userId == null) return;
    try {
      final rows = await TursoService.query(
        'SELECT hardware_id FROM user_nodes WHERE user_id = ?',
        [state.userId],
      );
      final ids = rows.map((r) => r['hardware_id'] as String).toList();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKeyHardwareIds, ids);

      state = state.copyWith(allowedHardwareIds: ids);
    } on TursoException catch (e) {
      // ignore: avoid_print
      print('[Auth] refreshHardwareIds failed: $e');
    } catch (e) {
      // ignore: avoid_print
      print('[Auth] refreshHardwareIds unexpected error: $e');
    }
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
  // Registration
  // ---------------------------------------------------------------------------

  /// Create a new user account and auto-login.
  ///
  /// Returns `null` on success, or an error message on failure.
  Future<String?> register(String username, String password) async {
    try {
      // Check Turso connectivity
      String? connError;
      final connected = await TursoService.checkConnection(
        onError: (msg) => connError = msg,
      );
      if (!connected) {
        return connError ?? 'Cannot reach the database.';
      }

      // Check if username already exists
      final existing = await TursoService.query(
        'SELECT id FROM users WHERE username = ?',
        [username],
      );
      if (existing.isNotEmpty) {
        return 'Username already taken.';
      }

      // Hash password and insert
      final hashed = _hashPassword(password);
      final id = await TursoService.execute(
        'INSERT INTO users (username, password) VALUES (?, ?)',
        [username, hashed],
      );

      if (id == null) {
        return 'Failed to create account. Database may not have write permissions.';
      }

      // Auto-login after registration
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyUsername, username);
      await prefs.setInt(_prefsKeyUserId, id);
      await prefs.setStringList(_prefsKeyHardwareIds, []);

      state = AuthState.authenticated(
        username: username,
        userId: id,
        allowedHardwareIds: [],
      );

      return null; // success
    } on TursoException catch (e) {
      return _tursoErrorMessage(e);
    } catch (e) {
      return 'Registration error: ${e.toString()}';
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Map a [TursoException] to a user-friendly message.
  static String _tursoErrorMessage(TursoException e) {
    switch (e.type) {
      case TursoErrorType.auth:
        return 'Database authentication failed. Check your Turso token configuration.';
      case TursoErrorType.network:
        return 'Cannot reach the database. Check your internet connection.';
      case TursoErrorType.timeout:
        return 'Database is not responding. Try again in a moment.';
      case TursoErrorType.sql:
        return 'A database error occurred. Please try again.';
      case TursoErrorType.parse:
        return 'Unexpected response from the database.';
      case TursoErrorType.unknown:
        return 'A database error occurred: ${e.message}';
    }
  }

  /// Compute SHA-256 hex digest of [input].
  static String _hashPassword(String input) {
    final digest = SHA256Digest().process(utf8.encode(input));
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
