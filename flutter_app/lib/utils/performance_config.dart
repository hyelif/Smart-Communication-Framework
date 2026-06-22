import 'package:flutter/material.dart';

/// Device performance tiers for adaptive visual effects.
///
/// Low-end devices get reduced or disabled effects (no blur, no animations)
/// to maintain smooth 60fps. High-end devices get full visual polish.
enum DeviceTier { low, mid, high }

/// Detects device capability and provides performance-aware decisions.
///
/// Usage:
/// ```dart
/// final perf = PerformanceConfig.of(context);
/// if (perf.enableBlur) // ... show BackdropFilter
/// ```
class PerformanceConfig {
  final DeviceTier tier;

  const PerformanceConfig._(this.tier);

  /// Resolve the performance tier for the current build context.
  ///
  /// Heuristic: logical pixels × device pixel ratio.
  /// - < 800px → low (budget phones)
  /// - 800–1400px → mid (mid-range)
  /// - > 1400px → high (flagship phones, tablets)
  static PerformanceConfig of(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final pixels = size.shortestSide * dpr;

    final tier = switch (pixels) {
      < 800 => DeviceTier.low,
      < 1400 => DeviceTier.mid,
      _ => DeviceTier.high,
    };

    return PerformanceConfig._(tier);
  }

  /// Whether to render BackdropFilter blur effects.
  bool get enableBlur => tier != DeviceTier.low;

  /// Whether to run continuous animations (pulse, shimmer, backgrounds).
  bool get enableAnimations => tier != DeviceTier.low;

  /// Whether to show the animated liquid background.
  bool get enableAnimatedBackground => tier == DeviceTier.high;

  /// Whether to use spring-based touch feedback.
  bool get enableSpringTouch => tier != DeviceTier.low;

  /// Maximum blur sigma for BackdropFilter (higher = more GPU cost).
  double get maxBlurSigma => switch (tier) {
    DeviceTier.low => 0, // no blur
    DeviceTier.mid => 4,
    DeviceTier.high => 6,
  };
}
