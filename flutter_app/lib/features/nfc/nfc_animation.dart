import 'package:flutter/material.dart';

import '../../widgets/app_theme.dart';

/// Animated NFC telemetry visualization with ripple effect.
class NfcAnimatedTelemetry extends StatefulWidget {
  final bool isError;
  final bool isComplete;

  const NfcAnimatedTelemetry({
    super.key,
    required this.isError,
    required this.isComplete,
  });

  @override
  State<NfcAnimatedTelemetry> createState() => _NfcAnimatedTelemetryState();
}

class _NfcAnimatedTelemetryState extends State<NfcAnimatedTelemetry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) => CustomPaint(
        size: const Size(180, 180),
        painter: NfcTelemetryPainter(
          animationValue: _animController.value,
          isError: widget.isError,
          isComplete: widget.isComplete,
        ),
      ),
    );
  }
}

class NfcTelemetryPainter extends CustomPainter {
  final double animationValue;
  final bool isError;
  final bool isComplete;

  NfcTelemetryPainter({
    required this.animationValue,
    this.isError = false,
    this.isComplete = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final color = isError
        ? Colors.red
        : (isComplete ? const Color(0xFF00FF87) : StitchColors.primaryContainer);

    // Draw phone outline
    const phoneWidth = 44.0;
    const phoneHeight = 72.0;
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: phoneWidth, height: phoneHeight),
      const Radius.circular(8),
    );

    final phonePaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawRRect(phoneRect, phonePaint);

    // Draw home button
    canvas.drawCircle(
      Offset(center.dx, center.dy + phoneHeight / 2 - 8),
      3.0,
      phonePaint,
    );

    // Draw NFC icon
    final iconPaint = Paint()
      ..color = color.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawArc(
      Rect.fromCenter(center: Offset(center.dx, center.dy - 6), width: 14, height: 14),
      -3.14 / 4,
      3.14 / 2,
      false,
      iconPaint,
    );
    canvas.drawArc(
      Rect.fromCenter(center: Offset(center.dx, center.dy - 6), width: 22, height: 22),
      -3.14 / 4,
      3.14 / 2,
      false,
      iconPaint,
    );

    // Draw ripples
    final maxRadius = size.width / 2.2;
    for (int i = 0; i < 3; i++) {
      final rippleVal = (animationValue + i / 3.0) % 1.0;
      final radius = rippleVal * maxRadius;
      final opacity = (1.0 - rippleVal) * 0.45;
      paint.color = color.withValues(alpha: opacity);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant NfcTelemetryPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.isError != isError ||
        oldDelegate.isComplete != isComplete;
  }
}
