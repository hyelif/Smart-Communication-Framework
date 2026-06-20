import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/turso_service.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class SensorReading {
  final String sensor;
  final String value;
  final int pin;
  final DateTime? createdAt;

  const SensorReading({
    required this.sensor,
    required this.value,
    required this.pin,
    this.createdAt,
  });
}

class CommHealth {
  final double? deliveryRate;
  final int totalExpected;
  final int totalReceived;
  final int sequenceGaps;
  final int freshnessSeconds;
  final int? lastRssi;
  final double? lastSnr;

  const CommHealth({
    this.deliveryRate,
    this.totalExpected = 0,
    this.totalReceived = 0,
    this.sequenceGaps = 0,
    this.freshnessSeconds = 0,
    this.lastRssi,
    this.lastSnr,
  });
}

class DeviceAlert {
  final int id;
  final String sensorKey;
  final String severity;
  final String message;
  final DateTime? createdAt;

  const DeviceAlert({
    required this.id,
    required this.sensorKey,
    required this.severity,
    required this.message,
    this.createdAt,
  });
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class DeviceDetailState {
  final List<SensorReading> readings;
  final CommHealth? commHealth;
  final List<DeviceAlert> alerts;
  final bool busy;
  final String? error;

  const DeviceDetailState({
    this.readings = const [],
    this.commHealth,
    this.alerts = const [],
    this.busy = false,
    this.error,
  });

  DeviceDetailState copyWith({
    List<SensorReading>? readings,
    CommHealth? commHealth,
    List<DeviceAlert>? alerts,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return DeviceDetailState(
      readings: readings ?? this.readings,
      commHealth: commHealth ?? this.commHealth,
      alerts: alerts ?? this.alerts,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final deviceDetailControllerProvider = StateNotifierProvider.family<
    DeviceDetailController, DeviceDetailState, String>(
  (ref, hardwareId) => DeviceDetailController(hardwareId),
);

// ---------------------------------------------------------------------------
// Controller
// ---------------------------------------------------------------------------

class DeviceDetailController extends StateNotifier<DeviceDetailState> {
  final String hardwareId;

  DeviceDetailController(this.hardwareId) : super(const DeviceDetailState());

  /// Load all data for this device.
  Future<void> loadAll() async {
    state = state.copyWith(busy: true, clearError: true);

    try {
      await Future.wait([
        _loadReadings(),
        _loadCommHealth(),
        _loadAlerts(),
      ]);

      state = state.copyWith(busy: false);
    } catch (e) {
      state = state.copyWith(
        busy: false,
        error: 'Failed to load device data: ${e.toString()}',
      );
    }
  }

  Future<void> _loadReadings() async {
    final rows = await TursoService.query(
      '''SELECT sd.sensor, sd.value, sd.pin, sr.created_at
         FROM sensor_data sd
         JOIN sensor_readings sr ON sd.reading_id = sr.id
         WHERE sr.hardware_id = ?
         ORDER BY sr.created_at DESC
         LIMIT 20''',
      [hardwareId],
    );

    final readings = rows.map((r) {
      DateTime? createdAt;
      if (r['created_at'] is String) {
        createdAt = DateTime.tryParse(r['created_at'] as String);
      }
      return SensorReading(
        sensor: r['sensor'] as String? ?? 'unknown',
        value: r['value'] as String? ?? '',
        pin: (r['pin'] as num?)?.toInt() ?? 0,
        createdAt: createdAt,
      );
    }).toList();

    state = state.copyWith(readings: readings);
  }

  Future<void> _loadCommHealth() async {
    final rows = await TursoService.query(
      '''SELECT delivery_rate, total_expected, total_received,
                sequence_gaps, freshness_seconds, last_rssi, last_snr
         FROM communication_health
         WHERE hardware_id = ?''',
      [hardwareId],
    );

    if (rows.isNotEmpty) {
      final r = rows[0];
      state = state.copyWith(
        commHealth: CommHealth(
          deliveryRate: (r['delivery_rate'] as num?)?.toDouble(),
          totalExpected: (r['total_expected'] as num?)?.toInt() ?? 0,
          totalReceived: (r['total_received'] as num?)?.toInt() ?? 0,
          sequenceGaps: (r['sequence_gaps'] as num?)?.toInt() ?? 0,
          freshnessSeconds: (r['freshness_seconds'] as num?)?.toInt() ?? 0,
          lastRssi: r['last_rssi'] as int?,
          lastSnr: (r['last_snr'] as num?)?.toDouble(),
        ),
      );
    }
  }

  Future<void> _loadAlerts() async {
    final rows = await TursoService.query(
      '''SELECT id, sensor_key, severity, message, created_at
         FROM alerts
         WHERE hardware_id = ? AND status = 'active'
         ORDER BY created_at DESC''',
      [hardwareId],
    );

    final alerts = rows.map((r) {
      DateTime? createdAt;
      if (r['created_at'] is String) {
        createdAt = DateTime.tryParse(r['created_at'] as String);
      }
      return DeviceAlert(
        id: (r['id'] as num?)?.toInt() ?? 0,
        sensorKey: r['sensor_key'] as String? ?? '',
        severity: r['severity'] as String? ?? 'warning',
        message: r['message'] as String? ?? '',
        createdAt: createdAt,
      );
    }).toList();

    state = state.copyWith(alerts: alerts);
  }

  /// Send a relay command to Turso.
  Future<String?> toggleRelay(int relayId, bool turnOn) async {
    final action = turnOn ? 'ON' : 'OFF';

    final id = await TursoService.execute(
      '''INSERT INTO relay_commands (hardware_id, relay_id, action, status)
         VALUES (?, ?, ?, 'pending')''',
      [hardwareId, relayId, action],
    );

    if (id == null) {
      return 'Failed to send relay command.';
    }

    return null; // success
  }
}
