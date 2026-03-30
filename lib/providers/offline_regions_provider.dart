import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'offline_regions_provider.g.dart';

class OfflineRegion {
  final LatLngBounds bounds;
  final int minZoom;
  final int maxZoom;

  OfflineRegion({required this.bounds, required this.minZoom, required this.maxZoom});

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
          LatLng(json['s'], json['w']),
          LatLng(json['n'], json['e']),
        ),
        minZoom: json['minZ'],
        maxZoom: json['maxZ'],
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
    final updated = [...current, region];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_regions', jsonEncode(updated.map((e) => e.toJson()).toList()));
    state = AsyncData(updated);
  }

  Future<void> clearRegions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_regions');
    state = const AsyncData([]);
  }
}
