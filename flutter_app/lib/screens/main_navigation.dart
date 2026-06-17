import 'package:flutter/material.dart';

import '../widgets/custom_ui.dart';
import 'calibration_screen.dart';
import 'config_screen.dart';
import 'device_screen.dart';
import 'profiles_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  final ValueNotifier<List<Map<String, dynamic>>> globalConfig =
      ValueNotifier([]);
  final ValueNotifier<int> activeTab = ValueNotifier(1);

  List<Widget> get _pages {
    return [
      DeviceScreen(
        activeTabListenable: activeTab,
        tabIndex: 0,
        onLoadToConfig: (cfg) {
          globalConfig.value =
              List<Map<String, dynamic>>.from(cfg.map((e) => Map<String, dynamic>.from(e)));
          _setIndex(1);
        },
      ),
      ConfigScreen(
        configNotifier: globalConfig,
        activeTabListenable: activeTab,
        tabIndex: 1,
      ),
      ProfilesScreen(
        activeTabListenable: activeTab,
        tabIndex: 2,
        onSelectProfile: (cfg) {
          globalConfig.value =
              List<Map<String, dynamic>>.from(cfg.map((e) => Map<String, dynamic>.from(e)));
          _setIndex(1);
        },
      ),
      CalibrationScreen(
        activeTabListenable: activeTab,
        tabIndex: 3,
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
    activeTab.value = value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RepaintBoundary(
        child: IndexedStack(
          index: activeTab.value,
          children: _pages,
        ),
      ),
      bottomNavigationBar: StitchBottomNavigation(
        currentIndex: activeTab.value,
        onTap: _setIndex,
      ),
    );
  }
}
