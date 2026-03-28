import 'package:flutter/material.dart';

import 'app_theme.dart';

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
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _ScaffoldBackdrop(),
          RepaintBoundary(
            child: SafeArea(bottom: false, child: body),
          ),
        ],
      ),
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
        decoration: BoxDecoration(
          color: StitchColors.surfaceHigh.withValues(alpha: 0.94),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
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
                'ESP32 ARCHITECT',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.4,
                    ),
              ),
            ),
            Text(
              section.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: StitchColors.primaryContainer,
                  ),
            ),
            const SizedBox(width: 12),
            trailing ??
                Icon(
                  trailingIcon ?? Icons.battery_charging_full_rounded,
                  color: StitchColors.primaryContainer,
                ),
          ],
        ),
      ),
    );
  }
}

class _ScaffoldBackdrop extends StatelessWidget {
  const _ScaffoldBackdrop();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              StitchColors.surfaceLowest,
              StitchColors.background,
              StitchColors.surface,
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -60,
              child: _GlowOrb(
                size: 220,
                color: Color(0x0F00FBFB),
              ),
            ),
            Positioned(
              top: 260,
              left: -90,
              child: _GlowOrb(
                size: 180,
                color: Color(0x0D1E95F2),
              ),
            ),
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
    _NavItem(Icons.insights_outlined, 'DATA'),
  ];

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
        decoration: BoxDecoration(
          color: StitchColors.surfaceHigh.withValues(alpha: 0.96),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.04)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = index == currentIndex;
              return GestureDetector(
                onTap: () => onTap(index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? StitchColors.primaryContainer.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: selected
                            ? StitchColors.primaryContainer
                            : StitchColors.onSurfaceVariant,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: selected
                                  ? StitchColors.primaryContainer
                                  : StitchColors.onSurfaceVariant,
                            ),
                      ),
                    ],
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
  final BorderRadius? borderRadius;

  const StitchPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.glow = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? StitchColors.surfaceLow,
        borderRadius: borderRadius ?? BorderRadius.circular(24),
        boxShadow: glow ? AppTheme.cyanGlowShadow : null,
      ),
      child: child,
    );
  }
}

class StitchSectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;

  const StitchSectionLabel(this.text, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: StitchColors.primaryContainer,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: StitchColors.primaryContainer),
          const SizedBox(width: 6),
        ],
        Text(text.toUpperCase(), style: style),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppTheme.ctaGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppTheme.cyanGlowShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(padding: padding, child: child),
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
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: StitchColors.outlineVariant.withValues(alpha: 0.3),
        ),
        foregroundColor: StitchColors.secondary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: child,
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
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.refresh_rounded, size: 18),
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
        content: Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isError ? StitchColors.primary : StitchColors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: Duration(milliseconds: isError ? 1800 : 1200),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        backgroundColor: isError
            ? const Color(0xFF2A3038)
            : StitchColors.surfaceHigh,
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
              style: Theme.of(context).textTheme.headlineMedium,
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

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }
}
