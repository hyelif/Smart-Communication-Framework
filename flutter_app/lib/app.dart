import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'screens/main_navigation.dart';
import 'widgets/app_theme.dart';

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'SmartPonic',
      theme: AppTheme.darkTheme,
      home: authState.isLoggedIn
          ? const MainNavigation()
          : const LoginScreen(),
    );
  }
}
