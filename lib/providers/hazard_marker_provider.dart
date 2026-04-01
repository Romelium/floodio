import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'hazard_marker_provider.g.dart';

@Riverpod(dependencies: [database])
class HazardMarkersController extends _$HazardMarkersController {
  @override
  Stream<List<HazardMarkerEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.hazardMarkers).watch();
  }

  Future<void> addMarker(HazardMarkerEntity marker) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.into(db.hazardMarkers).insert(
        HazardMarkersCompanion.insert(
          id: marker.id,
          latitude: marker.latitude,
          longitude: marker.longitude,
          type: marker.type,
          description: marker.description,
          timestamp: marker.timestamp,
          senderId: marker.senderId,
          signature: Value(marker.signature),
          trustTier: marker.trustTier,
          imageId: Value(marker.imageId),
          expiresAt: Value(marker.expiresAt),
          isCritical: Value(marker.isCritical),
        ),
        mode: InsertMode.insertOrReplace,
      );
      await db.into(db.seenMessageIds).insert(
        SeenMessageIdsCompanion.insert(
          messageId: '${marker.id}_${marker.timestamp}',
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> deleteMarker(String id) async {
    final db = ref.read(databaseProvider);
    
    final marker = await (db.select(db.hazardMarkers)..where((t) => t.id.equals(id))).getSingleOrNull();
    
    await db.transaction(() async {
      await (db.delete(db.hazardMarkers)..where((t) => t.id.equals(id))).go();
      await db.into(db.deletedItems).insert(
        DeletedItemsCompanion.insert(
          id: id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });

    if (marker?.imageId != null && marker!.imageId!.isNotEmpty) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/${marker.imageId}');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}

