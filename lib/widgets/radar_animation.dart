import 'dart:math';
import 'package:flutter/material.dart';

class RadarAnimation extends StatefulWidget {
  final double size;
  final Color color;
  final bool isPowerSave;

  const RadarAnimation({
    super.key,
    this.size = 100.0,
    this.color = Colors.blue,
    this.isPowerSave = false,
  });

  @override
  State<RadarAnimation> createState() => _RadarAnimationState();
}

class _RadarAnimationState extends State<RadarAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (!widget.isPowerSave) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RadarAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPowerSave != oldWidget.isPowerSave) {
      if (widget.isPowerSave) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RadarPainter(
              progress: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RadarPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);

    // Draw background circle
    final bgPaint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // Draw crosshairs
    final crosshairPaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    // Draw grid
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    
    final double gridSize = radius / 4;
    for (double x = center.dx % gridSize; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = center.dy % gridSize; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    canvas.restore();

    _drawDashedLine(canvas, Offset(center.dx, center.dy - radius), Offset(center.dx, center.dy + radius), crosshairPaint);
    _drawDashedLine(canvas, Offset(center.dx - radius, center.dy), Offset(center.dx + radius, center.dy), crosshairPaint);

    // Draw concentric circles
    final circlePaint = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, radius * 0.33, circlePaint);
    canvas.drawCircle(center, radius * 0.66, circlePaint);
    
    // Outer rim
    final rimPaint = Paint()
      ..color = color.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, rimPaint);

    // Add some tick marks on the outer rim
    final tickPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    for (int i = 0; i < 12; i++) {
      final angle = i * pi / 6;
      final start = center + Offset(cos(angle) * (radius - 6), sin(angle) * (radius - 6));
      final end = center + Offset(cos(angle) * radius, sin(angle) * radius);
      canvas.drawLine(start, end, tickPaint);
    }

    // Draw blips
    final blips = [
      const Offset(0.15, 0.6), // angle (0-1), distance (0-1)
      const Offset(0.45, 0.3),
      const Offset(0.75, 0.8),
      const Offset(0.85, 0.4),
    ];

    for (final blip in blips) {
      final blipAngle = blip.dx;
      final blipDist = blip.dy * radius;
      
      // Calculate angular distance from current sweep line
      double angleDiff = progress - blipAngle;
      if (angleDiff < 0) angleDiff += 1.0;
      
      // Brightness spikes when sweep passes, then fades
      double opacity = 0.0;
      if (angleDiff < 0.3) {
        opacity = 1.0 - (angleDiff / 0.3);
      }
      
      if (opacity > 0) {
        final blipPos = center + Offset(cos(blipAngle * 2 * pi - pi/2) * blipDist, sin(blipAngle * 2 * pi - pi/2) * blipDist);
        
        // Glow
        final glowPaint = Paint()
          ..color = color.withValues(alpha: opacity * 0.8)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawCircle(blipPos, 4.0 + (2.0 * opacity), glowPaint);
        
        // Core
        final corePaint = Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(blipPos, 2.0, corePaint);

        // Expanding ring
        final ringPaint = Paint()
          ..color = color.withValues(alpha: opacity * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        canvas.drawCircle(blipPos, 8.0 * (1.0 - opacity), ringPaint);
      }
    }

    // Draw sweeping gradient
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.05),
          color.withValues(alpha: 0.2),
          color.withValues(alpha: 0.8),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 0.85, 0.99, 1.0],
        transform: GradientRotation(progress * 2 * pi - pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..blendMode = BlendMode.srcOver
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      progress * 2 * pi - pi / 2, // Start angle
      pi / 2, // Sweep angle (90 degrees)
      true,
      sweepPaint,
    );
    
    // Draw scanner line
    final lineAngle = progress * 2 * pi - pi / 2;
    final lineEnd = center + Offset(cos(lineAngle) * radius, sin(lineAngle) * radius);
    
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawLine(center, lineEnd, linePaint);

    final sharpLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawLine(center, lineEnd, sharpLinePaint);

    // Draw glowing center dot
    final centerGlowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawCircle(center, 6.0, centerGlowPaint);
    
    final centerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 2.5, centerDotPaint);
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const int dashWidth = 4;
    const int dashSpace = 4;
    double distance = (p2 - p1).distance;
    if (distance == 0) return;
    double dx = (p2.dx - p1.dx) / distance;
    double dy = (p2.dy - p1.dy) / distance;
    double startX = p1.dx;
    double startY = p1.dy;

    while (distance >= 0) {
      canvas.drawLine(
        Offset(startX, startY),
        Offset(startX + dx * dashWidth, startY + dy * dashWidth),
        paint,
      );
      startX += dx * (dashWidth + dashSpace);
      startY += dy * (dashWidth + dashSpace);
      distance -= (dashWidth + dashSpace);
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class RippleAnimation extends StatefulWidget {
  final double size;
  final Color color;
  final bool isPowerSave;

  const RippleAnimation({
    super.key,
    this.size = 100.0,
    this.color = Colors.blue,
    this.isPowerSave = false,
  });

  @override
  State<RippleAnimation> createState() => _RippleAnimationState();
}

class _RippleAnimationState extends State<RippleAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (!widget.isPowerSave) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(RippleAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPowerSave != oldWidget.isPowerSave) {
      if (widget.isPowerSave) {
        _controller.stop();
      } else {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RipplePainter(
              progress: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final double progress;
  final Color color;

  _RipplePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = min(size.width / 2, size.height / 2);

    void drawRipple(double delay) {
      double currentProgress = (progress - delay) % 1.0;
      if (currentProgress < 0) currentProgress += 1.0;
      
      // Use an ease-out curve for a more natural expanding ripple
      double curvedProgress = Curves.easeOutQuart.transform(currentProgress);
      final radius = maxRadius * curvedProgress;
      final opacity = 1.0 - curvedProgress;
      
      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + (3.0 * (1.0 - curvedProgress));
        
      canvas.drawCircle(center, radius, paint);
      
      final fillPaint = Paint()
        ..color = color.withValues(alpha: opacity * 0.15)
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(center, radius, fillPaint);
    }

    drawRipple(0.0);
    drawRipple(0.33);
    drawRipple(0.66);
    
    // Center dot
    final centerDotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0);
    canvas.drawCircle(center, maxRadius * 0.1, centerDotPaint);
    
    final innerDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius * 0.04, innerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
