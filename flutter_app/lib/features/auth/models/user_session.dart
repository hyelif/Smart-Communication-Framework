/// Represents the current authenticated user session.
///
/// Stored in SharedPreferences and loaded on app startup.
/// [allowedHardwareIds] restricts which nodes this user can see/control.
class AuthState {
  /// Whether the user is currently logged in.
  final bool isLoggedIn;

  /// The username of the authenticated user.
  final String? username;

  /// The internal user ID from the Turso `users` table.
  final int? userId;

  /// The list of hardware IDs this user is allowed to access.
  ///
  /// Populated from the `user_nodes` table at login time.
  final List<String> allowedHardwareIds;

  const AuthState({
    this.isLoggedIn = false,
    this.username,
    this.userId,
    this.allowedHardwareIds = const [],
  });

  /// Create a logged-in state.
  const AuthState.authenticated({
    required this.username,
    required this.userId,
    required this.allowedHardwareIds,
  }) : isLoggedIn = true;

  /// Create a logged-out state.
  const AuthState.unauthenticated()
      : isLoggedIn = false,
        username = null,
        userId = null,
        allowedHardwareIds = const [];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthState &&
          isLoggedIn == other.isLoggedIn &&
          username == other.username &&
          userId == other.userId &&
          listEquals(allowedHardwareIds, other.allowedHardwareIds);

  @override
  int get hashCode =>
      Object.hash(isLoggedIn, username, userId, Object.hashAll(allowedHardwareIds));

  @override
  String toString() =>
      'AuthState(isLoggedIn: $isLoggedIn, username: $username, '
      'userId: $userId, nodes: ${allowedHardwareIds.length})';
}

/// Equality helper for lists used in [AuthState.==].
bool listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
