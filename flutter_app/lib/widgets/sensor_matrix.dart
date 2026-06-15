import 'dart:math';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

enum _Trend { up, down, stable }

class SensorMatrix extends StatelessWidget {
  final List<Map<String, dynamic>> deviceConfig;
  final void Function(List<Map<String, dynamic>>) onLoad;
  final bool loading;

  const SensorMatrix({
    super.key,
    required this.deviceConfig,
    required this.onLoad,
    this.loading = false,
  });

  static const _accentColors = [
    StitchColors.primaryContainer,
    StitchColors.secondary,
    StitchColors.tertiaryFixed,
    Color(0xFF00FF87),
  ];

  String _displayName(Map<String, dynamic> item) {
    final sensor = item['sensor']?.toString().trim() ?? 'Unknown Sensor';
    final label = item['label']?.toString().trim() ?? '';
    if (sensor == 'Relay' && label.isNotEmpty) {
      return '$label Relay';
    }
    return sensor;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _buildSkeleton();
    }

    if (deviceConfig.isEmpty) {
      return const StitchEmptyState(
        title: 'No Live Sensors',
        subtitle:
            'Your live node screen is ready. Load a saved profile or build one in Architect to populate this matrix.',
        icon: Icons.sensors_outlined,
      );
    }

    final itemCount = deviceConfig.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: AutoSizeText(
                  'GPIO SENSOR MATRIX',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: StitchColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                  maxLines: 1,
                  minFontSize: 10,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: StitchColors.surfaceLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: StitchColors.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const StitchPulseDot(
                      color: StitchColors.primaryContainer,
                      size: 6,
                      pulseRadius: 10,
                    ),
                    const SizedBox(width: 8),
                    AutoSizeText(
                      'LIVE FEED',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                      maxLines: 1,
                      minFontSize: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final accent = _accentColors[i % _accentColors.length];
            return AnimatedTelemetryCard(
              item: deviceConfig[i],
              index: i,
              accent: accent,
              displayName: _displayName(deviceConfig[i]),
            );
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: StitchGhostButton(
            onPressed: () => onLoad(deviceConfig),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.tune_rounded, size: 16),
                const SizedBox(width: 8),
                const AutoSizeText(
                  'EDIT IN ARCHITECT',
                  maxLines: 1,
                  minFontSize: 10,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: StitchShimmer(height: 16, width: 180, borderRadius: 4),
        ),
        const SizedBox(height: 14),
        ...List.generate(3, (i) => Padding(
          padding: EdgeInsets.only(bottom: i < 2 ? 12 : 0),
          child: const StitchSkeletonPanel(height: 80, lineCount: 2),
        )),
      ],
    );
  }
}

class AnimatedTelemetryCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final int index;
  final Color accent;
  final String displayName;

  const AnimatedTelemetryCard({
    super.key,
    required this.item,
    required this.index,
    required this.accent,
    required this.displayName,
  });

  @override
  State<AnimatedTelemetryCard> createState() => _AnimatedTelemetryCardState();
}

