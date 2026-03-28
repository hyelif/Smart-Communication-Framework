import 'package:flutter/material.dart';
import '../widgets/custom_ui.dart';
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

  // ✅ Move pages HERE (inside class)
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();

    pages = [
      DeviceScreen(
        onLoadToConfig: (cfg) {
          globalConfig.value = cfg;
          setState(() => index = 1);
        },
      ),
      ConfigScreen(configNotifier: globalConfig),
      ProfilesScreen(
        onSelectProfile: (cfg) {
          globalConfig.value = cfg;
          setState(() => index = 1);
        },
      ),
      const StitchEmptyState(
        title: 'Analytics Pipeline Offline',
        subtitle: 'This panel is reserved for future signal telemetry.',
        icon: Icons.insights_outlined,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: StitchBottomNavigation(
        currentIndex: index,
        onTap: (value) {
          if (value == index) return;
          setState(() => index = value);
        },
      ),
    );
  }
}
