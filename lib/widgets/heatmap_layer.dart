import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class HeatmapLayer extends StatelessWidget {
  final List<LatLng> points;
  final double radius;

  const HeatmapLayer({
    super.key,
    required this.points,
    this.radius = 40.0,
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return CustomPaint(
      size: camera.size,
      painter: _HeatmapPainter(
        points: points,
        camera: camera,
        radius: radius,
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<LatLng> points;
  final MapCamera camera;
  final double radius;

  _HeatmapPainter({
    required this.points,
    required this.camera,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // Use a blur filter to smoothly blend the overlapping points
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: radius * 0.3, sigmaY: radius * 0.3),
    );

    // Create a single reusable shader for high performance
    final shader = ui.Gradient.radial(
      Offset.zero,
      radius,
      [
        const Color(0xFFFFFFFF).withValues(alpha: 0.8), // White hot center
        const Color(0xFFFFC107).withValues(alpha: 0.6), // Amber
        const Color(0xFFF44336).withValues(alpha: 0.4), // Red
        const Color(0xFF3F51B5).withValues(alpha: 0.2), // Indigo
        const Color(0xFF3F51B5).withValues(alpha: 0.0), // Transparent
      ],
      [0.0, 0.2, 0.5, 0.8, 1.0],
    );

    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.screen;

    final margin = radius * 2.0;

    for (final point in points) {
      final offset = camera.latLngToScreenOffset(point);

      // Cull points outside the visible area (with margin for blur bleed)
      if (offset.dx < -margin ||
          offset.dx > size.width + margin ||
          offset.dy < -margin ||
          offset.dy > size.height + margin) {
        continue;
      }

      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      canvas.drawCircle(Offset.zero, radius, paint);
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.camera != camera ||
        oldDelegate.radius != radius;
  }
}