class _AnimatedTelemetryCardState extends State<AnimatedTelemetryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sweepAnimation;
  late double _targetPct;
  late String _valText;
  late _Trend _trend;
  late String _trendLabel;
  late List<FlSpot> _sparklineSpots;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 600 + widget.index * 100),
    );
    _sweepAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _loadMockTelemetry();
    _controller.forward();
  }

  void _loadMockTelemetry() {
    final sensor = (widget.item['sensor']?.toString() ?? '').toLowerCase();
    final label = (widget.item['label']?.toString() ?? '').toLowerCase();

    if (sensor.contains('ph')) {
      _targetPct = 6.8 / 14.0;
      _valText = '6.8 pH';
    } else if (sensor.contains('temp') || label.contains('temp')) {
      _targetPct = 26.5 / 50.0;
      _valText = '26.5 °C';
    } else if (sensor.contains('tds')) {
      _targetPct = 340.0 / 1000.0;
      _valText = '340 ppm';
    } else if (sensor.contains('turbidity')) {
      _targetPct = 18.0 / 100.0;
      _valText = '18 NTU';
    } else if (sensor.contains('rain')) {
      _targetPct = 0.08;
      _valText = 'DRY';
    } else if (sensor.contains('relay') || label.contains('relay') ||
        sensor.contains('pump') || label.contains('pump')) {
      _targetPct = 1.0;
      _valText = 'ACTIVE';
    } else {
      _targetPct = 0.72;
      _valText = 'ON';
    }

    // Trend: deterministic pseudo-random based on index
    final variance = ((widget.index * 0.37) % 1.0) * 1.5 - 0.5;
    if (variance > 0.2) {
      _trend = _Trend.up;
      _trendLabel = '+${variance.toStringAsFixed(1)}';
    } else if (variance < -0.2) {
      _trend = _Trend.down;
      _trendLabel = variance.toStringAsFixed(1);
    } else {
      _trend = _Trend.stable;
      _trendLabel = '0.0';
    }

    // Sparkline: 10 data points clustered around target
    final rng = Random(widget.index * 7 + 13);
    final base = _targetPct * 100;
    _sparklineSpots = List.generate(10, (i) {
      final noise = (rng.nextDouble() - 0.5) * 15;
      return FlSpot(i.toDouble(), (base + noise).clamp(0.0, 100.0));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _iconForSensor(String sensor) {
    final normalized = sensor.toLowerCase();
    if (normalized.contains('pump')) return Icons.water_rounded;
    if (normalized.contains('valve')) return Icons.tune_rounded;
    if (normalized.contains('relay')) return Icons.toggle_on_rounded;
    if (normalized.contains('temp')) return Icons.thermostat_rounded;
    if (normalized.contains('humid')) return Icons.water_drop_rounded;
    if (normalized.contains('light')) return Icons.light_mode_rounded;
    if (normalized.contains('ph')) return Icons.science_outlined;
    if (normalized.contains('tds')) return Icons.opacity_rounded;
    if (normalized.contains('turbidity')) return Icons.water_drop_outlined;
    if (normalized.contains('rain')) return Icons.grain_rounded;
    return Icons.developer_board_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final sensorType = (widget.item['sensor']?.toString() ?? '').toLowerCase();

    return StitchPanel(
      color: StitchColors.surfaceLowest,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: StitchColors.surfaceLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.accent.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(
                  _iconForSensor(widget.displayName),
                  color: widget.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AutoSizeText(
                      widget.displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                      maxLines: 1,
                      minFontSize: 12,
                    ),
                    const SizedBox(height: 4),
                    AutoSizeText(
                      'GPIO ${widget.item['pin']} • ${widget.item['type']}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                      maxLines: 1,
                      minFontSize: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 104,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AutoSizeText(
                      _valText,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: StitchColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                      maxLines: 1,
                      minFontSize: 12,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _trend == _Trend.up
                              ? Icons.trending_up_rounded
                              : _trend == _Trend.down
                                  ? Icons.trending_down_rounded
                                  : Icons.trending_flat_rounded,
                          size: 12,
                          color: _trend == _Trend.up
                              ? StitchColors.trendUp
                              : _trend == _Trend.down
                                  ? StitchColors.trendDown
                                  : StitchColors.trendStable,
                        ),
                        const SizedBox(width: 2),
                        AutoSizeText(
                          _trendLabel,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _trend == _Trend.up
                                ? StitchColors.trendUp
                                : _trend == _Trend.down
                                    ? StitchColors.trendDown
                                    : StitchColors.trendStable,
                          ),
                          maxLines: 1,
                          minFontSize: 8,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedBuilder(
                      animation: _sweepAnimation,
                      builder: (context, child) {
                        final currentPct = _sweepAnimation.value * _targetPct;
                        return _buildVisualTelemetryBar(sensorType, currentPct);
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildSparkline(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSparkline() {
    return SizedBox(
      width: 104,
      height: 28,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: _sparklineSpots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: widget.accent,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: widget.accent.withValues(alpha: 0.15),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 300),
      ),
    );
  }

  Gradient _barGradient(String sensorType) {
    if (sensorType.contains('temp')) return AppTheme.tempGradient;
    if (sensorType.contains('tds')) return AppTheme.tdsGradient;
    return LinearGradient(
      colors: [widget.accent, widget.accent],
    );
  }

  Widget _buildVisualTelemetryBar(String sensorType, double pct) {
    if (sensorType.contains('ph')) {
      return Container(
        height: 6,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          gradient: AppTheme.phGradient,
        ),
        child: Align(
          alignment: Alignment(pct * 2 - 1, 0),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 2,
                )
              ],
            ),
          ),
        ),
      );
    }

    if (sensorType.contains('relay') || sensorType.contains('pump')) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF00FF87),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FF87).withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          AutoSizeText(
            'ON',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              color: Color(0xFF00FF87),
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            minFontSize: 8,
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: StitchColors.surfaceLow,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct.clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: _barGradient(sensorType),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
