import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'app_theme.dart';

class StitchBounce extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const StitchBounce({
    super.key,
    required this.child,
    this.onTap,
  });

  @override
  State<StitchBounce> createState() => _StitchBounceState();
}

class _StitchBounceState extends State<StitchBounce> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.onTap != null) _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (widget.onTap != null) _controller.reverse();
  }

  void _onTapCancel() {
    if (widget.onTap != null) _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

class StitchScaffold extends StatelessWidget {
  final Widget body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;

  const StitchScaffold({
    super.key,
    required this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StitchColors.background,
      body: SafeArea(bottom: false, child: body),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

class StitchTopBar extends StatelessWidget {
  final String section;
  final IconData? trailingIcon;
  final Widget? trailing;

  const StitchTopBar({
    super.key,
    required this.section,
    this.trailingIcon = Icons.battery_charging_full_rounded,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(
          color: StitchColors.surfaceLowest,
          border: Border(
            bottom: BorderSide(color: StitchColors.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.memory_rounded,
              color: StitchColors.primaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'SMARTPONIC v2',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                      color: StitchColors.primary,
                    ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: StitchColors.surfaceLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: StitchColors.outlineVariant),
              ),
              child: Text(
                section.toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: StitchColors.primaryContainer,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
              ),
            ),
            if (trailing != null || trailingIcon != null) ...[
              const SizedBox(width: 12),
              trailing ??
                  Icon(
                    trailingIcon ?? Icons.battery_charging_full_rounded,
                    color: StitchColors.primaryContainer,
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class StitchBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const StitchBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    _NavItem(Icons.flash_on_rounded, 'DEVICE'),
    _NavItem(Icons.architecture_rounded, 'ARCHITECT'),
    _NavItem(Icons.inventory_2_outlined, 'VAULT'),
    _NavItem(Icons.tune_rounded, 'CALIBRATE'),
  ];

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        decoration: const BoxDecoration(
          color: StitchColors.surfaceLowest,
          border: Border(
            top: BorderSide(color: StitchColors.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = index == currentIndex;
              return Expanded(
                child: StitchBounce(
                  onTap: () => onTap(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                  decoration: BoxDecoration(
                    color: selected
                        ? StitchColors.surfaceContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected
                          ? StitchColors.outlineVariant.withValues(alpha: 0.5)
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedScale(
                        scale: selected ? 1.12 : 1.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          item.icon,
                          color: selected
                              ? StitchColors.primaryContainer
                              : StitchColors.onSurfaceVariant,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: selected
                                  ? StitchColors.primaryContainer
                                  : StitchColors.onSurfaceVariant,
                              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem(this.icon, this.label);
}

class StitchPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final bool glow;
  final bool glass;
  final BorderRadius? borderRadius;

  const StitchPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.glow = false,
    this.glass = false,
    this.borderRadius,
  });

  const StitchPanel.glass({
    Key? key,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    BorderRadius? borderRadius,
  }) : this(
         key: key,
         child: child,
         padding: padding,
         glass: true,
         borderRadius: borderRadius,
         color: StitchColors.glassSurface,
       );

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: glass
            ? StitchColors.glassSurface
            : (color ?? StitchColors.surfaceLow),
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        border: Border.all(
          color: glass
              ? StitchColors.glassBorder
              : StitchColors.outlineVariant.withValues(alpha: 0.8),
          width: 1,
        ),
        boxShadow: glow
            ? AppTheme.cyanGlowShadow
            : (glass ? AppTheme.glassShadow : AppTheme.subtleShadow),
      ),
      child: child,
    );

    if (!glass) return panel;

    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: panel,
      ),
    );
  }
}

class StitchSectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;

  const StitchSectionLabel(this.text, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: StitchColors.primaryContainer,
          fontWeight: FontWeight.w800,
        );

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: StitchColors.primaryContainer),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            text.toUpperCase(),
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class StitchPrimaryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const StitchPrimaryButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
  });

  @override
  Widget build(BuildContext context) {
    return StitchBounce(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.ctaGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppTheme.cyanGlowShadow,
        ),
        child: Padding(
          padding: padding,
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class StitchGhostButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;

  const StitchGhostButton({
    super.key,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StitchBounce(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: StitchColors.surfaceLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: StitchColors.outlineVariant,
            width: 1,
          ),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            color: StitchColors.secondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class StitchRefreshButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool busy;
  final String label;

  const StitchRefreshButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.label = 'REFRESH',
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: StitchGhostButton(
        onPressed: busy ? null : onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: StitchColors.secondary),
              )
            else
              const Icon(Icons.refresh_rounded, size: 16),
            const SizedBox(width: 8),
            Text(busy ? 'REFRESHING...' : label),
          ],
        ),
      ),
    );
  }
}

void showStitchMessage(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: isError ? StitchColors.error : StitchColors.primaryContainer,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: isError ? 2200 : 1600),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isError
                ? StitchColors.error.withValues(alpha: 0.3)
                : StitchColors.primaryContainer.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        backgroundColor: StitchColors.surfaceContainer,
      ),
    );
}

