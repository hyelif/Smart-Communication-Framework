import 'package:flutter/material.dart';

import 'screens/main_navigation.dart';
import 'widgets/app_theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'ESP32 Architect',
      theme: AppTheme.darkTheme,
      home: const MainNavigation(),
    );
  }
}
