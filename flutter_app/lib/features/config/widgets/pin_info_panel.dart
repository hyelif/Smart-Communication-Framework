import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';

import '../../../widgets/app_theme.dart';
import '../../../widgets/custom_ui.dart';

/// GPIO pin reference information panel.
class PinInfoPanel extends StatelessWidget {
  const PinInfoPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return StitchPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.settings_input_component_outlined,
                color: StitchColors.primaryContainer,
              ),
              SizedBox(width: 8),
              Expanded(
                child: AutoSizeText(
                  'PIN CONFIGURATION',
                  style: TextStyle(
                    color: StitchColors.primary,
                    fontFamily: 'SpaceGrotesk',
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                  maxLines: 1,
                  minFontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 640;
              final tileWidth = wide
                  ? (constraints.maxWidth - 30) / 4
                  : (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _InfoTile(
                    'ANALOG INPUT',
                    'pH, TDS, Turbidity\n32, 33, 34, 35, 36, 39',
                  ),
                  _InfoTile(
                    'DIGITAL INPUT',
                    'Rain, DHT22, WaterTemp\n12, 13, 16, 17, 27',
                  ),
                  _InfoTile(
                    'DIGITAL OUTPUT',
                    'Relay\n25, 26',
                  ),
                  _InfoTile(
                    'RESERVED',
                    '5, 14, 18, 19, 21, 22, 23',
                  ),
                ].map((tile) {
                  return SizedBox(
                    width: tileWidth,
                    child: tile,
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;

  const _InfoTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(minHeight: 104),
      decoration: BoxDecoration(
        color: StitchColors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AutoSizeText(
            label,
            style: Theme.of(context).textTheme.labelMedium,
            maxLines: 1,
            minFontSize: 9,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: AutoSizeText(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontSize: 13),
              minFontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
