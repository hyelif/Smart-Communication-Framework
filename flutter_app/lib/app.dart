import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'screens/main_navigation.dart';
import 'services/api_service.dart';
import 'services/turso_service.dart';
import 'widgets/app_theme.dart';

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      // App is being terminated — release HTTP clients.
      TursoService.dispose();
      ApiService.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);

    return MaterialApp(
      navigatorKey: MyApp.navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'SmartPonic',
      theme: AppTheme.darkTheme,
      home: authState.isLoggedIn
          ? const MainNavigation()
          : const LoginScreen(),
    );
  }
}
