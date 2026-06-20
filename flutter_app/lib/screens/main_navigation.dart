import 'package:flutter/material.dart';

import '../features/devices/device_list_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';
import '../widgets/custom_ui.dart';
import 'config_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final ValueNotifier<List<Map<String, dynamic>>> globalConfig =
      ValueNotifier([]);
  final ValueNotifier<int> activeTab = ValueNotifier(0);

  /// Cached page widgets — created once in [initState] to avoid
  /// recreating them on every [build] call.
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = _buildPages();
  }

  List<Widget> _buildPages() {
    return [
      // HOME tab
      RepaintBoundary(
        child: HomeScreen(
          activeTabListenable: activeTab,
          tabIndex: 0,
        ),
      ),
      // DEVICES tab
      RepaintBoundary(
        child: DeviceListScreen(
          activeTabListenable: activeTab,
          tabIndex: 1,
        ),
      ),
      // ARCHITECT tab
      RepaintBoundary(
        child: ConfigScreen(
          configNotifier: globalConfig,
          activeTabListenable: activeTab,
          tabIndex: 2,
        ),
      ),
      // SETTINGS tab (Vault + Calibration)
      RepaintBoundary(
        child: SettingsScreen(
          activeTabListenable: activeTab,
          tabIndex: 3,
          onSelectProfile: (cfg) {
            globalConfig.value =
                List<Map<String, dynamic>>.from(cfg.map((e) => Map<String, dynamic>.from(e)));
            _setIndex(2);
          },
        ),
      ),
    ];
  }

  @override
  void dispose() {
    activeTab.dispose();
    globalConfig.dispose();
    super.dispose();
  }

  void _setIndex(int value) {
    if (value == activeTab.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          activeTab.value = value;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: activeTab.value,
        children: _pages,
      ),
      bottomNavigationBar: StitchBottomNavigation(
        currentIndex: activeTab.value,
        onTap: _setIndex,
      ),
    );
  }
}
