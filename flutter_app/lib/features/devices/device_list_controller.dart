import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/turso_service.dart';
import '../../features/auth/auth_controller.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

/// Health status for a device, computed from telemetry freshness
/// and communication health metrics.
enum DeviceHealth { healthy, warning, critical, offline }

/// A single device shown in the device list.
class DeviceListItem {
  final String hardwareId;
  final String? name;
  final String? location;
  final DateTime? lastSeen;
  final double? deliveryRate;
  final int? lastRssi;
  final double? lastSnr;
  final int? freshnessSeconds;

  const DeviceListItem({
    required this.hardwareId,
    this.name,
    this.location,
    this.lastSeen,
    this.deliveryRate,
    this.lastRssi,
    this.lastSnr,
    this.freshnessSeconds,
  });

  /// Compute health status based on the plan's thresholds.
  DeviceHealth get health {
    final now = DateTime.now();

    // Offline: last_seen > 30 min ago
    if (lastSeen != null) {
      final elapsed = now.difference(lastSeen!).inSeconds;
      if (elapsed > 1800) return DeviceHealth.offline;
    }

    // Critical: delivery_rate < 50% OR freshness > 300s
    if (deliveryRate != null && deliveryRate! < 50) return DeviceHealth.critical;
    if (freshnessSeconds != null && freshnessSeconds! > 300) {
      return DeviceHealth.critical;
    }

    // Warning: delivery_rate < 80% OR freshness > 120s
    if (deliveryRate != null && deliveryRate! < 80) return DeviceHealth.warning;
    if (freshnessSeconds != null && freshnessSeconds! > 120) {
      return DeviceHealth.warning;
    }

    return DeviceHealth.healthy;
  }

  /// Human-readable label for the health status.
  String get healthLabel {
    switch (health) {
      case DeviceHealth.healthy:
        return 'Healthy';
      case DeviceHealth.warning:
        return 'Warning';
      case DeviceHealth.critical:
        return 'Critical';
      case DeviceHealth.offline:
        return 'Offline';
    }
  }

  /// Relative time since last seen.
  String get lastSeenLabel {
    if (lastSeen == null) return 'Never';
    final diff = DateTime.now().difference(lastSeen!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class DeviceListState {
  final List<DeviceListItem> devices;
  final bool busy;
  final String? error;

  const DeviceListState({
    this.devices = const [],
    this.busy = false,
    this.error,
  });

  DeviceListState copyWith({
    List<DeviceListItem>? devices,
    bool? busy,
    String? error,
  }) {
    return DeviceListState(
      devices: devices ?? this.devices,
      busy: busy ?? this.busy,
      error: error,
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final deviceListControllerProvider =
    StateNotifierProvider<DeviceListController, DeviceListState>((ref) {
  return DeviceListController(ref);
});

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class DeviceListController extends StateNotifier<DeviceListState> {
  final Ref _ref;

  DeviceListController(this._ref) : super(const DeviceListState());

  /// Load devices for the currently authenticated user.
  Future<void> loadDevices() async {
    final auth = _ref.read(authControllerProvider);
    // ignore: avoid_print
    print('[DeviceList] auth.isLoggedIn=${auth.isLoggedIn} ids=${auth.allowedHardwareIds}');
    if (!auth.isLoggedIn || auth.allowedHardwareIds.isEmpty) {
      state = const DeviceListState(devices: [], error: 'No devices found for this user.');
      return;
    }

    state = state.copyWith(busy: true, error: null);

    try {
      final hardwareIds = auth.allowedHardwareIds;

      // Build the SQL with the correct number of placeholders
      final placeholders = hardwareIds.map((_) => '?').join(',');
      final sql = '''
        SELECT n.hardware_id, n.name, n.location, n.last_seen,
               ch.delivery_rate, ch.last_rssi, ch.last_snr, ch.freshness_seconds
        FROM nodes n
        LEFT JOIN communication_health ch ON n.hardware_id = ch.hardware_id
        WHERE n.hardware_id IN ($placeholders)
        ORDER BY n.last_seen DESC
      ''';

      // ignore: avoid_print
      print('[DeviceList] query=$sql ids=$hardwareIds');
      final rows = await TursoService.query(sql, hardwareIds);
      // ignore: avoid_print
      print('[DeviceList] rows=${rows.length}');

      final devices = rows.map((r) {
        DateTime? lastSeen;
        if (r['last_seen'] is String) {
          lastSeen = DateTime.tryParse(r['last_seen'] as String);
        }

        return DeviceListItem(
          hardwareId: r['hardware_id'] as String? ?? '',
          name: r['name'] as String?,
          location: r['location'] as String?,
          lastSeen: lastSeen,
          deliveryRate: (r['delivery_rate'] as num?)?.toDouble(),
          lastRssi: r['last_rssi'] as int?,
          lastSnr: (r['last_snr'] as num?)?.toDouble(),
          freshnessSeconds: r['freshness_seconds'] as int?,
        );
      }).toList();

      // ignore: avoid_print
      print('[DeviceList] parsed ${devices.length} devices');
      state = DeviceListState(devices: devices);
    } catch (e) {
      // ignore: avoid_print
      print('[DeviceList] error: $e');
      state = state.copyWith(
        busy: false,
        error: 'Failed to load devices: ${e.toString()}',
      );
    }
  }

  /// Refresh the device list (used by pull-to-refresh).
  Future<void> refresh() async {
    await loadDevices();
  }
}
