import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class HeatmapLayer extends StatefulWidget {
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
  State<HeatmapLayer> createState() => _HeatmapLayerState();
}

class _Cluster {
  double sumLat;
  double sumLng;
  int count;
  late LatLng center;

  _Cluster(LatLng point)
    : sumLat = point.latitude,
      sumLng = point.longitude,
      count = 1;

  void add(LatLng point) {
    sumLat += point.latitude;
    sumLng += point.longitude;
    count++;
  }

  void computeCenter() {
    center = LatLng(sumLat / count, sumLng / count);
  }
}

class _HeatmapLayerState extends State<HeatmapLayer> {
  List<_Cluster> _cachedClusters = [];
  int _cachedZoom = -1;
  List<LatLng> _cachedPoints = [];

  void _updateClusters(MapCamera camera) {
    final zoom = camera.zoom.round();
    if (_cachedZoom == zoom && identical(_cachedPoints, widget.points)) {
      return;
    }

    _cachedZoom = zoom;
    _cachedPoints = widget.points;

    final cellSize = widget.radius / 2.0;
    final Map<math.Point<int>, _Cluster> grid = {};

    for (final point in widget.points) {
      final globalPos = camera.projectAtZoom(point, zoom.toDouble());

      final gridX = (globalPos.dx / cellSize).floor();
      final gridY = (globalPos.dy / cellSize).floor();
      final gridPoint = math.Point(gridX, gridY);

      final existing = grid[gridPoint];
      if (existing != null) {
        existing.add(point);
      } else {
        grid[gridPoint] = _Cluster(point);
      }
    }

    for (final cluster in grid.values) {
      cluster.computeCenter();
    }

    _cachedClusters = grid.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    _updateClusters(camera);

    return CustomPaint(
      size: camera.size,
      painter: _HeatmapPainter(
        clusters: _cachedClusters,
        camera: camera,
        radius: widget.radius,
        blurSigma: widget.blurSigma,
        colors: widget.colors,
        stops: widget.stops,
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final List<_Cluster> clusters;
  final MapCamera camera;
  final double radius;
  final double blurSigma;
  final List<Color> colors;
  final List<double> stops;

  _HeatmapPainter({
    required this.clusters,
    required this.camera,
    required this.radius,
    required this.blurSigma,
    required this.colors,
    required this.stops,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (clusters.isEmpty) return;

    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
        ),
    );

    final shader = ui.Gradient.radial(Offset.zero, radius, colors, stops);

    final paint = Paint()
      ..shader = shader
      ..blendMode = BlendMode.screen;

    final margin = radius * 2.0;

    for (final cluster in clusters) {
      final offset = camera.latLngToScreenOffset(cluster.center);

      if (offset.dx < -margin ||
          offset.dx > size.width + margin ||
          offset.dy < -margin ||
          offset.dy > size.height + margin) {
        continue;
      }

      final weight = cluster.count;
      final drawCount = math.min(weight, 5);

      canvas.save();
      canvas.translate(offset.dx, offset.dy);

      for (int i = 0; i < drawCount; i++) {
        canvas.drawCircle(Offset.zero, radius, paint);
      }

      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) {
    return oldDelegate.clusters != clusters ||
        oldDelegate.camera != camera ||
        oldDelegate.radius != radius ||
        oldDelegate.blurSigma != blurSigma ||
        oldDelegate.colors != colors ||
        oldDelegate.stops != stops;
  }
}
