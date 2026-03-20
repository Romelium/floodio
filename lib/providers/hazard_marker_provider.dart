import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'hazard_marker_provider.g.dart';

@riverpod
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
        ),
        mode: InsertMode.insertOrReplace,
      );
      await db.into(db.seenMessageIds).insert(
        SeenMessageIdsCompanion.insert(
          messageId: marker.id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }
}
