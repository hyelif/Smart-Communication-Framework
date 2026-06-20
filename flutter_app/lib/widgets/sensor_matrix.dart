import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

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

  static final _accentColors = [
    StitchColors.primaryContainer,
    StitchColors.secondary,
    StitchColors.tertiaryFixed,
    const Color(0xFF00FF87),
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
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.tune_rounded, size: 16),
                SizedBox(width: 8),
                AutoSizeText(
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: StitchShimmer(height: 16, width: 180, borderRadius: 4),
        ),
        SizedBox(height: 14),
        SkeletonList(),
      ],
    );
  }
}

/// Internal helper to render skeleton items without dynamic generation.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(3, (i) => Padding(
        padding: EdgeInsets.only(bottom: i < 2 ? 12 : 0),
        child: const StitchSkeletonPanel(height: 80, lineCount: 2),
      )),
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
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static IconData _iconForSensor(String sensor) {
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
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _pulseAnimation.value,
                          child: AutoSizeText(
                            'AWAITING\nSIGNAL',
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: StitchColors.onSurfaceVariant,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                            maxLines: 2,
                            minFontSize: 8,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildNoDataBar(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataBar() {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: StitchColors.surfaceLow,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
