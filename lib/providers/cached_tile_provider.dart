import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../services/map_cache_service.dart';

class CachedTileProvider extends TileProvider {
  final MapCacheService cacheService;

  CachedTileProvider(this.cacheService);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return CachedTileImageProvider(
      coordinates: coordinates,
      urlTemplate: options.urlTemplate!,
      cacheService: cacheService,
    );
  }
}

class CachedTileImageProvider extends ImageProvider<CachedTileImageProvider> {
  final TileCoordinates coordinates;
  final String urlTemplate;
  final MapCacheService cacheService;

  CachedTileImageProvider({
    required this.coordinates,
    required this.urlTemplate,
    required this.cacheService,
  });

  @override
  Future<CachedTileImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<CachedTileImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(CachedTileImageProvider key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
    );
  }

  Future<ui.Codec> _loadAsync(CachedTileImageProvider key, ImageDecoderCallback decode) async {
    final bytes = await cacheService.getTile(
      key.coordinates.z,
      key.coordinates.x,
      key.coordinates.y,
      key.urlTemplate,
    );
    
    if (bytes == null || bytes.isEmpty) {
      final empty = Uint8List.fromList([
        137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 11, 73, 68, 65, 84, 8, 215, 99, 96, 0, 2, 0, 0, 5, 0, 1, 226, 38, 5, 155, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130
      ]);
      final buffer = await ui.ImmutableBuffer.fromUint8List(empty);
      return decode(buffer);
    }
    
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }
}
