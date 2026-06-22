import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/turso_service.dart';
import '../auth/auth_controller.dart';
import '../auth/models/user_session.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Aggregate dashboard data fetched from Turso.
class HomeState {
  /// Total number of devices for this user.
  final int deviceCount;

  /// Number of active alerts across all user devices.
  final int alertCount;

  /// Average communication delivery rate (0–100), or null if no data.
  final double? averageDeliveryRate;

  /// Whether data is currently being loaded.
  final bool busy;

  /// Error message, or null if no error.
  final String? error;

  const HomeState({
    this.deviceCount = 0,
    this.alertCount = 0,
    this.averageDeliveryRate,
    this.busy = false,
    this.error,
  });

  HomeState copyWith({
    int? deviceCount,
    int? alertCount,
    double? averageDeliveryRate,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return HomeState(
      deviceCount: deviceCount ?? this.deviceCount,
      alertCount: alertCount ?? this.alertCount,
      averageDeliveryRate: averageDeliveryRate ?? this.averageDeliveryRate,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final homeControllerProvider =
    StateNotifierProvider<HomeController, HomeState>((ref) {
  return HomeController(ref);
});

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

/// Fetches aggregate dashboard data from Turso for the authenticated user.
///
/// Watches [authControllerProvider] reactively — when the user logs in or
/// the session is restored, data loads automatically.
class HomeController extends StateNotifier<HomeState> {
  final Ref _ref;

  HomeController(this._ref) : super(const HomeState()) {
    // React to auth changes: load data when user logs in, reset on logout.
    _ref.listen(authControllerProvider, (AuthState? prev, AuthState next) {
      if (next.isLoggedIn && next.allowedHardwareIds.isNotEmpty) {
        loadDashboard();
      } else if (!next.isLoggedIn) {
        state = const HomeState();
      }
    });

    // Load immediately if already logged in (controller created after auth).
    final initialAuth = _ref.read(authControllerProvider);
    if (initialAuth.isLoggedIn && initialAuth.allowedHardwareIds.isNotEmpty) {
      Future.microtask(() => loadDashboard());
    }
  }

  /// Fetch all dashboard aggregates from Turso.
  Future<void> loadDashboard() async {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isLoggedIn || auth.allowedHardwareIds.isEmpty) {
      state = const HomeState();
      return;
    }

    state = state.copyWith(busy: true, clearError: true);

    try {
      final ids = auth.allowedHardwareIds;
      final placeholders = ids.map((_) => '?').join(',');

      // Run each query independently so a single failure doesn't wipe
      // all results. Each query returns null on failure.
      final results = await Future.wait([
        _safeQuery(
          'SELECT COUNT(*) AS count FROM nodes WHERE hardware_id IN ($placeholders)',
          ids,
        ),
        _safeQuery(
          '''SELECT COUNT(*) AS count FROM alerts
             WHERE hardware_id IN ($placeholders) AND status = 'active' ''',
          ids,
        ),
        _safeQuery(
          'SELECT AVG(delivery_rate) AS avg_rate FROM communication_health WHERE hardware_id IN ($placeholders)',
          ids,
        ),
      ]);

      final deviceCount = (results[0]?.isNotEmpty == true
          ? (results[0]![0]['count'] as num?)?.toInt()
          : 0) ?? 0;

      final alertCount = (results[1]?.isNotEmpty == true
          ? (results[1]![0]['count'] as num?)?.toInt()
          : 0) ?? 0;

      double? avgRate;
      if (results[2]?.isNotEmpty == true) {
        final raw = results[2]![0]['avg_rate'];
        if (raw is num) avgRate = raw.toDouble();
      }

      state = HomeState(
        deviceCount: deviceCount,
        alertCount: alertCount,
        averageDeliveryRate: avgRate,
      );
    } catch (e) {
      state = state.copyWith(
        busy: false,
        error: 'Failed to load dashboard: ${e.toString()}',
      );
    }
  }

  /// Refresh dashboard data (used by pull-to-refresh).
  Future<void> refresh() async {
    await loadDashboard();
  }

  /// Run a Turso query that returns null on failure instead of throwing.
  /// This isolates individual aggregate queries so one failure doesn't
  /// prevent the others from completing.
  Future<List<Map<String, dynamic>>?> _safeQuery(
    String sql,
    List<dynamic> args,
  ) async {
    try {
      return await TursoService.query(sql, args);
    } catch (_) {
      return null;
    }
  }
}
