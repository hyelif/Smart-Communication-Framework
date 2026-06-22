import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../screens/calibration_screen.dart';
import '../../screens/config_screen.dart';
import '../../screens/profiles_screen.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/custom_ui.dart';
import '../auth/auth_controller.dart';

/// Settings screen with Vault, Calibrate, Account, and Architect tabs.
class SettingsScreen extends ConsumerStatefulWidget {
  final void Function(List<Map<String, dynamic>>) onSelectProfile;
  final ValueListenable<int> activeTabListenable;
  final int tabIndex;
  final ValueNotifier<List<Map<String, dynamic>>> configNotifier;

  const SettingsScreen({
    super.key,
    required this.onSelectProfile,
    required this.activeTabListenable,
    required this.tabIndex,
    required this.configNotifier,
  });

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _settingsTab = 0;

  /// Base tabs always shown.
  static const _baseTabs = [
    _SettingsTab(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Vault'),
    _SettingsTab(Icons.tune_rounded, Icons.tune_rounded, 'Calibrate'),
    _SettingsTab(Icons.person_outline, Icons.person_rounded, 'Account'),
  ];

  /// Admin-only tab.
  static const _adminTab = _SettingsTab(
    Icons.architecture_outlined, Icons.architecture_rounded, 'Architect',
  );

  /// Get the full tab list based on whether the current user is admin.
  List<_SettingsTab> _tabs(bool isAdmin) {
    if (isAdmin) return [..._baseTabs, _adminTab];
    return _baseTabs;
  }

  /// Get the content widgets for the current tab list.
  List<Widget> _tabWidgets(bool isAdmin) {
    final widgets = <Widget>[
      _VaultTab(onSelectProfile: widget.onSelectProfile),
      const _CalibrationTab(),
      const _AccountTab(),
    ];
    if (isAdmin) {
      widgets.add(_ArchitectTab(configNotifier: widget.configNotifier));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final isAdmin = auth.username == 'admin';
    final tabs = _tabs(isAdmin);
    final tabWidgets = _tabWidgets(isAdmin);
    final count = tabs.length;

    // Reset tab index if it's out of range (e.g. admin logs out)
    if (_settingsTab >= count) {
      _settingsTab = 0;
    }

    return Column(
      children: [
        // Sub-tab floating island nav at the top
        const SizedBox(height: 48),
        SizedBox(
          height: 56,
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: StitchColors.surfaceLowest,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: StitchColors.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                ),
                boxShadow: AppTheme.subtleShadow,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth / count;
                  const double indicatorWidth = 44;
                  const double indicatorHeight = 32;
                  final leftPosition =
                      (_settingsTab * itemWidth) + (itemWidth / 2) - (indicatorWidth / 2);

                  return Stack(
                    children: [
                      // Animated pill indicator
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOutCubicEmphasized,
                        left: leftPosition,
                        top: (56 - indicatorHeight) / 2,
                        child: Container(
                          width: indicatorWidth,
                          height: indicatorHeight,
                          decoration: BoxDecoration(
                            color: StitchColors.surfaceContainer.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: StitchColors.outlineVariant.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                      // Nav items
                      Row(
                        children: List.generate(count, (index) {
                          final tab = tabs[index];
                          final selected = index == _settingsTab;
                          return SizedBox(
                            width: itemWidth,
                            height: 56,
                            child: GestureDetector(
                              onTap: () => setState(() => _settingsTab = index),
                              behavior: HitTestBehavior.opaque,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    selected ? tab.activeIcon : tab.icon,
                                    color: selected
                                        ? StitchColors.primaryContainer
                                        : StitchColors.onSurfaceVariant,
                                    size: 20,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tab.label,
                                    style: TextStyle(
                                      color: selected
                                          ? StitchColors.primaryContainer
                                          : StitchColors.onSurfaceVariant,
                                      fontSize: 9,
                                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                    ),
                                  ),
                                ],
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
        ),
        // Content
        Expanded(
          child: IndexedStack(
            index: _settingsTab,
            children: tabWidgets,
          ),
        ),
      ],
    );
  }
}

class _SettingsTab {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _SettingsTab(this.icon, this.activeIcon, this.label);
}

// ---------------------------------------------------------------------------
// Vault Tab
// ---------------------------------------------------------------------------

class _VaultTab extends StatefulWidget {
  final void Function(List<Map<String, dynamic>>) onSelectProfile;

  const _VaultTab({required this.onSelectProfile});

  @override
  State<_VaultTab> createState() => _VaultTabState();
}

class _VaultTabState extends State<_VaultTab> {
  @override
  Widget build(BuildContext context) {
    return ProfilesScreen(
      showTopBar: false,
      activeTabListenable: DefaultValueListenable(0),
      tabIndex: 0,
      onSelectProfile: widget.onSelectProfile,
    );
  }
}

// ---------------------------------------------------------------------------
// Calibration Tab
// ---------------------------------------------------------------------------

class _CalibrationTab extends StatefulWidget {
  const _CalibrationTab();

  @override
  State<_CalibrationTab> createState() => _CalibrationTabState();
}

class _CalibrationTabState extends State<_CalibrationTab> {
  @override
  Widget build(BuildContext context) {
    return CalibrationScreen(
      showTopBar: false,
      activeTabListenable: DefaultValueListenable(0),
      tabIndex: 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Account Tab
// ---------------------------------------------------------------------------

class _AccountTab extends ConsumerStatefulWidget {
  const _AccountTab();

  @override
  ConsumerState<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends ConsumerState<_AccountTab> {
  bool _loggingOut = false;

  Future<void> _handleLogout() async {
    setState(() => _loggingOut = true);
    await ref.read(authControllerProvider.notifier).logout();
    if (mounted) setState(() => _loggingOut = false);
  }

  Future<void> _showClaimNodeSheet() async {
    final hardwareIdController = TextEditingController();
    final claimed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StitchColors.surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: StitchRadius.cardBorder),
        title: const Text('Claim Node',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: hardwareIdController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Hardware ID',
            hintText: 'e.g. 000090F74BDF948C',
            prefixIcon: Icon(Icons.memory_rounded),
          ),
          textInputAction: TextInputAction.done,
          style: const TextStyle(
            fontFamily: 'SpaceGrotesk',
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        StitchSpacing.xl, StitchSpacing.xxl, StitchSpacing.xl, StitchSpacing.pageBottom,
      ),
      children: [
        // Avatar / branding
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppTheme.ctaGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppTheme.cyanGlowShadow,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.black,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Username
        Center(
          child: Text(
            auth.username ?? 'Unknown User',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            'User ID: ${auth.userId ?? '--'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: StitchColors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${auth.allowedHardwareIds.length} device(s) linked',
            style: theme.textTheme.bodySmall?.copyWith(
              color: StitchColors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Claim Node button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showClaimNodeSheet,
            style: OutlinedButton.styleFrom(
              foregroundColor: StitchColors.primaryContainer,
              side: BorderSide(
                color: StitchColors.primaryContainer.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.add_link_rounded, size: 20),
            label: const Text(
              'CLAIM NODE',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Divider
        Container(
          height: 1,
          color: StitchColors.outlineVariant.withValues(alpha: 0.5),
        ),
        const SizedBox(height: 24),

        // Logout button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loggingOut ? null : _handleLogout,
            style: OutlinedButton.styleFrom(
              foregroundColor: StitchColors.error,
              side: BorderSide(
                color: StitchColors.error.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _loggingOut
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: StitchColors.error,
                    ),
                  )
                : const Icon(Icons.logout_rounded, size: 20),
            label: Text(
              _loggingOut ? 'LOGGING OUT...' : 'SIGN OUT',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // App version info
        Center(
          child: Text(
            'SmartPonic v2.0.0',
            style: theme.textTheme.labelSmall?.copyWith(
              color: StitchColors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Architect Tab
// ---------------------------------------------------------------------------

class _ArchitectTab extends StatefulWidget {
  final ValueNotifier<List<Map<String, dynamic>>> configNotifier;

  const _ArchitectTab({required this.configNotifier});

  @override
  State<_ArchitectTab> createState() => _ArchitectTabState();
}

class _ArchitectTabState extends State<_ArchitectTab> {
  @override
  Widget build(BuildContext context) {
    return ConfigScreen(
      configNotifier: widget.configNotifier,
      activeTabListenable: DefaultValueListenable(0),
      tabIndex: 0,
    );
  }
}

/// A simple [ValueNotifier] that always returns a fixed value and never changes.
class DefaultValueListenable<T> extends ValueNotifier<T> {
  DefaultValueListenable(T value) : super(value);

  @override
  set value(T _) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
