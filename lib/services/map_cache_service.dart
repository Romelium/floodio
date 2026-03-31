import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/offline_regions_provider.dart';

part 'map_cache_service.g.dart';

class MapPackData {
  final String dirPath;
  final Map<String, dynamic>? regionJson;
  MapPackData(this.dirPath, this.regionJson);
}

int _lon2tilex(double lon, int z) {
  return ((lon + 180.0) / 360.0 * pow(2.0, z)).floor();
}

int _lat2tiley(double lat, int z) {
  return ((1.0 - log(tan(lat * pi / 180.0) + 1.0 / cos(lat * pi / 180.0)) / pi) / 2.0 * pow(2.0, z)).floor();
}

Future<String> _isolatePackMap(MapPackData data) async {
  final mapDir = Directory('${data.dirPath}/map_tiles');
  
  String fileName = 'offline_map.fmap';
  if (data.regionJson != null) {
    fileName = 'map_${data.regionJson!['n']}_${data.regionJson!['s']}_${data.regionJson!['e']}_${data.regionJson!['w']}_${data.regionJson!['minZ']}_${data.regionJson!['maxZ']}.fmap';
  }
  final packFile = File('${data.dirPath}/$fileName');
  
  if (!await mapDir.exists()) {
    await mapDir.create(recursive: true);
  }

  final sink = packFile.openWrite();
  
  // Header: FLDMAP (6 bytes)
  sink.add(const [70, 76, 68, 77, 65, 80]);
  // Version: 1 (1 byte)
  sink.add([1]);
  // Timestamp: 8 bytes
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tsData = ByteData(8);
  tsData.setInt64(0, timestamp, Endian.big);
  sink.add(tsData.buffer.asUint8List());

  await for (final entity in mapDir.list(recursive: true)) {
    if (entity is File && entity.path.endsWith('.png')) {
      final parts = entity.path.split(RegExp(r'[/\\]'));
        if (parts.length >= 3) {
          final yStr = parts.last.replaceAll('.png', '');
          final xStr = parts[parts.length - 2];
          final zStr = parts[parts.length - 3];
  
          final z = int.tryParse(zStr);
          final x = int.tryParse(xStr);
          final y = int.tryParse(yStr);
  
          if (z != null && x != null && y != null) {
            if (data.regionJson != null) {
              final n = data.regionJson!['n'] as double;
              final s = data.regionJson!['s'] as double;
              final e = data.regionJson!['e'] as double;
              final w = data.regionJson!['w'] as double;
              final minZ = data.regionJson!['minZ'] as int;
              final maxZ = data.regionJson!['maxZ'] as int;
  
              if (z < minZ || z > maxZ) continue;
              final minX = _lon2tilex(w, z);
              final maxX = _lon2tilex(e, z);
              final minY = _lat2tiley(n, z);
              final maxY = _lat2tiley(s, z);
              if (x < min(minX, maxX) || x > max(minX, maxX) || y < min(minY, maxY) || y > max(minY, maxY)) {
                continue;
              }
          }

          final fileData = await entity.readAsBytes();
        
          final header = ByteData(13);
          header.setUint8(0, z);
          header.setUint32(1, x, Endian.big);
          header.setUint32(5, y, Endian.big);
          header.setUint32(9, fileData.length, Endian.big);
        
          sink.add(header.buffer.asUint8List());
          sink.add(fileData);
        }
      }
    }
  }
  
  await sink.close();
  return '${timestamp}_${packFile.path}';
}

class MapUnpackData {
  final String dirPath;
  final String packFilePath;
  MapUnpackData(this.dirPath, this.packFilePath);
}

