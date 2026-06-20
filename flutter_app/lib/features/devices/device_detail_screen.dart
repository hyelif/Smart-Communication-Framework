import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';
import 'device_detail_controller.dart';
import 'widgets/relay_toggle.dart';

/// Device detail screen showing sensor readings, communication health,
/// active alerts, and relay controls for a single node.
class DeviceDetailScreen extends ConsumerStatefulWidget {
  final String hardwareId;
  final String? deviceName;

  const DeviceDetailScreen({
    super.key,
    required this.hardwareId,
    this.deviceName,
  });

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceDetailControllerProvider(widget.hardwareId).notifier).loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceDetailControllerProvider(widget.hardwareId));

    return StitchScaffold(
      body: Column(
        children: [
          _Header(
            hardwareId: widget.hardwareId,
            deviceName: widget.deviceName,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _buildBody(state),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(DeviceDetailState state) {
    if (state.busy && state.readings.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: List.generate(
          5,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: StitchSkeletonPanel(height: 80, lineCount: 2),
          ),
        ),
      );
    }

    if (state.error != null && state.readings.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: StitchEmptyState(
            title: 'Failed to Load',
            subtitle: state.error!,
            icon: Icons.cloud_off_rounded,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(deviceDetailControllerProvider(widget.hardwareId).notifier).loadAll(),
      child: ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          // Comm health card
          if (state.commHealth != null)
            _CommHealthCard(health: state.commHealth!),
          if (state.commHealth != null) const SizedBox(height: 16),

          // Active alerts
          if (state.alerts.isNotEmpty) ...[
            const StitchSectionLabel('Active Alerts', icon: Icons.warning_rounded),
            const SizedBox(height: 10),
            ...state.alerts.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AlertCard(alert: a),
                )),
            const SizedBox(height: 16),
          ],

          // Relay controls
          const StitchSectionLabel('Relay Control', icon: Icons.power_settings_new_rounded),
          const SizedBox(height: 10),
          RelayToggle(
            hardwareId: widget.hardwareId,
            relayId: 0,
            label: 'Relay 0',
            isOn: false,
            onToggle: (on) => _handleToggle(0, on),
          ),
          const SizedBox(height: 8),
          RelayToggle(
            hardwareId: widget.hardwareId,
            relayId: 1,
            label: 'Relay 1',
            isOn: false,
            onToggle: (on) => _handleToggle(1, on),
          ),
          const SizedBox(height: 16),

          // Sensor readings
          const StitchSectionLabel('Recent Readings', icon: Icons.sensors_rounded),
          const SizedBox(height: 10),
          if (state.readings.isEmpty)
            const StitchPanel(
              child: Text('No sensor readings yet.',
                  style: TextStyle(color: StitchColors.onSurfaceVariant)),
            )
          else
            ...state.readings.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ReadingRow(reading: r),
                )),
        ],
      ),
    );
  }

  Future<void> _handleToggle(int relayId, bool turnOn) async {
    final controller =
        ref.read(deviceDetailControllerProvider(widget.hardwareId).notifier);
    final error = await controller.toggleRelay(relayId, turnOn);
    if (mounted && error != null) {
      showStitchMessage(context, error, isError: true);
    } else if (mounted) {
      showStitchMessage(
        context,
        'Relay $relayId ${turnOn ? 'ON' : 'OFF'} command sent.',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final String hardwareId;
  final String? deviceName;
  final VoidCallback onBack;

  const _Header({
    required this.hardwareId,
    this.deviceName,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: StitchColors.surfaceLowest,
        border: Border(
          bottom: BorderSide(color: StitchColors.outlineVariant),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: onBack,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    deviceName ?? hardwareId,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    hardwareId,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: StitchColors.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Comm Health Card
// ---------------------------------------------------------------------------

class _CommHealthCard extends StatelessWidget {
  final CommHealth health;

  const _CommHealthCard({required this.health});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rate = health.deliveryRate ?? 100;
    final rateColor = rate >= 80
        ? const Color(0xFF4CAF50)
        : (rate >= 50 ? const Color(0xFFFFA726) : const Color(0xFFEF5350));

    return StitchPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StitchSectionLabel('Communication Health',
              icon: Icons.wifi_rounded),
          const SizedBox(height: 16),
          Row(
            children: [
              // Delivery rate gauge
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CircularProgressIndicator(
                        value: rate / 100,
                        strokeWidth: 6,
                        backgroundColor: StitchColors.surfaceLow,
                        valueColor: AlwaysStoppedAnimation(rateColor),
                      ),
                    ),
                    Text(
                      '${rate.round()}%',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: rateColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [
                    _CommRow(
                        label: 'RSSI',
                        value: health.lastRssi != null
                            ? '${health.lastRssi} dBm'
                            : '--'),
                    const SizedBox(height: 6),
                    _CommRow(
                        label: 'SNR',
                        value: health.lastSnr != null
                            ? '${health.lastSnr!.toStringAsFixed(1)} dB'
                            : '--'),
                    const SizedBox(height: 6),
                    _CommRow(
                        label: 'Freshness',
                        value: health.freshnessSeconds > 0
                            ? '${health.freshnessSeconds}s'
                            : '--'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CommRow(
            label: 'Packets',
            value: '${health.totalReceived}/${health.totalExpected}',
          ),
        ],
      ),
    );
  }
}

class _CommRow extends StatelessWidget {
  final String label;
  final String value;

  const _CommRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: StitchColors.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Alert Card
// ---------------------------------------------------------------------------

class _AlertCard extends StatelessWidget {
  final DeviceAlert alert;

  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (alert.severity) {
      'critical' => (const Color(0xFFEF5350), Icons.error_rounded),
      'warning' => (const Color(0xFFFFA726), Icons.warning_rounded),
      _ => (const Color(0xFF42A5F5), Icons.info_rounded),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (alert.sensorKey.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    alert.sensorKey,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: StitchColors.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reading Row
// ---------------------------------------------------------------------------

class _ReadingRow extends StatelessWidget {
  final SensorReading reading;

  const _ReadingRow({required this.reading});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StitchPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: StitchColors.surfaceContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _sensorIcon(reading.sensor),
              size: 18,
              color: StitchColors.secondary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reading.sensor.toUpperCase(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Pin ${reading.pin}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: StitchColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            reading.value,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
        ],
      ),
    );
  }

  IconData _sensorIcon(String sensor) {
    switch (sensor.toLowerCase()) {
      case 'temperature':
      case 'temp':
        return Icons.thermostat_rounded;
      case 'humidity':
      case 'hum':
        return Icons.water_drop_rounded;
      case 'ph':
        return Icons.science_rounded;
      case 'tds':
      case 'ec':
        return Icons.opacity_rounded;
      case 'turbidity':
        return Icons.blur_on_rounded;
      case 'rain':
        return Icons.umbrella_rounded;
      case 'water_temp':
      case 'watertemperature':
        return Icons.bathroom_rounded;
      default:
        return Icons.sensors_rounded;
    }
  }
}
