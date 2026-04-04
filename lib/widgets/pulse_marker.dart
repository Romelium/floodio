import 'dart:math';

import 'package:flutter/material.dart';

class PulseMarker extends StatefulWidget {
  final Color color;
  final double size;
  final Widget child;
  final bool isRadar;

  const PulseMarker({
    super.key,
    this.color = Colors.blue,
    this.size = 24.0,
    this.isRadar = false,
    required this.child,
  });

  @override
  State<PulseMarker> createState() => _PulseMarkerState();
}

class _PulseMarkerState extends State<PulseMarker> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              size: Size(widget.size * 4, widget.size * 4),
              painter: _PulsePainter(
                progress: _controller.value,
                color: widget.color,
                baseSize: widget.size,
                isRadar: widget.isRadar,
              ),
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _PulsePainter extends CustomPainter {
  final double progress;
  final Color color;
  final double baseSize;
  final bool isRadar;

  _PulsePainter({
    required this.progress,
    required this.color,
    required this.baseSize,
    required this.isRadar,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    void drawRipple(double delay) {
      double currentProgress = (progress - delay) % 1.0;
      if (currentProgress < 0) currentProgress += 1.0;

      // Ease out curve for expanding
      double curvedProgress = Curves.easeOutQuart.transform(currentProgress);
      
      final startRadius = baseSize / 2;
      final radius = startRadius + (maxRadius - startRadius) * curvedProgress;
      final opacity = 1.0 - curvedProgress;

      final strokePaint = Paint()
        ..color = color.withValues(alpha: opacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * opacity;

      canvas.drawCircle(center, radius, strokePaint);

      final fillPaint = Paint()
        ..color = color.withValues(alpha: opacity * 0.3)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(center, radius, fillPaint);
    }

    drawRipple(0.0);
    drawRipple(0.33);
    drawRipple(0.66);

    if (isRadar) {
      final sweepPaint = Paint()
        ..shader = SweepGradient(
          colors: [
            color.withValues(alpha: 0.0),
            color.withValues(alpha: 0.05),
            color.withValues(alpha: 0.2),
            color.withValues(alpha: 0.6),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 0.85, 0.99, 1.0],
          transform: GradientRotation(progress * 2 * pi - pi / 2),
        ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
        ..blendMode = BlendMode.srcOver
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: maxRadius),
        progress * 2 * pi - pi / 2, // Start angle
        pi / 2, // Sweep angle (90 degrees)
        true,
        sweepPaint,
      );
      
      // Draw scanner line
      final lineAngle = progress * 2 * pi - pi / 2;
      final lineEnd = center + Offset(cos(lineAngle) * maxRadius, sin(lineAngle) * maxRadius);

      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      canvas.drawLine(center, lineEnd, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulsePainter oldDelegate) {
    return oldDelegate.progress != progress || 
           oldDelegate.color != color ||
           oldDelegate.baseSize != baseSize ||
           oldDelegate.isRadar != isRadar;
  }
}
