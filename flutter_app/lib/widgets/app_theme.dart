import 'package:flutter/material.dart';

class StitchColors {
  static const background = Color(0xFF10141A);
  static const surface = Color(0xFF10141A);
  static const surfaceLowest = Color(0xFF0A0E14);
  static const surfaceLow = Color(0xFF181C22);
  static const surfaceContainer = Color(0xFF1C2026);
  static const surfaceHigh = Color(0xFF262A31);

  static const primary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF00FBFB);
  static const secondary = Color(0xFF9ECAFF);
  static const secondaryContainer = Color(0xFF1E95F2);
  static const tertiaryFixed = Color(0xFFFCE442);

  static const onSurface = Color(0xFFDFE2EB);
  static const onSurfaceVariant = Color(0xFFB9CAC9);
  static const outlineVariant = Color(0xFF3A4A49);
  static const error = Color(0xFFFFB4AB);
  static const onSecondaryContainer = Color(0xFF002B4D);

}

class AppTheme {
  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: StitchColors.primary,
      secondary: StitchColors.secondary,
      surface: StitchColors.surface,
      error: StitchColors.error,
      onPrimary: StitchColors.onSecondaryContainer,
      onSecondary: StitchColors.onSurface,
      onSurface: StitchColors.onSurface,
      onError: Color(0xFF690005),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: StitchColors.background,
      canvasColor: StitchColors.background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayMedium: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 40,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          color: StitchColors.primary,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: StitchColors.primary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: StitchColors.primary,
        ),
        titleLarge: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: StitchColors.primary,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: StitchColors.primary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: StitchColors.onSurfaceVariant,
        ),
        labelLarge: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
          color: StitchColors.secondary,
        ),
        labelMedium: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.8,
          color: StitchColors.onSurfaceVariant,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: StitchColors.surfaceLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: StitchColors.secondary, width: 1),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static LinearGradient get ctaGradient => const LinearGradient(
        colors: [StitchColors.primary, StitchColors.secondaryContainer],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static List<BoxShadow> get cyanGlowShadow => const [];
}
