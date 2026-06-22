import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Central color palette for the SmartPonic v2 dark theme.
class StitchColors {
  StitchColors._(); // Private constructor to prevent instantiation.

  // Backgrounds & surfaces
  static const Color background = Color(0xFF0A0D14);
  static const Color surface = Color(0xFF0A0D14);
  static const Color surfaceLowest = Color(0xFF0E131F);
  static const Color surfaceLow = Color(0xFF151B29);
  static const Color surfaceContainer = Color(0xFF1D263B);
  static const Color surfaceHigh = Color(0xFF2B3754);

  // Primary / accent
  static const Color primary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF00F5FF); // Neon Electric Cyan
  static const Color secondary = Color(0xFFB08CFF); // Soft Aurora Purple
  static const Color secondaryContainer = Color(0xFF1B60EC); // Quantum Blue
  static const Color tertiaryFixed = Color(0xFFFAD02C); // Sol Gold

  // On-colors
  static const Color onSurface = Color(0xFFE2E6F0);
  static const Color onSurfaceVariant = Color(0xFFA5B2CD);
  static const Color outlineVariant = Color(0xFF334163);
  static const Color error = Color(0xFFFF8E8E);
  static const Color onSecondaryContainer = primary;

  // Glassmorphism
  static const Color glassSurface = Color(0x1A1D263B);
  static const Color glassBorder = Color(0x1A334163);

  // Glass gradient sheen colors (used for improved glass effect)
  static const Color glassSheenCyan = Color(0x0D00F5FF);
  static const Color glassSheenPurple = Color(0x0DB08CFF);
  static const Color glassSpecular = Color(0x08FFFFFF);

  // Shimmer
  static const Color shimmerBase = Color(0xFF151B29);
  static const Color shimmerHighlight = Color(0xFF1D263B);

  // Trend indicators
  static const Color trendUp = Color(0xFF00FF87);
  static const Color trendDown = Color(0xFFFF8E8E);
  static const Color trendStable = Color(0xFFA5B2CD);
}

/// Design tokens — spacing and border radius constants.
///
/// All spacing values follow a 4px grid for visual rhythm consistency.
/// Use these constants instead of raw numbers throughout the app.
class StitchSpacing {
  StitchSpacing._();

  /// 4px — smallest gap (icon to text, small elements)
  static const double xs = 4;

  /// 8px — small gap (badge to text, small sections)
  static const double sm = 8;

  /// 12px — medium gap (between related elements)
  static const double md = 12;

  /// 16px — large gap (card padding, between cards)
  static const double lg = 16;

  /// 20px — extra large (screen edge padding, section spacing)
  static const double xl = 20;

  /// 24px — double extra large (section spacing, top padding)
  static const double xxl = 24;

  /// 32px — section separator
  static const double xxxl = 32;

  /// 40px — major section break
  static const double section = 40;

  /// 48px — page-level padding
  static const double page = 48;

  /// 120px — bottom padding to clear navigation bar
  static const double pageBottom = 120;
}

/// Border radius tokens for consistent corner rounding.
class StitchRadius {
  StitchRadius._();

  /// 6px — small badges, tags, pills
  static const double badge = 6;

  /// 12px — buttons, icon containers, small cards
  static const double button = 12;

  /// 16px — input fields, text form fields
  static const double input = 16;

  /// 20px — cards, panels, default containers
  static const double card = 20;

  /// 28px — bottom sheets, modals
  static const double sheet = 28;

  /// BorderRadius objects for convenience.
  static const BorderRadius badgeBorder = BorderRadius.all(Radius.circular(badge));
  static const BorderRadius buttonBorder = BorderRadius.all(Radius.circular(button));
  static const BorderRadius inputBorder = BorderRadius.all(Radius.circular(input));
  static const BorderRadius cardBorder = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetBorder = BorderRadius.all(Radius.circular(sheet));
}

/// Theme data and visual assets for the SmartPonic v2 dark theme.
class AppTheme {
  AppTheme._(); // Private constructor to prevent instantiation.

  // ---------------------------------------------------------------------------
  // Theme data
  // ---------------------------------------------------------------------------

  /// The complete dark theme for the app.
  static final ThemeData darkTheme = _buildDarkTheme();

  static ThemeData _buildDarkTheme() {
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
      splashFactory: InkRipple.splashFactory,
      highlightColor: StitchColors.outlineVariant.withValues(alpha: 0.15),
      splashColor: StitchColors.primaryContainer.withValues(alpha: 0.2),
      fontFamily: 'Inter',
      textTheme: const TextTheme(
        displayMedium: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 38,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          color: StitchColors.primary,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
          color: StitchColors.primary,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 22,
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
          fontFamily: 'SpaceGrotesk',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.3,
          color: StitchColors.primaryContainer,
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
          borderRadius: StitchRadius.inputBorder,
          borderSide: const BorderSide(color: StitchColors.outlineVariant, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: StitchRadius.inputBorder,
          borderSide: const BorderSide(color: StitchColors.outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: StitchRadius.inputBorder,
          borderSide: const BorderSide(color: StitchColors.primaryContainer, width: 1.5),
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

  // ---------------------------------------------------------------------------
  // Gradients
  // ---------------------------------------------------------------------------

  /// Call-to-action gradient from primaryContainer to secondaryContainer.
  static const LinearGradient ctaGradient = LinearGradient(
    colors: [StitchColors.primaryContainer, StitchColors.secondaryContainer],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Glass panel gradient — subtle cyan-to-purple sheen over the glass surface.
  static const LinearGradient glassGradient = LinearGradient(
    colors: [
      StitchColors.glassSheenCyan,
      StitchColors.glassSurface,
      StitchColors.glassSheenPurple,
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// pH bar gradient spanning the colour spectrum.
  static const LinearGradient phGradient = LinearGradient(
    colors: [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
    ],
  );

  /// Temperature bar gradient from secondaryContainer to primaryContainer.
  static const LinearGradient tempGradient = LinearGradient(
    colors: [
      StitchColors.secondaryContainer,
      StitchColors.primaryContainer,
    ],
  );

  /// TDS bar gradient from blue to green.
  static const LinearGradient tdsGradient = LinearGradient(
    colors: [Color(0xFF00B4D8), Color(0xFF00FF87)],
  );

  // ---------------------------------------------------------------------------
  // Shadows
  // ---------------------------------------------------------------------------

  /// Cyan glow shadow used for interactive elements.
  static final List<BoxShadow> cyanGlowShadow = [
    BoxShadow(
      color: StitchColors.primaryContainer.withValues(alpha: 0.25),
      blurRadius: 12,
      spreadRadius: 1,
    ),
    BoxShadow(
      color: StitchColors.secondaryContainer.withValues(alpha: 0.15),
      blurRadius: 24,
      spreadRadius: 0,
    ),
  ];

  /// Glassmorphism shadow used for frosted-glass panels.
  static final List<BoxShadow> glassShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.3),
      blurRadius: 20,
      spreadRadius: 0,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: StitchColors.primaryContainer.withValues(alpha: 0.06),
      blurRadius: 40,
      spreadRadius: 0,
    ),
  ];

  /// Subtle shadow used for default panels.
  static final List<BoxShadow> subtleShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.2),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
}
