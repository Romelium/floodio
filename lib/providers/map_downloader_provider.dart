import 'dart:math';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

part 'map_downloader_provider.g.dart';

class DownloadProgress {
  final int total;
  final int downloaded;
  final bool isDownloading;

  DownloadProgress({
    this.total = 0,
    this.downloaded = 0,
    this.isDownloading = false,
  });

  double get percentage => total == 0 ? 0 : downloaded / total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadProgress &&
          runtimeType == other.runtimeType &&
          total == other.total &&
          downloaded == other.downloaded &&
          isDownloading == other.isDownloading;

  @override
  int get hashCode => Object.hash(total, downloaded, isDownloading);
}

class MapTile {
  final int x;
  final int y;
  final int z;
  MapTile(this.x, this.y, this.z);
}

int lon2tilex(double lon, int z) {
  return ((lon + 180.0) / 360.0 * pow(2.0, z)).floor();
}

int lat2tiley(double lat, int z) {
  return ((1.0 -
              log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) /
          2.0 *
          pow(2.0, z))
      .floor();
}

@riverpod
class MapDownloader extends _$MapDownloader {
  @override
  DownloadProgress build() {
    final service = FlutterBackgroundService();

    final sub = service.on('mapDownloadProgress').listen((event) {
      if (event != null) {
        state = DownloadProgress(
          total: event['total'] as int,
          downloaded: event['downloaded'] as int,
          isDownloading: event['isDownloading'] as bool,
        );
      }
    });

    ref.onDispose(() {
      sub.cancel();
    });

    service.invoke('requestMapDownloadState');

    return DownloadProgress();
  }

  int estimateTileCount(LatLngBounds bounds, int minZoom, int maxZoom) {
    int count = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      final minX = lon2tilex(bounds.west, z);
      final maxX = lon2tilex(bounds.east, z);
      final minY = lat2tiley(bounds.north, z);
      final maxY = lat2tiley(bounds.south, z);

      count +=
          ((max(minX, maxX) - min(minX, maxX) + 1) *
                  (max(minY, maxY) - min(minY, maxY) + 1))
              .toInt();
    }
    return count;
  }

  void downloadRegion(
    LatLngBounds bounds,
    int minZoom,
    int maxZoom,
    String urlTemplate,
  ) {
    FlutterBackgroundService().invoke('startMapDownload', {
      'north': bounds.north,
      'south': bounds.south,
      'east': bounds.east,
      'west': bounds.west,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'urlTemplate': urlTemplate,
    });
  }

  void cancelDownload() {
    FlutterBackgroundService().invoke('cancelMapDownload');
  }
}
