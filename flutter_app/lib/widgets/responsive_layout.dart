import 'package:flutter/material.dart';

/// Breakpoint constants for responsive layouts.
class StitchBreakpoints {
  StitchBreakpoints._();

  /// Screens narrower than this are considered mobile.
  static const double mobile = 600;

  /// Screens between [mobile] and [tablet] are tablet-sized.
  static const double tablet = 1024;

  /// Screens wider than [tablet] are desktop-sized.
  static const double desktop = 1024;
}

/// Device type inferred from screen width.
enum StitchScreenSize { mobile, tablet, desktop }

/// Resolve the current screen size from a [BuildContext].
StitchScreenSize stitchScreenSizeOf(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  if (width < StitchBreakpoints.mobile) return StitchScreenSize.mobile;
  if (width < StitchBreakpoints.tablet) return StitchScreenSize.tablet;
  return StitchScreenSize.desktop;
}

/// Whether the current screen is at least tablet-sized.
bool stitchIsTabletOrWider(BuildContext context) {
  return MediaQuery.of(context).size.width >= StitchBreakpoints.mobile;
}

/// Whether the current screen is desktop-sized.
bool stitchIsDesktop(BuildContext context) {
  return MediaQuery.of(context).size.width >= StitchBreakpoints.desktop;
}

/// A widget that renders different layouts based on screen width.
///
/// Usage:
/// ```dart
/// ResponsiveLayout(
///   mobile: MobileWidget(),
///   tablet: TabletWidget(),
///   desktop: DesktopWidget(),
/// )
/// ```
class ResponsiveLayout extends StatelessWidget {
  final Widget mobile;
  final Widget? tablet;
  final Widget desktop;

  const ResponsiveLayout({
    super.key,
    required this.mobile,
    this.tablet,
    required this.desktop,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < StitchBreakpoints.mobile) {
          return mobile;
        }
        if (constraints.maxWidth < StitchBreakpoints.tablet) {
          return tablet ?? desktop;
        }
        return desktop;
      },
    );
  }
}

/// Returns the optimal number of grid columns for the current screen width.
///
/// - Mobile: [mobileColumns] (default 2)
/// - Tablet: [tabletColumns] (default 3)
/// - Desktop: [desktopColumns] (default 4)
int stitchGridColumns(
  BuildContext context, {
  int mobileColumns = 2,
  int tabletColumns = 3,
  int desktopColumns = 4,
}) {
  final size = stitchScreenSizeOf(context);
  switch (size) {
    case StitchScreenSize.mobile:
      return mobileColumns;
    case StitchScreenSize.tablet:
      return tabletColumns;
    case StitchScreenSize.desktop:
      return desktopColumns;
  }
}
