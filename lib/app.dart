import 'package:flutter/material.dart';

import 'screens/main_navigation.dart';
import 'widgets/app_theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ESP32 Architect',
      theme: AppTheme.darkTheme,
      home: const MainNavigation(),
    );
  }
}
