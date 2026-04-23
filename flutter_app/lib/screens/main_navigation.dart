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
  int index = 1;

  final ValueNotifier<List<Map<String, dynamic>>> globalConfig =
      ValueNotifier([]);
  final ValueNotifier<int> activeTab = ValueNotifier(1);

  @override
  void initState() {
    super.initState();
    _pages[1] = _buildPage(1);
  }

  final Map<int, Widget> _pages = {};

  Widget _buildPage(int pageIndex) {
    switch (pageIndex) {
      case 0:
        return DeviceScreen(
          activeTabListenable: activeTab,
          tabIndex: 0,
          onLoadToConfig: (cfg) {
            globalConfig.value = cfg;
            _setIndex(1);
          },
        );
      case 1:
        return ConfigScreen(
          configNotifier: globalConfig,
          activeTabListenable: activeTab,
          tabIndex: 1,
        );
      case 2:
        return ProfilesScreen(
          activeTabListenable: activeTab,
          tabIndex: 2,
          onSelectProfile: (cfg) {
            globalConfig.value = cfg;
            _setIndex(1);
          },
        );
      case 3:
        return CalibrationScreen(
          activeTabListenable: activeTab,
          tabIndex: 3,
        );
      default:
        return const StitchEmptyState(
          title: 'Analytics Pipeline Offline',
          subtitle: 'This panel is reserved for future signal telemetry.',
          icon: Icons.insights_outlined,
        );
    }
  }

  @override
  void dispose() {
    activeTab.dispose();
    globalConfig.dispose();
    super.dispose();
  }

  void _setIndex(int value) {
    if (value == index) return;
    _pages.putIfAbsent(value, () => _buildPage(value));
    activeTab.value = value;
    setState(() => index = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RepaintBoundary(
        child: IndexedStack(
          index: index,
          children: List.generate(
            4,
            (pageIndex) => _pages[pageIndex] ?? const SizedBox.shrink(),
          ),
        ),
      ),
      bottomNavigationBar: StitchBottomNavigation(
        currentIndex: index,
        onTap: _setIndex,
      ),
    );
  }
}
