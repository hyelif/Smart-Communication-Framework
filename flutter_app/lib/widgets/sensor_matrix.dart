import 'package:flutter/material.dart';

import '../widgets/app_theme.dart';
import '../widgets/custom_ui.dart';

class SensorMatrix extends StatelessWidget {
  final List<Map<String, dynamic>> deviceConfig;
  final void Function(List<Map<String, dynamic>>) onLoad;

  static const _accentColors = [
    StitchColors.primaryContainer,
    StitchColors.secondary,
    StitchColors.secondaryContainer,
    StitchColors.tertiaryFixed,
  ];

  const SensorMatrix({
    super.key,
    required this.deviceConfig,
    required this.onLoad,
  });

  String _displayName(Map<String, dynamic> item) {
    final sensor = item['sensor']?.toString().trim() ?? 'Unknown Sensor';
    final label = item['label']?.toString().trim() ?? '';
    if (sensor == 'Relay' && label.isNotEmpty) {
      return '$label Relay';
    }
    return sensor;
  }

  String _componentKey(Map<String, dynamic> item) {
    final label = item['label']?.toString().trim() ?? '';
    if (label.isNotEmpty) {
      return label;
    }
    return item['sensor']?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    if (deviceConfig.isEmpty) {
      return const StitchEmptyState(
        title: 'No Live Sensors',
        subtitle:
            'Your live node screen is ready. Load a saved profile or build one in Architect to populate this matrix.',
        icon: Icons.sensors_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'GPIO SENSOR MATRIX',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: StitchColors.primary,
                      ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'LIVE SNAPSHOT',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...deviceConfig.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final accent = _accentColors[index % _accentColors.length];
          final strength = ((index + 2) * 0.18).clamp(0.18, 1.0);

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: RepaintBoundary(
              child: StitchPanel(
                color: StitchColors.surfaceLowest,
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        _iconForSensor(_componentKey(item)),
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _displayName(item),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'GPIO ${item['pin']} - ${item['type']}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 88,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _mockLiveValue(item),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: LinearProgressIndicator(
                              value: strength,
                              minHeight: 4,
                              color: accent,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.05),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: StitchGhostButton(
            onPressed: () => onLoad(deviceConfig),
            child: const Text('LOAD INTO ARCHITECT'),
          ),
        ),
      ],
    );
  }

  IconData _iconForSensor(String sensor) {
    final normalized = sensor.toLowerCase();
    if (normalized.contains('pump')) return Icons.water_rounded;
    if (normalized.contains('valve')) return Icons.tune_rounded;
    if (normalized.contains('relay')) return Icons.toggle_on_rounded;
    if (normalized.contains('temp')) return Icons.thermostat_rounded;
    if (normalized.contains('humid')) return Icons.water_drop_rounded;
    if (normalized.contains('light')) return Icons.light_mode_rounded;
    if (normalized.contains('power') || normalized.contains('volt')) {
      return Icons.bolt_rounded;
    }
    if (normalized.contains('ph')) return Icons.science_outlined;
    return Icons.memory_rounded;
  }

  String _mockLiveValue(Map<String, dynamic> item) {
    final normalized = _componentKey(item).toLowerCase();
    if (normalized.contains('pump')) return 'OFF';
    if (normalized.contains('valve')) return 'CLOSED';
    if (normalized.contains('relay')) return 'OFF';
    if (normalized.contains('temp')) return '24.8 C';
    if (normalized.contains('humid')) return '58 %';
    if (normalized.contains('light')) return '412 lx';
    if (normalized.contains('power') || normalized.contains('volt')) {
      return '3.29 V';
    }
    if (normalized.contains('ph')) return '6.7 pH';
    return 'LIVE';
  }
}
