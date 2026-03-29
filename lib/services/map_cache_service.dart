import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'map_cache_service.g.dart';

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
}
