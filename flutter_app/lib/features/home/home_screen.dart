import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';

/// Home dashboard screen — placeholder for Phase 2.
///
/// Shows a welcome message, device count summary, and quick status.
/// Will be expanded with charts and insights in later phases.
class HomeScreen extends StatelessWidget {
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;

  const HomeScreen({
    super.key,
    required this.activeTabListenable,
    required this.tabIndex,
  });

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      body: Column(
        children: [
          StitchTopBar(section: 'Home'),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
              children: [
                AutoSizeText(
                  'Good Evening,',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: StitchColors.onSurfaceVariant,
                        fontSize: 16,
                      ),
                  maxLines: 1,
                  minFontSize: 12,
                ),
                const SizedBox(height: 4),
                AutoSizeText(
                  'SmartPonic Operator',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        fontSize: 28,
                      ),
                  maxLines: 1,
                  minFontSize: 20,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.flash_on_rounded,
                        label: 'DEVICES',
                        value: '--',
                        accent: StitchColors.primaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.notifications_rounded,
                        label: 'ALERTS',
                        value: '--',
                        accent: StitchColors.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.wifi_rounded,
                        label: 'COMM HEALTH',
                        value: '--',
                        accent: StitchColors.secondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.inventory_2_outlined,
                        label: 'PROFILES',
                        value: '--',
                        accent: StitchColors.tertiaryFixed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                StitchPanel.glass(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.rocket_launch_rounded,
                                size: 18, color: StitchColors.primaryContainer),
                            SizedBox(width: 8),
                            AutoSizeText(
                              'GETTING STARTED',
                              style: TextStyle(
                                fontFamily: 'SpaceGrotesk',
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                letterSpacing: 1.2,
                                color: StitchColors.primaryContainer,
                              ),
                              maxLines: 1,
                              minFontSize: 9,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Your devices will appear here once they send data to the cloud. '
                          'Use the Architect tab to configure and deploy new ESP32 nodes.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return StitchPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 6),
              AutoSizeText(
                label,
                style: Theme.of(context).textTheme.labelMedium,
                maxLines: 1,
                minFontSize: 9,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AutoSizeText(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 24,
                  color: accent,
                ),
            maxLines: 1,
            minFontSize: 16,
          ),
        ],
      ),
    );
  }
}
