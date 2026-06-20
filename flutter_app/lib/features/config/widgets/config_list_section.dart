import 'package:flutter/material.dart';

import '../../../utils/config_validator.dart';
import '../../../widgets/app_theme.dart';
import '../../../widgets/custom_ui.dart';

/// Displays the list of configured sensor nodes as bento-style cards.
class ConfigListSection extends StatelessWidget {
  final List<Map<String, dynamic>> config;
  final ValueChanged<int> onRemoveNode;

  const ConfigListSection({
    super.key,
    required this.config,
    required this.onRemoveNode,
  });

  @override
  Widget build(BuildContext context) {
    if (config.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: StitchEmptyState(
          title: 'No Nodes Defined',
          subtitle:
              'Tap "Add Sensor Node" or "Load From Node" to start building your ESP32 configuration.',
          icon: Icons.hub_outlined,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 720;
        return RepaintBoundary(
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: config.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 2 : 1,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: wide ? 1.7 : 2.9,
            ),
            itemBuilder: (context, index) =>
                _ConfigCard(item: config[index], index: index, onRemove: onRemoveNode),
          ),
        );
      },
    );
  }
}

class _ConfigCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final int index;
  final ValueChanged<int> onRemove;

  const _ConfigCard({
    required this.item,
    required this.index,
    required this.onRemove,
  });

  String _displayName(Map<String, dynamic> item) {
    final sensor = item['sensor']?.toString().trim() ?? 'Node';
    final label = item['label']?.toString().trim() ?? '';
    if (sensor == 'Relay' && label.isNotEmpty) {
      return '$label Relay';
    }
    return sensor;
  }

  IconData _componentIcon(String component) =>
      ConfigValidator.componentIcon(component);

  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString().toUpperCase() ?? 'AI';
    Color accentColor;
    if (type == 'AI') {
      accentColor = StitchColors.primaryContainer;
    } else if (type == 'DI') {
      accentColor = StitchColors.secondary;
    } else {
      accentColor = StitchColors.tertiaryFixed;
    }

    return StitchBounce(
      onTap: () {},
      child: StitchPanel(
        color: StitchColors.surfaceLowest,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    'P${item['pin']}',
                    style: TextStyle(
                      fontFamily: 'SpaceGrotesk',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  _componentIcon(_displayName(item)),
                  color: accentColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                StitchBounce(
                  onTap: () => onRemove(index),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: StitchColors.error.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: StitchColors.error,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              _displayName(item).toUpperCase(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'GPIO ${item['pin']}  •  $type',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
