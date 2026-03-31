import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/map_cache_service.dart';
import 'offline_regions_provider.dart';

part 'map_downloader_provider.g.dart';

class DownloadProgress {
  final int total;
  final int downloaded;
  final bool isDownloading;

  DownloadProgress({this.total = 0, this.downloaded = 0, this.isDownloading = false});
  
  double get percentage => total == 0 ? 0 : downloaded / total;
}

class MapTile {
  final int x;
  final int y;
  final int z;
  MapTile(this.x, this.y, this.z);
}

@riverpod
class MapDownloader extends _$MapDownloader {
  bool _isCancelled = false;

  @override
  DownloadProgress build() {
    return DownloadProgress();
  }

  int _lon2tilex(double lon, int z) {
    return ((lon + 180.0) / 360.0 * pow(2.0, z)).floor();
  }

  int _lat2tiley(double lat, int z) {
    return ((1.0 - log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * pow(2.0, z)).floor();
  }

  int estimateTileCount(LatLngBounds bounds, int minZoom, int maxZoom) {
    int count = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final minX = _lon2tilex(bounds.west, z);
      final maxX = _lon2tilex(bounds.east, z);
      final minY = _lat2tiley(bounds.north, z);
      final maxY = _lat2tiley(bounds.south, z);

      count += ((max(minX, maxX) - min(minX, maxX) + 1) * (max(minY, maxY) - min(minY, maxY) + 1)).toInt();
    }
    return count;
  }

  Future<void> downloadRegion(LatLngBounds bounds, int minZoom, int maxZoom, String urlTemplate) async {
    if (state.isDownloading) return;
    _isCancelled = false;
    
    final cacheService = ref.read(mapCacheServiceProvider);
    
    List<MapTile> tilesToDownload = [];
    
    for (int z = minZoom; z <= maxZoom; z++) {
      final minX = _lon2tilex(bounds.west, z);
      final maxX = _lon2tilex(bounds.east, z);
      final minY = _lat2tiley(bounds.north, z);
      final maxY = _lat2tiley(bounds.south, z);
      
      for (int x = min(minX, maxX); x <= max(minX, maxX); x++) {
        for (int y = min(minY, maxY); y <= max(minY, maxY); y++) {
          tilesToDownload.add(MapTile(x, y, z));
        }
      }
    }
    
    state = DownloadProgress(total: tilesToDownload.length, downloaded: 0, isDownloading: true);
    
    int downloaded = 0;
    const batchSize = 5;
    for (int i = 0; i < tilesToDownload.length; i += batchSize) {
      if (_isCancelled) break;
      
      final batch = tilesToDownload.skip(i).take(batchSize);
      await Future.wait(batch.map((tile) => cacheService.getTile(tile.z, tile.x, tile.y, urlTemplate)));
      
      downloaded += batch.length;
      state = DownloadProgress(total: tilesToDownload.length, downloaded: downloaded, isDownloading: true);
    }

    if (!_isCancelled) {
      ref.read(offlineRegionsProvider.notifier).addRegion(
        OfflineRegion(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom),
      );
    }
    
    state = DownloadProgress(total: tilesToDownload.length, downloaded: downloaded, isDownloading: false);
  }
  
  void cancelDownload() {
    _isCancelled = true;
    state = DownloadProgress(total: state.total, downloaded: state.downloaded, isDownloading: false);
  }
}
