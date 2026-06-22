import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/turso_service.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/models/user_session.dart';

// ---------------------------------------------------------------------------
// Health
// ---------------------------------------------------------------------------

/// Health status for a device, computed from telemetry freshness
/// and communication health metrics.
enum DeviceHealth { healthy, warning, critical, offline }

// ---------------------------------------------------------------------------
// Device List Item
// ---------------------------------------------------------------------------

/// A single device shown in the node selector.
class DeviceListItem {
  final String hardwareId;
  final String? name;
  final String? location;
  final DateTime? lastSeen;
  final double? deliveryRate;
  final int? lastRssi;
  final double? lastSnr;
  final int? freshnessSeconds;
  final String? lastReading;
  final String? lastSensorKey;

  const DeviceListItem({
    required this.hardwareId,
    this.name,
    this.location,
    this.lastSeen,
    this.deliveryRate,
    this.lastRssi,
    this.lastSnr,
    this.freshnessSeconds,
    this.lastReading,
    this.lastSensorKey,
  });

  String get deviceType {
    final n = (name ?? '').toLowerCase();
    if (n.contains('hydroponic') || n.contains('farm') || n.contains('hydro')) return 'hydroponic';
    if (n.contains('weather') || n.contains('rain') || n.contains('climate')) return 'weather';
    if (n.contains('tank') || n.contains('water') || n.contains('reservoir')) return 'tank';
    if (n.contains('gateway') || n.contains('hq') || n.contains('lora')) return 'gateway';
    return 'node';
  }

  String get deviceEmoji {
    switch (deviceType) {
      case 'hydroponic': return '💧';
      case 'weather': return '🌤';
      case 'tank': return '🛢';
      case 'gateway': return '📡';
      default: return '🔌';
    }
  }

  /// Short label for the node selector (first 4 chars of hardware ID or name).
  String get shortLabel {
    if (name != null && name!.isNotEmpty) {
      return name!.length > 8 ? '${name!.substring(0, 8)}…' : name!;
    }
    return hardwareId.length > 4 ? hardwareId.substring(0, 4) : hardwareId;
  }

  DeviceHealth get health {
    final now = DateTime.now();
    if (lastSeen != null) {
      final elapsed = now.difference(lastSeen!).inSeconds;
      if (elapsed > 1800) return DeviceHealth.offline;
    }
    if (deliveryRate != null && deliveryRate! < 50) return DeviceHealth.critical;
    if (freshnessSeconds != null && freshnessSeconds! > 300) return DeviceHealth.critical;
    if (deliveryRate != null && deliveryRate! < 80) return DeviceHealth.warning;
    if (freshnessSeconds != null && freshnessSeconds! > 120) return DeviceHealth.warning;
    return DeviceHealth.healthy;
  }

  String get healthLabel {
    switch (health) {
      case DeviceHealth.healthy: return 'Healthy';
      case DeviceHealth.warning: return 'Warning';
      case DeviceHealth.critical: return 'Critical';
      case DeviceHealth.offline: return 'Offline';
    }
  }

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
// Sensor Reading (for the grid)
// ---------------------------------------------------------------------------

/// A single sensor reading displayed in the 2-column grid.
class DeviceSensorReading {
  final String sensor;
  final String value;
  final int pin;
  final DateTime? createdAt;

  /// Historical values for the sparkline chart (newest first).
  final List<double> history;

  const DeviceSensorReading({
    required this.sensor,
    required this.value,
    this.pin = 0,
    this.createdAt,
    this.history = const [],
  });

  /// Human-readable label for the sensor.
  String get label {
    switch (sensor.toLowerCase()) {
      case 'temperature': case 'temp': return 'Temperature';
      case 'humidity': case 'hum': return 'Humidity';
      case 'ph': return 'pH';
      case 'tds': case 'ec': return 'TDS';
      case 'turbidity': return 'Turbidity';
      case 'rain': return 'Rain';
      case 'water_temp': case 'watertemperature': return 'Water Temp';
      default: return sensor;
    }
  }

  /// Unit string for the sensor.
  String get unit {
    switch (sensor.toLowerCase()) {
      case 'temperature': case 'temp': return '°C';
      case 'humidity': case 'hum': return '%';
      case 'ph': return 'pH';
      case 'tds': case 'ec': return 'ppm';
      case 'turbidity': return 'NTU';
      case 'rain': return 'mm';
      case 'water_temp': case 'watertemperature': return '°C';
      default: return '';
    }
  }

