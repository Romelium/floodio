import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/background_service.dart';

part 'offline_regions_provider.g.dart';

class OfflineRegion {
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;

  OfflineRegion({
    required this.bounds,
    required this.minZoom,
    required this.maxZoom,
  });

  Map<String, dynamic> toJson() => {
    'n': bounds.north,
    's': bounds.south,
    'e': bounds.east,
    'w': bounds.west,
    'minZ': minZoom,
    'maxZ': maxZoom,
  };

  factory OfflineRegion.fromJson(Map<String, dynamic> json) => OfflineRegion(
    bounds: LatLngBounds(
      LatLng((json['s'] as num).toDouble(), (json['w'] as num).toDouble()),
      LatLng((json['n'] as num).toDouble(), (json['e'] as num).toDouble()),
    ),
    minZoom: (json['minZ'] as num).toInt(),
    maxZoom: (json['maxZ'] as num).toInt(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OfflineRegion &&
          runtimeType == other.runtimeType &&
          bounds.north == other.bounds.north &&
          bounds.south == other.bounds.south &&
          bounds.east == other.bounds.east &&
          bounds.west == other.bounds.west &&
          minZoom == other.minZoom &&
          maxZoom == other.maxZoom;

  @override
  int get hashCode => Object.hash(
    bounds.north,
    bounds.south,
    bounds.east,
    bounds.west,
    minZoom,
    maxZoom,
  );
}

@riverpod
class OfflineRegions extends _$OfflineRegions {
  @override
  Future<List<OfflineRegion>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('offline_regions');
    if (data == null) return [];
    try {
      final List<dynamic> decoded = jsonDecode(data);
      return decoded.map((e) => OfflineRegion.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> addRegion(OfflineRegion region) async {
    final current = state.value ?? [];

    final isDuplicate = current.any(
      (r) =>
          (r.bounds.north - region.bounds.north).abs() < 0.0001 &&
          (r.bounds.south - region.bounds.south).abs() < 0.0001 &&
          (r.bounds.east - region.bounds.east).abs() < 0.0001 &&
          (r.bounds.west - region.bounds.west).abs() < 0.0001 &&
          r.minZoom == region.minZoom &&
          r.maxZoom == region.maxZoom,
    );

    if (isDuplicate) return;

    final updated = [...current, region];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'offline_regions',
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    state = AsyncData(updated);
    if (isBackgroundIsolate) {
      bgServiceInstance?.invoke('reloadOfflineRegions');
    } else {
      try {
        FlutterBackgroundService().invoke('reloadOfflineRegions');
      } catch (e) {
        print("[OfflineRegions] Error invoking background service: $e");
      }
    }
  }

  Future<void> clearRegions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_regions');
    state = const AsyncData([]);
    if (isBackgroundIsolate) {
      bgServiceInstance?.invoke('reloadOfflineRegions');
    } else {
      try {
        FlutterBackgroundService().invoke('reloadOfflineRegions');
      } catch (e) {
        print("[OfflineRegions] Error invoking background service: $e");
      }
    }
  }

  Future<void> removeRegion(OfflineRegion region) async {
    final current = state.value ?? [];
    final updated = current
        .where(
          (r) =>
              (r.bounds.north - region.bounds.north).abs() > 0.0001 ||
              (r.bounds.south - region.bounds.south).abs() > 0.0001 ||
              (r.bounds.east - region.bounds.east).abs() > 0.0001 ||
              (r.bounds.west - region.bounds.west).abs() > 0.0001 ||
              r.minZoom != region.minZoom ||
              r.maxZoom != region.maxZoom,
        )
        .toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'offline_regions',
      jsonEncode(updated.map((e) => e.toJson()).toList()),
    );
    state = AsyncData(updated);
    if (isBackgroundIsolate) {
      bgServiceInstance?.invoke('reloadOfflineRegions');
    } else {
      try {
        FlutterBackgroundService().invoke('reloadOfflineRegions');
      } catch (e) {
        print("[OfflineRegions] Error invoking background service: $e");
      }
    }
  }
}
