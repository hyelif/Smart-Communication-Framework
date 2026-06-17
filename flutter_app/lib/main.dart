import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'core/dependency_injection.dart';
import 'app.dart';

/// User-friendly error screen shown in place of the default red error box
/// when a widget throws during build.
class _ErrorScreen extends StatelessWidget {
  final FlutterErrorDetails details;

  const _ErrorScreen({required this.details});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0A0D14),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFFF8E8E), size: 64),
              const SizedBox(height: 24),
              Text(
                'Something went wrong',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFFE2E6F0),
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                details.summary.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFA5B2CD),
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _restartApp(),
                icon: const Icon(Icons.refresh),
                label: const Text('Restart'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _restartApp() {
    // Push a new app entry so the user can recover without a full process kill.
    // In production you might use a package like `flutter_restart`.
    runApp(const MyApp());
  }
}

void main() async {
  // ---- Global error handlers ----

  // Replace the default red error box with a branded error screen.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    // In debug mode, still print the full stack to the console.
    // ignore: avoid_print
    if (details.stack != null) print(details.exception);
    return _ErrorScreen(details: details);
  };

  // Catch unhandled errors that escape the zone (e.g. timers, callbacks).
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    // ignore: avoid_print
    print('[Unhandled Error] $error\n$stack');
    return true; // We handled it — don't crash the process.
  };

  WidgetsFlutterBinding.ensureInitialized();

  // Show a splash / loading indicator while dependencies are set up.
  runApp(
    _SplashWrapper(
      future: setupDependencies(),
      child: const MyApp(),
    ),
  );
}

/// A minimal splash screen that waits for [future] to complete, then shows
/// [child]. If the future fails, it shows an error state.
class _SplashWrapper extends StatefulWidget {
  final Future<void> future;
  final Widget child;

  const _SplashWrapper({required this.future, required this.child});

  @override
  State<_SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<_SplashWrapper> {
  AsyncSnapshot<void> _snapshot = const AsyncSnapshot<void>.waiting();

  @override
  void initState() {
    super.initState();
    widget.future.then((_) {
      if (mounted) {
        setState(() => _snapshot = const AsyncSnapshot<void>.withData(ConnectionState.done, null));
      }
    }).catchError((Object error, StackTrace stack) {
      if (mounted) {
        setState(() => _snapshot = AsyncSnapshot<void>.withError(ConnectionState.done, error, stack));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0D14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFFFFF),
          secondary: Color(0xFFB08CFF),
          surface: Color(0xFF0A0D14),
          error: Color(0xFFFF8E8E),
          onPrimary: Color(0xFFFFFFFF),
          onSecondary: Color(0xFFE2E6F0),
          onSurface: Color(0xFFE2E6F0),
          onError: Color(0xFF690005),
        ),
      ),
      home: Builder(
        builder: (context) {
          if (_snapshot.connectionState == ConnectionState.waiting) {
            return const _LoadingIndicator();
          }
          if (_snapshot.hasError) {
            return _InitError(
              error: _snapshot.error,
              stack: _snapshot.stackTrace,
              onRetry: () {
                setState(() => _snapshot = const AsyncSnapshot<void>.waiting());
                widget.future.then((_) {
                  if (mounted) {
                    setState(() => _snapshot = const AsyncSnapshot<void>.withData(ConnectionState.done, null));
                  }
                }).catchError((Object e, StackTrace s) {
                  if (mounted) {
                    setState(() => _snapshot = AsyncSnapshot<void>.withError(ConnectionState.done, e, s));
                  }
                });
              },
            );
          }
          // Future completed successfully — switch to the real app.
          return widget.child;
        },
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00F5FF)),
            SizedBox(height: 24),
            Text(
              'Initializing…',
              style: TextStyle(
                color: Color(0xFFA5B2CD),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InitError extends StatelessWidget {
  final Object? error;
  final StackTrace? stack;
  final VoidCallback onRetry;

  const _InitError({required this.error, required this.stack, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, color: Color(0xFFFF8E8E), size: 64),
              const SizedBox(height: 24),
              Text(
                'Startup failed',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: const Color(0xFFE2E6F0),
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                error?.toString() ?? 'Unknown error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFA5B2CD),
                    ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