  /// Icon for the sensor type.
  String get emoji {
    switch (sensor.toLowerCase()) {
      case 'temperature': case 'temp': return '🌡';
      case 'humidity': case 'hum': return '💧';
      case 'ph': return '🧪';
      case 'tds': case 'ec': return '🧂';
      case 'turbidity': return '🌫';
      case 'rain': return '🌧';
      case 'water_temp': case 'watertemperature': return '🌊';
      default: return '📡';
    }
  }
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// A single data point for a chart series.
class ChartPoint {
  final DateTime time;
  final double value;
  const ChartPoint({required this.time, required this.value});
}

/// Chart data for one sensor type.
class SensorChartData {
  final String sensor;
  final String label;
  final String unit;
  final Color color;
  final List<ChartPoint> points;

  const SensorChartData({
    required this.sensor,
    required this.label,
    required this.unit,
    required this.color,
    required this.points,
  });
}

class DeviceListState {
  final List<DeviceListItem> devices;
  final String? selectedHardwareId;
  final List<DeviceSensorReading> sensorReadings;
  final bool busy;
  final bool refreshing;
  final bool sensorsBusy;
  final String? error;
  final String? sensorError;
  final List<SensorChartData> chartData;
  final bool chartsBusy;
  final bool showCharts;

  const DeviceListState({
    this.devices = const [],
    this.selectedHardwareId,
    this.sensorReadings = const [],
    this.busy = false,
    this.refreshing = false,
    this.sensorsBusy = false,
    this.error,
    this.sensorError,
    this.chartData = const [],
    this.chartsBusy = false,
    this.showCharts = false,
  });

