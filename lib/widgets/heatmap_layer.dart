import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class HeatmapLayer extends StatelessWidget {
  final List<LatLng> points;
  final double radius;
  final double blurSigma;
  final List<Color> colors;
  final List<double> stops;

  const HeatmapLayer({
    super.key,
    required this.points,
    this.radius = 40.0,
    this.blurSigma = 15.0,
    this.colors = const [
      Color(0xFFFFFFFF), // White hot center
      Color(0xE6FFF176), // Yellow
      Color(0xCCFF9800), // Orange
      Color(0x99F44336), // Red
      Color(0x663F51B5), // Indigo
      Color(0x003F51B5), // Transparent Indigo
    ],
    this.stops = const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
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
        blurSigma: blurSigma,
        colors: colors,
        stops: stops,
      ),
    );
  }
}

class _Cluster {
  double sumX;
  double sumY;
  int count;

  _Cluster(Offset offset)
      : sumX = offset.dx,
        sumY = offset.dy,
        count = 1;

  void add(Offset offset) {
    sumX += offset.dx;
    sumY += offset.dy;
    count++;
  }

  Offset get center => Offset(sumX / count, sumY / count);
}

class _HeatmapPainter extends CustomPainter {
  final List<LatLng> points;
  final MapCamera camera;
  final double radius;
  final double blurSigma;
  final List<Color> colors;
  final List<double> stops;

  _HeatmapPainter({
    required this.points,
    required this.camera,
    required this.radius,
    required this.blurSigma,
    required this.colors,
    required this.stops,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    // 1. Save layer with blur to blend the points smoothly
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
    );

    // 2. Create the radial gradient shader
    final shader = ui.Gradient.radial(
      Offset.zero,
      radius,
      colors,
      stops,
    );

    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.screen;

    final margin = radius * 2.0;

    // 3. Cluster points to improve performance and visual density
    final cellSize = radius / 2.0;
    final Map<math.Point<int>, _Cluster> grid = {};

    for (final point in points) {
      final offset = camera.latLngToScreenOffset(point);

      // Cull points outside the visible area
      if (offset.dx < -margin ||
          offset.dx > size.width + margin ||
          offset.dy < -margin ||
          offset.dy > size.height + margin) {
        continue;
      }

      final gridX = (offset.dx / cellSize).floor();
      final gridY = (offset.dy / cellSize).floor();
      final gridPoint = math.Point(gridX, gridY);

      if (grid.containsKey(gridPoint)) {
        grid[gridPoint]!.add(offset);
      } else {
        grid[gridPoint] = _Cluster(offset);
      }
    }

    // 4. Draw the clustered points
    for (final cluster in grid.values) {
      final offset = cluster.center;
      final weight = cluster.count;

      canvas.save();
      canvas.translate(offset.dx, offset.dy);

      // Draw multiple times based on weight to increase intensity
      // Cap the weight to prevent excessive overdraw and pure white blowouts
      final drawCount = math.min(weight, 5);
      for (int i = 0; i < drawCount; i++) {
        canvas.drawCircle(Offset.zero, radius, paint);
      }

      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.camera != camera ||
        oldDelegate.radius != radius ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.colors != colors ||
        oldDelegate.stops != stops;
  }
}
