import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'area_provider.g.dart';

@riverpod
class AreasController extends _$AreasController {
  @override
  Stream<List<AreaEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.areas).watch();
  }

  Future<void> addArea(AreaEntity area) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.into(db.areas).insert(
        AreasCompanion.insert(
          id: area.id,
          coordinates: area.coordinates,
          type: area.type,
          description: area.description,
          timestamp: area.timestamp,
          senderId: area.senderId,
          signature: Value(area.signature),
          trustTier: area.trustTier,
        ),
        mode: InsertMode.insertOrReplace,
      );
      await db.into(db.seenMessageIds).insert(
        SeenMessageIdsCompanion.insert(
          messageId: area.id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> deleteArea(String id) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await (db.delete(db.areas)..where((t) => t.id.equals(id))).go();
      await db.into(db.deletedItems).insert(
        DeletedItemsCompanion.insert(
          id: id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }
}