class StitchStatusDot extends StatelessWidget {
  final Color color;
  final double size;

  const StitchStatusDot({
    super.key,
    this.color = StitchColors.primaryContainer,
    this.size = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

class StitchPulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final double pulseRadius;
  final Duration pulseDuration;

  const StitchPulseDot({
    super.key,
    this.color = StitchColors.primaryContainer,
    this.size = 10,
    this.pulseRadius = 16,
    this.pulseDuration = const Duration(milliseconds: 1500),
  });

  @override
  State<StitchPulseDot> createState() => _StitchPulseDotState();
}

class _StitchPulseDotState extends State<StitchPulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.pulseDuration)
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return SizedBox(
          width: widget.pulseRadius * 2,
          height: widget.pulseRadius * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.pulseRadius * 2 * (0.4 + 0.6 * _pulse.value),
                height: widget.pulseRadius * 2 * (0.4 + 0.6 * _pulse.value),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.15 * (1.0 - _pulse.value)),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4 + 0.3 * _pulse.value),
                      blurRadius: 6 + 4 * _pulse.value,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class StitchShimmer extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  final Color? baseColor;
  final Color? highlightColor;

  const StitchShimmer({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 12,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<StitchShimmer> createState() => _StitchShimmerState();
}

class _StitchShimmerState extends State<StitchShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shift;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shift = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shift,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: [
                widget.baseColor ?? StitchColors.shimmerBase,
                widget.highlightColor ?? StitchColors.shimmerHighlight,
                widget.baseColor ?? StitchColors.shimmerBase,
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(_shift.value, 0.0),
              end: Alignment(-_shift.value, 0.0),
            ),
          ),
        );
      },
    );
  }
}

class StitchSkeletonPanel extends StatelessWidget {
  final double height;
  final int lineCount;
  final bool showIcon;

  const StitchSkeletonPanel({
    super.key,
    this.height = 120,
    this.lineCount = 3,
    this.showIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: StitchColors.surfaceLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: StitchColors.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        children: [
          if (showIcon)
            const Padding(
              padding: EdgeInsets.only(right: 14),
              child: StitchShimmer(
                width: 46,
                height: 46,
                borderRadius: 12,
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(lineCount, (i) {
                return Padding(
                  padding: EdgeInsets.only(bottom: i < lineCount - 1 ? 10 : 0),
                  child: StitchShimmer(
                    height: 12,
                    width: i == 0 ? 0.6 : (i == lineCount - 1 ? 0.4 : 0.8),
                    borderRadius: 6,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class StitchEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const StitchEmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: StitchPanel(
        padding: const EdgeInsets.all(24),
        glow: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: StitchColors.secondary, size: 34),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

