import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';
import 'device_detail_screen.dart';
import 'device_list_controller.dart';

/// Device list screen showing all nodes accessible to the current user.
///
/// Data is fetched from Turso via [DeviceListController].
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
  @override
  void initState() {
    super.initState();
    // Load devices on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deviceListControllerProvider.notifier).loadDevices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deviceListControllerProvider);

    return StitchScaffold(
      body: Column(
        children: [
          const StitchTopBar(section: 'Devices'),
          Expanded(
            child: _buildBody(state),
          ),
        ],
      ),
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
      child: ListView.builder(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        itemCount: state.devices.length,
        itemBuilder: (context, index) {
          final device = state.devices[index];
          return _DeviceCard(device: device);
        },
      ),
    );
  }

  Widget _buildLoading() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      children: List.generate(
        4,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: StitchSkeletonPanel(height: 100, lineCount: 3),
        ),
      ),
    );
  }

  Widget _buildError(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: StitchEmptyState(
          title: 'Connection Error',
          subtitle: error,
          icon: Icons.cloud_off_rounded,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
      children: [
        AutoSizeText(
          'Devices',
          style: Theme.of(context).textTheme.displayMedium,
          maxLines: 1,
          minFontSize: 20,
        ),
        const SizedBox(height: 8),
        AutoSizeText(
          'Your registered nodes will appear here.',
          style: Theme.of(context).textTheme.bodyMedium,
          maxLines: 2,
          minFontSize: 11,
        ),
        const SizedBox(height: 24),
        const StitchEmptyState(
          title: 'No Devices Found',
          subtitle:
              'Deploy a node from the Architect tab and it will appear here once it sends data to the cloud.',
          icon: Icons.flash_on_rounded,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Device Card
// ---------------------------------------------------------------------------

class _DeviceCard extends StatelessWidget {
  final DeviceListItem device;

  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final health = device.health;
    final (Color color, IconData icon) = switch (health) {
      DeviceHealth.healthy => (const Color(0xFF4CAF50), Icons.check_circle_rounded),
      DeviceHealth.warning => (const Color(0xFFFFA726), Icons.warning_rounded),
      DeviceHealth.critical => (const Color(0xFFEF5350), Icons.error_rounded),
      DeviceHealth.offline => (StitchColors.onSurfaceVariant, Icons.cancel_rounded),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StitchBounce(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DeviceDetailScreen(
                hardwareId: device.hardwareId,
                deviceName: device.name,
              ),
            ),
          );
        },
        child: StitchPanel(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Health icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),

              // Name + location + meta
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name ?? device.hardwareId,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (device.location != null && device.location!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        device.location!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: StitchColors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Health badge
                        _Badge(label: device.healthLabel, color: color),
                        const SizedBox(width: 8),
                        // Signal strength
                        if (device.lastRssi != null) ...[
                          Icon(
                            Icons.signal_cellular_alt_rounded,
                            size: 14,
                            color: _rssiColor(device.lastRssi!),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${device.lastRssi} dBm',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: StitchColors.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // Last seen
                        const Icon(Icons.access_time_rounded,
                            size: 13, color: StitchColors.onSurfaceVariant),
                        const SizedBox(width: 3),
                        Text(
                          device.lastSeenLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: StitchColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Chevron
              const Icon(
                Icons.chevron_right_rounded,
                color: StitchColors.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -70) return const Color(0xFF4CAF50);
    if (rssi >= -85) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
      ),
    );
  }
}
