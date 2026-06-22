import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';
import '../../widgets/responsive_layout.dart';
import '../auth/auth_controller.dart';
import 'home_controller.dart';

/// Home dashboard screen showing aggregate device status.
///
/// Displays device count, active alerts, communication health,
/// and a getting-started prompt. Data is fetched from Turso via
/// [HomeController].
class HomeScreen extends ConsumerStatefulWidget {
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;

  const HomeScreen({
    super.key,
    required this.activeTabListenable,
    required this.tabIndex,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      ref.read(homeControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homeState = ref.watch(homeControllerProvider);
    final authState = ref.watch(authControllerProvider);

    final greeting = _timeBasedGreeting();
    final displayName = authState.username ?? 'SmartPonic Operator';

    return StitchScaffold(
      body: Column(
        children: [
          StitchTopBar(section: 'Home'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(homeControllerProvider.notifier).refresh(),
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(
                  StitchSpacing.xl, StitchSpacing.xxl, StitchSpacing.xl, StitchSpacing.pageBottom,
                ),
                children: [
                  // Greeting
                  AutoSizeText(
                    greeting,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: StitchColors.onSurfaceVariant,
                          fontSize: 16,
                        ),
                    maxLines: 1,
                    minFontSize: 12,
                  ),
                  const SizedBox(height: StitchSpacing.xs),
                  AutoSizeText(
                    displayName,
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 28,
                        ),
                    maxLines: 1,
                    minFontSize: 20,
                  ),
                  const SizedBox(height: StitchSpacing.xxl),

                  // Summary cards — responsive grid
                  if (homeState.error != null)
                    _buildErrorBanner(homeState.error!)
                  else
                    _buildSummaryGrid(homeState),

                  const SizedBox(height: 24),

                  // Getting started / status panel
                  _buildStatusPanel(context, homeState),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: StitchColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: StitchColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: StitchColors.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: StitchColors.error),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(BuildContext context, HomeState state) {
    if (state.deviceCount == 0 && !state.busy) {
      return StitchPanel.glass(
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
      );
    }

    // All healthy
    if (state.alertCount == 0 &&
        (state.averageDeliveryRate == null ||
            state.averageDeliveryRate! >= 80)) {
      return StitchPanel.glass(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const StitchPulseDot(
                color: Color(0xFF4CAF50),
                size: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'All systems operational. ${state.deviceCount} device${state.deviceCount == 1 ? '' : 's'} online.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Has alerts or degraded health
    return StitchPanel.glass(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.alertCount > 0
                      ? Icons.warning_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: state.alertCount > 0
                      ? StitchColors.error
                      : StitchColors.tertiaryFixed,
                ),
                const SizedBox(width: 8),
                AutoSizeText(
                  state.alertCount > 0 ? 'ATTENTION NEEDED' : 'DEGRADED',
                  style: TextStyle(
                    fontFamily: 'SpaceGrotesk',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: state.alertCount > 0
                        ? StitchColors.error
                        : StitchColors.tertiaryFixed,
                  ),
                  maxLines: 1,
                  minFontSize: 9,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              state.alertCount > 0
                  ? '${state.alertCount} active alert${state.alertCount == 1 ? '' : 's'} require your attention.'
                  : 'Communication health is degraded (${state.averageDeliveryRate?.round()}% delivery rate).',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// Return a time-appropriate greeting.
  String _timeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning,';
    if (hour < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  Widget _buildSummaryGrid(HomeState homeState) {
    final columns = stitchGridColumns(context, mobileColumns: 2, tabletColumns: 4, desktopColumns: 4);

    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: StitchSpacing.md,
        mainAxisSpacing: StitchSpacing.md,
        childAspectRatio: 1.6,
      ),
      children: [
        _SummaryCard(
          icon: Icons.flash_on_rounded,
          label: 'DEVICES',
          value: homeState.busy ? '...' : '${homeState.deviceCount}',
          accent: StitchColors.primaryContainer,
        ),
        _SummaryCard(
          icon: Icons.notifications_rounded,
          label: 'ALERTS',
          value: homeState.busy ? '...' : '${homeState.alertCount}',
          accent: homeState.alertCount > 0
              ? StitchColors.error
              : StitchColors.primaryContainer,
        ),
        _SummaryCard(
          icon: Icons.wifi_rounded,
          label: 'COMM HEALTH',
          value: homeState.busy
              ? '...'
              : (homeState.averageDeliveryRate != null
                  ? '${homeState.averageDeliveryRate!.round()}%'
                  : '--'),
          accent: _healthColor(homeState.averageDeliveryRate),
        ),
        _SummaryCard(
          icon: Icons.inventory_2_outlined,
          label: 'PROFILES',
          value: '--',
          accent: StitchColors.tertiaryFixed,
        ),
      ],
    );
  }

  /// Map a delivery rate to a color.
  Color _healthColor(double? rate) {
    if (rate == null) return StitchColors.onSurfaceVariant;
    if (rate >= 80) return const Color(0xFF4CAF50);
    if (rate >= 50) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }
}

// ---------------------------------------------------------------------------
// Summary Card
// ---------------------------------------------------------------------------

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