  DeviceListState copyWith({
    List<DeviceListItem>? devices,
    String? selectedHardwareId,
    List<DeviceSensorReading>? sensorReadings,
    bool? busy,
    bool? refreshing,
    bool? sensorsBusy,
    String? error,
    String? sensorError,
    List<SensorChartData>? chartData,
    bool? chartsBusy,
    bool? showCharts,
    bool clearError = false,
    bool clearSensorError = false,
  }) {
    return DeviceListState(
      devices: devices ?? this.devices,
      selectedHardwareId: selectedHardwareId ?? this.selectedHardwareId,
      sensorReadings: sensorReadings ?? this.sensorReadings,
      busy: busy ?? this.busy,
      refreshing: refreshing ?? this.refreshing,
      sensorsBusy: sensorsBusy ?? this.sensorsBusy,
      error: clearError ? null : (error ?? this.error),
      sensorError: clearSensorError ? null : (sensorError ?? this.sensorError),
      chartData: chartData ?? this.chartData,
      chartsBusy: chartsBusy ?? this.chartsBusy,
      showCharts: showCharts ?? this.showCharts,
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

  DeviceListController(this._ref) : super(const DeviceListState()) {
    _ref.listen(authControllerProvider, (AuthState? prev, AuthState next) {
      if (next.isLoggedIn) {
        loadDevices();
      } else if (!next.isLoggedIn) {
        state = const DeviceListState();
      }
    });

    // If auth is already logged-in when this controller is first created
    // (e.g. user navigates to Devices tab after login), the listener above
    // won't fire because the value hasn't changed. Load devices immediately.
    final initialAuth = _ref.read(authControllerProvider);
    if (initialAuth.isLoggedIn) {
      // Use a post-frame callback to avoid calling loadDevices() during
      // the provider's constructor (which would be out of the build phase).
      Future.microtask(() => loadDevices());
    }
  }

  /// Load devices for the currently authenticated user.
  Future<void> loadDevices() async {
    final auth = _ref.read(authControllerProvider);
    if (!auth.isLoggedIn || auth.allowedHardwareIds.isEmpty) {
      state = const DeviceListState(devices: [], error: 'No devices found for this user.');
      return;
    }

    // Use `refreshing` (keeps current data visible) if we already have devices,
    // `busy` (shows skeleton) only on initial load.
    final hasData = state.devices.isNotEmpty;
    state = state.copyWith(
      busy: !hasData,
      refreshing: hasData,
      clearError: true,
    );

    try {
      final hardwareIds = auth.allowedHardwareIds;
      final placeholders = hardwareIds.map((_) => '?').join(',');
      final sql = '''
        SELECT n.hardware_id, n.name, n.location, n.last_seen,
               ch.delivery_rate, ch.last_rssi, ch.last_snr, ch.freshness_seconds,
               (SELECT sd.sensor || ':' || sd.value
                FROM sensor_data sd
                JOIN sensor_readings sr ON sd.reading_id = sr.id
                WHERE sr.hardware_id = n.hardware_id
                ORDER BY sr.created_at DESC LIMIT 1) AS last_reading
        FROM nodes n
        LEFT JOIN communication_health ch ON n.hardware_id = ch.hardware_id
        WHERE n.hardware_id IN ($placeholders)
        ORDER BY n.last_seen DESC
      ''';

      final rows = await TursoService.query(sql, hardwareIds);

      final devices = rows.map((r) {
        DateTime? lastSeen;
        if (r['last_seen'] is String) {
          lastSeen = DateTime.tryParse(r['last_seen'] as String);
        }
        String? lastReading;
        String? lastSensorKey;
        final raw = r['last_reading'] as String?;
        if (raw != null && raw.contains(':')) {
          final parts = raw.split(':');
          lastSensorKey = parts[0];
          lastReading = '${_sensorLabel(lastSensorKey)}: ${parts.sublist(1).join(':')}';
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
          lastReading: lastReading,
          lastSensorKey: lastSensorKey,
        );
      }).toList();

      // Auto-select first device if none selected or selected is gone
      final currentSelected = state.selectedHardwareId;
      final validSelection = devices.any((d) => d.hardwareId == currentSelected);
      final newSelected = validSelection ? currentSelected : (devices.isNotEmpty ? devices.first.hardwareId : null);

      state = DeviceListState(
        devices: devices,
        selectedHardwareId: newSelected,
        refreshing: false,
      );

      // Load sensor data for the selected device
      if (newSelected != null) {
        await loadSensorData(newSelected);
      }
    } catch (e) {
      state = state.copyWith(
        busy: false,
        error: 'Failed to load devices: ${e.toString()}',
      );
    }
  }

  /// Select a node and load its sensor readings.
  Future<void> selectNode(String hardwareId) async {
    if (hardwareId == state.selectedHardwareId) return;
    // Keep old sensor data visible while loading new data.
    // Only clear if switching to a different node.
    state = state.copyWith(
      selectedHardwareId: hardwareId,
      sensorReadings: const [],
      clearSensorError: true,
    );
    await loadSensorData(hardwareId);
  }

  /// Load latest sensor readings for a specific node.
  Future<void> loadSensorData(String hardwareId) async {
    // Only show loading state on initial load, not on refresh
    if (state.sensorReadings.isEmpty) {
      state = state.copyWith(sensorsBusy: true);
    }

    try {
      final rows = await TursoService.query(
        '''SELECT sd.sensor, sd.value, sd.pin, sr.created_at
           FROM sensor_data sd
           JOIN sensor_readings sr ON sd.reading_id = sr.id
           WHERE sr.hardware_id = ?
           ORDER BY sr.created_at DESC
           LIMIT 50''',
        [hardwareId],
      );

      // Group all rows by sensor, keeping newest first
      final Map<String, List<Map<String, dynamic>>> grouped = {};
      for (final r in rows) {
        final sensor = (r['sensor'] as String? ?? '').toLowerCase();
        if (sensor.isEmpty) continue;
        grouped.putIfAbsent(sensor, () => []).add(r);
      }

      // Build readings with history for sparkline
      final readings = <DeviceSensorReading>[];
      for (final entry in grouped.entries) {
        final sensor = entry.key;
        final sensorRows = entry.value;
        if (sensorRows.isEmpty) continue;

        // First row is the latest (DESC order)
        final latest = sensorRows[0];
        DateTime? createdAt;
        if (latest['created_at'] is String) {
          createdAt = DateTime.tryParse(latest['created_at'] as String);
        }

        // Extract history values for sparkline (up to 15 points, reverse to chronological)
        final history = sensorRows
            .take(15)
            .map((r) => double.tryParse(r['value']?.toString() ?? ''))
            .whereType<double>()
            .toList()
            .reversed
            .toList();

        readings.add(DeviceSensorReading(
          sensor: sensor,
          value: latest['value'] as String? ?? '',
          pin: (latest['pin'] as num?)?.toInt() ?? 0,
          createdAt: createdAt,
          history: history,
        ));
      }

      state = state.copyWith(
        sensorReadings: readings,
        sensorsBusy: false,
        clearSensorError: true,
      );
    } on TursoException catch (e) {
      state = state.copyWith(
        sensorsBusy: false,
        sensorError: 'Failed to load sensor data: ${e.message}',
      );
    } catch (e) {
      state = state.copyWith(
        sensorsBusy: false,
        sensorError: 'Failed to load sensor data: ${e.toString()}',
      );
    }
  }

  /// Refresh everything (full reload).
  Future<void> refresh() async {
    await loadDevices();
  }

  /// Lightweight refresh — only reloads sensor data for the selected node.
  Future<void> refreshSensors() async {
    final hwId = state.selectedHardwareId;
    if (hwId != null) {
      await loadSensorData(hwId);
    }
  }

  /// Toggle chart visibility and load data if needed.
  Future<void> toggleCharts() async {
    final show = !state.showCharts;
    state = state.copyWith(showCharts: show);
    if (show && state.chartData.isEmpty && state.selectedHardwareId != null) {
      await loadChartData(state.selectedHardwareId!);
    }
  }

  /// Load historical sensor data for charts (last 24 hours).
  Future<void> loadChartData(String hardwareId) async {
    state = state.copyWith(chartsBusy: true);
    try {
      final rows = await TursoService.query(
        '''SELECT sd.sensor, sd.value, sr.created_at
           FROM sensor_data sd
           JOIN sensor_readings sr ON sd.reading_id = sr.id
           WHERE sr.hardware_id = ?
             AND sr.created_at > datetime('now', '-24 hours')
           ORDER BY sr.created_at ASC''',
        [hardwareId],
      );

      // Group points by sensor
      final Map<String, List<ChartPoint>> grouped = {};
      for (final r in rows) {
        final sensor = (r['sensor'] as String? ?? '').toLowerCase();
        if (sensor.isEmpty) continue;
        final value = double.tryParse(r['value']?.toString() ?? '');
        if (value == null) continue;
        DateTime? time;
        if (r['created_at'] is String) {
          time = DateTime.tryParse(r['created_at'] as String);
        }
        if (time == null) continue;
        grouped.putIfAbsent(sensor, () => []).add(ChartPoint(time: time, value: value));
      }

      // Build chart data for each sensor that has enough points
      final chartData = <SensorChartData>[];
      for (final entry in grouped.entries) {
        if (entry.value.length < 2) continue; // need at least 2 points for a line
        chartData.add(SensorChartData(
          sensor: entry.key,
          label: _sensorLabel(entry.key),
          unit: _sensorUnit(entry.key),
          color: _sensorColor(entry.key),
          points: entry.value,
        ));
      }

      state = state.copyWith(chartData: chartData, chartsBusy: false);
    } catch (e) {
      state = state.copyWith(chartsBusy: false);
    }
  }
}

/// Map a sensor key to a human-readable label.
String _sensorLabel(String key) {
  switch (key.toLowerCase()) {
    case 'temperature': case 'temp': return 'Temp';
    case 'humidity': case 'hum': return 'Humidity';
    case 'ph': return 'pH';
    case 'tds': case 'ec': return 'TDS';
    case 'turbidity': return 'Turbidity';
    case 'rain': return 'Rain';
    case 'water_temp': case 'watertemperature': return 'Water';
    default: return key;
  }
}

String _sensorUnit(String key) {
  switch (key.toLowerCase()) {
    case 'temperature': case 'temp': return '°C';
    case 'humidity': case 'hum': return '%';
    case 'ph': return 'pH';
    case 'tds': case 'ec': return 'ppm';
    case 'turbidity': return 'NTU';
    case 'rain': return 'mm';
    case 'water_temp': case 'watertemperature': return '°C';
    default: return '';
  }
}

Color _sensorColor(String key) {
  switch (key.toLowerCase()) {
    case 'temperature': case 'temp': return const Color(0xFFFF6B6B);
    case 'humidity': case 'hum': return const Color(0xFF4FC3F7);
    case 'ph': return const Color(0xFFCE93D8);
    case 'tds': case 'ec': return const Color(0xFFFFB74D);
    case 'turbidity': return const Color(0xFF81C784);
    case 'rain': return const Color(0xFF4DD0E1);
    case 'water_temp': case 'watertemperature': return const Color(0xFF4FC3F7);
    default: return const Color(0xFF00F5FF);
  }
}
