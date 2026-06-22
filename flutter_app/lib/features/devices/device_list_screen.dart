import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fl_chart/fl_chart.dart';

import '../../services/turso_service.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';
import '../../widgets/responsive_layout.dart';
import '../auth/auth_controller.dart';
import 'device_list_controller.dart';

/// Device screen showing a node selector floating island at the top
/// and a 2-column sensor reading grid below for the selected node.
class DeviceListScreen extends ConsumerStatefulWidget {
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;

  const DeviceListScreen({
    super.key,
    required this.activeTabListenable,
    required this.tabIndex,
  });

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Full device list refresh every 60s (keeps node list current)
    // Sensor-only refresh every 15s (lightweight, no UI flash)
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      ref.read(deviceListControllerProvider.notifier).refreshSensors();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _showClaimNodeSheet() async {
    final hardwareIdController = TextEditingController();
    final claimed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StitchColors.surfaceContainer,
        shape: const RoundedRectangleBorder(borderRadius: StitchRadius.cardBorder),
        title: const Text('Claim Node', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: hardwareIdController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Hardware ID',
            hintText: 'e.g. 000090F74BDF948C',
            prefixIcon: Icon(Icons.memory_rounded),
          ),
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontFamily: 'SpaceGrotesk', fontWeight: FontWeight.w700, letterSpacing: 1.2),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          StitchPrimaryButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CLAIM'),
          ),
        ],
      ),
    );

    if (claimed != true || !mounted) return;
    final hwId = hardwareIdController.text.trim().toUpperCase();
    if (hwId.isEmpty) return;
    if (!RegExp(r'^[0-9A-F]{12,16}$').hasMatch(hwId)) {
      if (mounted) showStitchMessage(context, 'Invalid hardware ID format.', isError: true);
      return;
    }

    final error = await ref.read(authControllerProvider.notifier).claimNode(hwId);
    if (!mounted) return;

    if (error != null) {
      showStitchMessage(context, error, isError: true);
    } else {
      showStitchMessage(context, 'Node $hwId claimed successfully!');
      await ref.read(deviceListControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceListControllerProvider);

    return StitchScaffold(
      body: _buildBody(state),
    );
  }

  Widget _buildBody(DeviceListState state) {
    if (state.busy && state.devices.isEmpty) {
      return _buildLoading();
    }
    if (state.error != null && state.devices.isEmpty) {
      return _buildError(state.error!);
    }
    if (state.devices.isEmpty) {
      return _buildEmpty();
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(deviceListControllerProvider.notifier).refresh(),
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(StitchSpacing.lg, StitchSpacing.lg, StitchSpacing.lg, StitchSpacing.pageBottom),
        children: [
          // Subtle refresh indicator bar (instead of full-screen blank)
          if (state.refreshing)
            const Padding(
              padding: EdgeInsets.only(bottom: StitchSpacing.sm),
              child: LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                color: StitchColors.primaryContainer,
                minHeight: 2,
              ),
            ),

          // Node selector floating island
          _NodeSelector(
            devices: state.devices,
            selectedId: state.selectedHardwareId,
            onSelect: (id) => ref.read(deviceListControllerProvider.notifier).selectNode(id),
          ),
          const SizedBox(height: StitchSpacing.xxl),

          // Sensor grid or empty state
          if (state.selectedHardwareId != null) ...[
            if (state.sensorsBusy && state.sensorReadings.isEmpty)
              _buildSensorLoading()
            else if (state.sensorError != null && state.sensorReadings.isEmpty)
              _buildSensorError(state.sensorError!)
            else if (state.sensorReadings.isEmpty)
              _buildNoSensors()
            else
              _buildSensorGrid(state.sensorReadings),
          ],
        ],
      ),
    );
  }

  Widget _buildSensorGrid(List<DeviceSensorReading> readings) {
    final columns = stitchGridColumns(context, mobileColumns: 2, tabletColumns: 3, desktopColumns: 4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: StitchSpacing.md),
          child: AutoSizeText(
            'LIVE SENSORS',
            style: Theme.of(context).textTheme.labelLarge,
            maxLines: 1,
            minFontSize: 9,
          ),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: StitchSpacing.md,
            mainAxisSpacing: StitchSpacing.md,
            childAspectRatio: columns <= 2 ? 1.4 : 1.2,
          ),
          itemCount: readings.length,
          itemBuilder: (context, index) => _SensorGridCard(reading: readings[index]),
        ),
      ],
    );
  }

  Widget _buildSensorLoading() {
    final columns = stitchGridColumns(context, mobileColumns: 2, tabletColumns: 3, desktopColumns: 4);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: StitchSpacing.md,
        mainAxisSpacing: StitchSpacing.md,
        childAspectRatio: 1.0,
      ),
      itemCount: 4,
      itemBuilder: (_, _) => const StitchSkeletonPanel(height: 100, lineCount: 2, showIcon: false),
    );
  }

  Widget _buildSensorError(String error) {
    return StitchEmptyState(
      title: 'Sensor Error',
      subtitle: error,
      icon: Icons.cloud_off_rounded,
    );
  }

  Widget _buildNoSensors() {
    return const StitchEmptyState(
      title: 'No Sensor Data',
      subtitle: 'Waiting for the node to send telemetry data.',
      icon: Icons.sensors_rounded,
    );
  }

  Widget _buildLoading() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(StitchSpacing.lg, StitchSpacing.lg, StitchSpacing.lg, StitchSpacing.pageBottom),
      children: List.generate(4, (_) => const Padding(
        padding: EdgeInsets.only(bottom: StitchSpacing.md),
        child: StitchSkeletonPanel(height: 100, lineCount: 3),
      )),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: StitchEmptyState(title: 'Connection Error', subtitle: error, icon: Icons.cloud_off_rounded),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(StitchSpacing.xl, StitchSpacing.xxl, StitchSpacing.xl, StitchSpacing.pageBottom),
      children: [
        AutoSizeText('Devices', style: Theme.of(context).textTheme.displayMedium, maxLines: 1, minFontSize: 20),
        const SizedBox(height: StitchSpacing.sm),
        AutoSizeText('Your registered nodes will appear here.', style: Theme.of(context).textTheme.bodyMedium, maxLines: 2, minFontSize: 11),
        const SizedBox(height: StitchSpacing.xxl),
        const StitchEmptyState(
          title: 'No Devices Found',
          subtitle: 'Deploy a node from the Architect tab and it will appear here once it sends data to the cloud.',
          icon: Icons.flash_on_rounded,
        ),
        const SizedBox(height: StitchSpacing.xxl),
        Center(
          child: StitchPrimaryButton(
            onPressed: _showClaimNodeSheet,
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_link_rounded, size: 18),
              SizedBox(width: 8),
              Text('CLAIM NODE'),
            ]),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Node Selector — Floating Island
