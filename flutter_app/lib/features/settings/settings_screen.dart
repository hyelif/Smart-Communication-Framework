import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../screens/calibration_screen.dart';
import '../../screens/profiles_screen.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';

/// Settings screen with Vault (profiles) and Calibration tabs.
class SettingsScreen extends StatefulWidget {
  final void Function(List<Map<String, dynamic>>) onSelectProfile;
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;

  const SettingsScreen({
    super.key,
    required this.onSelectProfile,
    required this.activeTabListenable,
    required this.tabIndex,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StitchScaffold(
      body: Column(
        children: [
          StitchTopBar(section: 'Settings'),
          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            decoration: BoxDecoration(
              color: StitchColors.surfaceLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: StitchColors.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: StitchColors.primary,
              unselectedLabelColor: StitchColors.onSurfaceVariant,
              labelStyle: const TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('VAULT'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.tune_rounded, size: 16),
                      SizedBox(width: 6),
                      Text('CALIBRATE'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _VaultTab(
                  onSelectProfile: widget.onSelectProfile,
                ),
                _CalibrationTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vault tab content — shows saved profiles.
class _VaultTab extends StatefulWidget {
  final void Function(List<Map<String, dynamic>>) onSelectProfile;

  const _VaultTab({required this.onSelectProfile});

  @override
  State<_VaultTab> createState() => _VaultTabState();
}

class _VaultTabState extends State<_VaultTab> {
  @override
  Widget build(BuildContext context) {
    // Reuse the existing ProfilesScreen without its outer scaffold
    return ProfilesScreen(
      showTopBar: false,
      activeTabListenable: DefaultValueListenable(0),
      tabIndex: 0,
      onSelectProfile: widget.onSelectProfile,
    );
  }
}

/// Calibration tab content — shows sensor calibration.
class _CalibrationTab extends StatefulWidget {
  const _CalibrationTab();

  @override
  State<_CalibrationTab> createState() => _CalibrationTabState();
}

class _CalibrationTabState extends State<_CalibrationTab> {
  @override
  Widget build(BuildContext context) {
    // Reuse the existing CalibrationScreen without its outer scaffold
    return CalibrationScreen(
      showTopBar: false,
      activeTabListenable: DefaultValueListenable(0),
      tabIndex: 0,
    );
  }
}

/// A simple [ValueNotifier] that always returns a fixed value and never changes.
/// Used to satisfy the [ValueListenable] parameter on embedded screens
/// without triggering tab-change logic.
class DefaultValueListenable<T> extends ValueNotifier<T> {
  DefaultValueListenable(T value) : super(value);

  @override
  set value(T _) {
    // Ignore all attempts to change the value
  }

  @override
  void addListener(VoidCallback listener) {
    // Don't register listeners — this notifier never fires
  }

  @override
  void removeListener(VoidCallback listener) {
    // No-op
  }
}
