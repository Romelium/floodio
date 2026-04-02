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

    canvas.saveLayer(Offset.zero & size, Paint());

    final paint = Paint()..blendMode = BlendMode.screen;

    for (final point in points) {
      final offset = camera.latLngToScreenOffset(point);

      if (offset.dx < -radius ||
          offset.dx > size.width + radius ||
          offset.dy < -radius ||
          offset.dy > size.height + radius) {
        continue;
      }

      paint.shader = ui.Gradient.radial(
        offset,
        radius,
        [
          Colors.red.withValues(alpha: 0.6),
          Colors.orange.withValues(alpha: 0.3),
          Colors.yellow.withValues(alpha: 0.1),
          Colors.transparent,
        ],
        [0.0, 0.4, 0.7, 1.0],
      );

      canvas.drawCircle(offset, radius, paint);
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