// ---------------------------------------------------------------------------

class _NodeSelector extends StatelessWidget {
  final List<DeviceListItem> devices;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _NodeSelector({
    required this.devices,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final count = devices.length;
    // Width per item: 72px for label + padding
    const double itemWidth = 72;
    final double totalWidth = count * itemWidth + 16; // +16 for horizontal padding

    return SizedBox(
      height: 48,
      child: Center(
        child: Container(
          width: totalWidth.clamp(120, 360),
          decoration: BoxDecoration(
            color: StitchColors.surfaceLowest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: StitchColors.outlineVariant.withValues(alpha: 0.5), width: 1),
            boxShadow: AppTheme.subtleShadow,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemW = constraints.maxWidth / count;
              const double indicatorWidth = 36;
              const double indicatorHeight = 28;
              final selectedIndex = devices.indexWhere((d) => d.hardwareId == selectedId);
              final idx = selectedIndex >= 0 ? selectedIndex : 0;
              final leftPosition = (idx * itemW) + (itemW / 2) - (indicatorWidth / 2);

              return Stack(
                children: [
                  // Pill indicator
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeInOutCubicEmphasized,
                    left: leftPosition,
                    top: (48 - indicatorHeight) / 2,
                    child: Container(
                      width: indicatorWidth,
                      height: indicatorHeight,
                      decoration: BoxDecoration(
                        color: StitchColors.surfaceContainer.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: StitchColors.outlineVariant.withValues(alpha: 0.3), width: 1),
                      ),
                    ),
                  ),
                  // Node items — label only, no emoji
                  Row(
                    children: List.generate(count, (index) {
                      final device = devices[index];
                      final selected = device.hardwareId == selectedId;
                      return SizedBox(
                        width: itemW,
                        height: 48,
                        child: GestureDetector(
                          onTap: () => onSelect(device.hardwareId),
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: Text(
                              device.shortLabel,
                              style: TextStyle(
                                color: selected ? StitchColors.primaryContainer : StitchColors.onSurfaceVariant,
                                fontSize: 11,
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sensor Grid Card
// ---------------------------------------------------------------------------

class _SensorGridCard extends StatelessWidget {
  final DeviceSensorReading reading;

  const _SensorGridCard({required this.reading});

  void _openChartModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: StitchColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      isScrollControlled: true,
      builder: (ctx) => _SensorChartModal(reading: reading),
    );
  }

  Color get _accent {
    switch (reading.sensor.toLowerCase()) {
      case 'temperature': case 'temp': return const Color(0xFFFF6B6B);
      case 'humidity': case 'hum': return const Color(0xFF4FC3F7);
      case 'ph': return const Color(0xFFCE93D8);
      case 'tds': case 'ec': return const Color(0xFFFFB74D);
      case 'turbidity': return const Color(0xFF81C784);
      case 'rain': return const Color(0xFF4DD0E1);
      case 'water_temp': case 'watertemperature': return const Color(0xFF4FC3F7);
      default: return StitchColors.primaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent;
    return GestureDetector(
      onTap: () => _openChartModal(context),
      child: Container(
      decoration: BoxDecoration(
        color: StitchColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Colored top accent bar
          Container(
            height: 3,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
          ),
          // Value section
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sensor emoji + name
                Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(reading.emoji, style: const TextStyle(fontSize: 14)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        reading.label.toUpperCase(),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 9, letterSpacing: 0.8,
                          color: accent, fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Large value
                Text(
                  reading.value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontSize: 26, fontWeight: FontWeight.w900,
                    fontFamily: 'SpaceGrotesk', color: StitchColors.primary,
                    height: 1.0,
                  ),
                  maxLines: 1,
                ),
                // Unit + timestamp
                Row(
                  children: [
                    if (reading.unit.isNotEmpty)
                      Text(
                        reading.unit,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: StitchColors.onSurfaceVariant,
                          fontSize: 11, fontWeight: FontWeight.w600,
                        ),
                      ),
                    const Spacer(),
                    if (reading.createdAt != null)
                      Text(
                        _formatTime(reading.createdAt!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: StitchColors.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 8,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    return '${diff.inHours}h';
  }
}

// ---------------------------------------------------------------------------
// Sensor Chart Modal
// ---------------------------------------------------------------------------

class _SensorChartModal extends StatefulWidget {
  final DeviceSensorReading reading;
  const _SensorChartModal({required this.reading});

  @override
  State<_SensorChartModal> createState() => _SensorChartModalState();
}

class _SensorChartModalState extends State<_SensorChartModal> {
  String _range = '24 HOUR';
  List<ChartPoint> _chartPoints = [];
  bool _loading = true;

  static const _ranges = ['1 HOUR', '6 HOUR', '24 HOUR', '7 DAY'];

  @override
  void initState() {
    super.initState();
    _loadChartData();
  }

  Future<void> _loadChartData() async {
    setState(() => _loading = true);
    try {
      // Calculate the time threshold based on selected range
      final now = DateTime.now();
      final threshold = switch (_range) {
        '1 HOUR' => now.subtract(const Duration(hours: 1)),
        '6 HOUR' => now.subtract(const Duration(hours: 6)),
        '24 HOUR' => now.subtract(const Duration(hours: 24)),
        '7 DAY' => now.subtract(const Duration(days: 7)),
        _ => now.subtract(const Duration(hours: 24)),
      };

      final rows = await TursoService.query(
        '''SELECT sd.value, sr.created_at
           FROM sensor_data sd
           JOIN sensor_readings sr ON sd.reading_id = sr.id
           WHERE sr.hardware_id IN (
             SELECT hardware_id FROM user_nodes WHERE user_id = (
               SELECT id FROM users WHERE username = 'admin'
             )
           )
           AND LOWER(sd.sensor) = ?
           AND sr.created_at > ?
           ORDER BY sr.created_at ASC''',
        [widget.reading.sensor.toLowerCase(), threshold.toIso8601String()],
      );

      final points = <ChartPoint>[];
      for (final r in rows) {
        final value = double.tryParse(r['value']?.toString() ?? '');
        if (value == null) continue;
        DateTime? time;
        if (r['created_at'] is String) {
          time = DateTime.tryParse(r['created_at'] as String);
        }
        if (time == null) continue;
        points.add(ChartPoint(time: time, value: value));
      }

      if (mounted) setState(() => _chartPoints = points);
    } catch (_) {
      // Keep empty
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = widget.reading;
    final accent = _modalSensorColor(reading.sensor);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: StitchColors.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Text(reading.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reading.label,
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          reading.sensor,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: StitchColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Current value
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        reading.value,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontSize: 24, fontWeight: FontWeight.w900,
                          fontFamily: 'SpaceGrotesk',
                        ),
                      ),
                      if (reading.unit.isNotEmpty)
                        Text(
                          reading.unit,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: StitchColors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Range selector
              Row(
                children: _ranges.map((r) {
                  final selected = _range == r;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _range = r);
                        _loadChartData();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: selected
                              ? accent.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: selected
                                ? accent.withValues(alpha: 0.4)
                                : StitchColors.outlineVariant.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          r,
                          style: TextStyle(
                            color: selected ? accent : StitchColors.onSurfaceVariant,
                            fontSize: 10,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Chart
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                    : _chartPoints.length < 2
                        ? const Center(
                            child: Text(
                              'Not enough data for this range.',
                              style: TextStyle(color: StitchColors.onSurfaceVariant),
                            ),
                          )
                        : _buildChart(accent),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChart(Color accent) {
    final points = _chartPoints;
    final min = points.map((p) => p.value).reduce((a, b) => a < b ? a : b);
    final max = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final range = (max - min).clamp(0.1, double.infinity);
    final pad = range * 0.1;

    return LineChart(
      LineChartData(
        minY: min - pad,
        maxY: max + pad,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: range / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: StitchColors.outlineVariant.withValues(alpha: 0.15),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(1),
                style: const TextStyle(color: StitchColors.onSurfaceVariant, fontSize: 9),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (points.length / 5).ceilToDouble().clamp(1, double.infinity),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                final t = points[idx].time;
                return Text(
                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: StitchColors.onSurfaceVariant, fontSize: 9),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(points.length, (i) => FlSpot(i.toDouble(), points[i].value)),
            isCurved: true,
            color: accent,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: accent.withValues(alpha: 0.08),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final idx = s.spotIndex;
              final v = points[idx].value.toStringAsFixed(1);
              final t = '${points[idx].time.hour.toString().padLeft(2, '0')}:${points[idx].time.minute.toString().padLeft(2, '0')}';
              return LineTooltipItem(
                '$v ${widget.reading.unit}\n$t',
                TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 11),
              );
            }).toList(),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 300),
    );
  }
}

Color _modalSensorColor(String sensor) {
  switch (sensor.toLowerCase()) {
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

