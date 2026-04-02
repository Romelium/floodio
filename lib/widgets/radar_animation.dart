import 'dart:math';
import 'package:flutter/material.dart';

class RadarAnimation extends StatefulWidget {
  final double size;
  final Color color;

  const RadarAnimation({
    super.key,
    this.size = 100.0,
    this.color = Colors.blue,
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
    )..repeat();
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

    // Draw concentric circles
    final circlePaint = Paint()
      ..color = color.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, radius * 0.33, circlePaint);
    canvas.drawCircle(center, radius * 0.66, circlePaint);
    canvas.drawCircle(center, radius, circlePaint);

    // Draw sweeping gradient
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.5),
          color.withValues(alpha: 0.8),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.85, 0.95, 1.0],
        transform: GradientRotation(progress * 2 * pi),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      progress * 2 * pi, // Start angle
      pi / 2, // Sweep angle (90 degrees)
      true,
      sweepPaint,
    );
    
    // Draw scanner line
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
      
    final lineAngle = progress * 2 * pi + pi / 2;
    canvas.drawLine(
      center,
      center + Offset(cos(lineAngle) * radius, sin(lineAngle) * radius),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class RippleAnimation extends StatefulWidget {
  final double size;
  final Color color;

  const RippleAnimation({
    super.key,
    this.size = 100.0,
    this.color = Colors.blue,
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
    )..repeat();
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
      
      final radius = maxRadius * currentProgress;
      final opacity = 1.0 - currentProgress;
      
      final paint = Paint()
        ..color = color.withValues(alpha: opacity * 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 + (2.0 * (1.0 - currentProgress));
        
      canvas.drawCircle(center, radius, paint);
      
      final fillPaint = Paint()
        ..color = color.withValues(alpha: opacity * 0.2)
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(center, radius, fillPaint);
    }

    drawRipple(0.0);
    drawRipple(0.33);
    drawRipple(0.66);
    
    // Center dot
    canvas.drawCircle(
      center, 
      maxRadius * 0.1, 
      Paint()..color = color
    );
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
