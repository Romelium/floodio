import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'map_cache_service.g.dart';

class MapPackData {
  final String dirPath;
  MapPackData(this.dirPath);
}

Future<String> _isolatePackMap(MapPackData data) async {
  final mapDir = Directory('${data.dirPath}/map_tiles');
  final packFile = File('${data.dirPath}/offline_map.fmap');
  
  if (!await mapDir.exists()) {
    throw Exception('No offline map data found.');
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
      final yStr = parts.last.replaceAll('.png', '');
      final xStr = parts[parts.length - 2];
      final zStr = parts[parts.length - 3];
      
      final z = int.tryParse(zStr);
      final x = int.tryParse(xStr);
      final y = int.tryParse(yStr);
      
      if (z != null && x != null && y != null) {
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
      await tileFile.parent.create(recursive: true);
      await tileFile.writeAsBytes(fileData);
    }
    return timestamp;
  } finally {
    await raf.close();
  }
}

@Riverpod(keepAlive: true)
MapCacheService mapCacheService(Ref ref) {
  return MapCacheService();
}

class MapCacheService {
  Future<File> getTileFile(int z, int x, int y) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/map_tiles/$z/$x/$y.png';
    return File(path);
  }

  Future<Uint8List?> getTile(int z, int x, int y, String urlTemplate) async {
    final file = await getTileFile(z, x, y);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    
    final url = urlTemplate
        .replaceAll('{z}', z.toString())
        .replaceAll('{x}', x.toString())
        .replaceAll('{y}', y.toString());
        
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('User-Agent', 'com.example.floodio');
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
        return bytes;
      }
    } catch (e) {
      debugPrint('Error downloading tile: $e');
    }
    return null;
  }

  Future<File> packMap() async {
    final dir = await getApplicationDocumentsDirectory();
    final result = await Isolate.run(() => _isolatePackMap(MapPackData(dir.path)));
    final parts = result.split('_');
    final timestamp = int.parse(parts[0]);
    final path = result.substring(parts[0].length + 1);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_map_version', timestamp);
    
    return File(path);
  }

  Future<void> unpackMap(File packFile) async {
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = await Isolate.run(() => _isolateUnpackMap(MapUnpackData(dir.path, packFile.path)));
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('local_map_version', timestamp);
  }
  
  Future<int> getLocalMapVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('local_map_version') ?? 0;
  }
}