Future<int> _isolateUnpackMap(MapUnpackData data) async {
  final mapDir = Directory('${data.dirPath}/map_tiles');
  final packFile = File(data.packFilePath);
  
  final raf = await packFile.open(mode: FileMode.read);
  try {
    final header = await raf.read(7);
    if (header.length < 7 || String.fromCharCodes(header.sublist(0, 6)) != 'FLDMAP') {
      throw Exception('Invalid map pack file');
    }
    // read timestamp
    final tsBytes = await raf.read(8);
    final tsData = ByteData.sublistView(tsBytes);
    final timestamp = tsData.getInt64(0, Endian.big);
    
    while (true) {
      final tileHeader = await raf.read(13);
      if (tileHeader.length < 13) break; // EOF
      
      final headerData = ByteData.sublistView(tileHeader);
      final z = headerData.getUint8(0);
      final x = headerData.getUint32(1, Endian.big);
      final y = headerData.getUint32(5, Endian.big);
      final length = headerData.getUint32(9, Endian.big);
      
      final fileData = await raf.read(length);
      if (fileData.length < length) break; // Unexpected EOF
      
      final tileFile = File('${mapDir.path}/$z/$x/$y.png');
      try {
        await tileFile.parent.create(recursive: true);
        await tileFile.writeAsBytes(fileData);
      } catch (e) {
        debugPrint('Failed to write unpacked tile: $e');
      }
    }
    return timestamp; // Kept for backwards compatibility with older file headers
  } finally {
    await raf.close();
  }
}

@Riverpod(keepAlive: true)
MapCacheService mapCacheService(Ref ref) {
  return MapCacheService();
}

class MapCacheService {
  final _memoryCache = <String, Uint8List>{};
  final int _maxMemoryCacheSize = 200; // Cache up to 200 tiles in memory

  Future<File> getTileFile(int z, int x, int y) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/map_tiles/$z/$x/$y.png';
    return File(path);
  }

  Future<Uint8List?> getTile(int z, int x, int y, String urlTemplate) async {
    final key = '$z/$x/$y';
    if (_memoryCache.containsKey(key)) {
      final bytes = _memoryCache.remove(key)!;
      _memoryCache[key] = bytes; // Move to end (most recently used)
      return bytes;
    }

    final file = await getTileFile(z, x, y);
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      _addToMemoryCache(key, bytes);
      return bytes;
    }
    
    final url = urlTemplate
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
        
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'FloodioApp/0.1.0');
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        await file.parent.create(recursive: true);
        try {
          await file.writeAsBytes(bytes);
        } catch (_) {} // Ignore concurrent write collisions
        _addToMemoryCache(key, bytes);
        return bytes;
      }
    } catch (e) {
      debugPrint('Error downloading tile: $e');
    }
    return null;
  }

  void _addToMemoryCache(String key, Uint8List bytes) {
    _memoryCache[key] = bytes;
    if (_memoryCache.length > _maxMemoryCacheSize) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
  }

  Future<File> packMap({OfflineRegion? region}) async {
    final dir = await getApplicationDocumentsDirectory();
    
    // Clean up old pack files
    final dirList = dir.listSync();
    for (var entity in dirList) {
      if (entity is File && entity.path.endsWith('.fmap')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }

    final result = await Isolate.run(() => _isolatePackMap(MapPackData(dir.path, region?.toJson())));
    final parts = result.split('_');
    final path = result.substring(parts[0].length + 1);
    
    return File(path);
  }

  Future<void> unpackMap(File packFile) async {
    final dir = await getApplicationDocumentsDirectory();
    await Isolate.run(() => _isolateUnpackMap(MapUnpackData(dir.path, packFile.path)));
  }
  
  Future<int> getCacheSize() async {
    final dir = await getApplicationDocumentsDirectory();
    final mapDir = Directory('${dir.path}/map_tiles');
    if (!await mapDir.exists()) return 0;

    int size = 0;
    await for (final entity in mapDir.list(recursive: true)) {
      if (entity is File) {
        size += await entity.length();
      }
    }
    return size;
  }

  Future<void> clearCache() async {
    final dir = await getApplicationDocumentsDirectory();
    final mapDir = Directory('${dir.path}/map_tiles');
    if (await mapDir.exists()) {
      await mapDir.delete(recursive: true);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_regions');
  }

  Future<void> deleteRegionTiles(OfflineRegion region) async {
    final dir = await getApplicationDocumentsDirectory();
    for (int z = region.minZoom; z <= region.maxZoom; z++) {
      final minX = _lon2tilex(region.bounds.west, z);
      final maxX = _lon2tilex(region.bounds.east, z);
      final minY = _lat2tiley(region.bounds.north, z);
      final maxY = _lat2tiley(region.bounds.south, z);

      for (int x = min(minX, maxX); x <= max(minX, maxX); x++) {
        for (int y = min(minY, maxY); y <= max(minY, maxY); y++) {
          final file = File('${dir.path}/map_tiles/$z/$x/$y.png');
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {}
          }
        }
      }
    }
  }
}
