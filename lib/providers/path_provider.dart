import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'path_provider.g.dart';

@Riverpod(dependencies: [database])
class PathsController extends _$PathsController {
  @override
  Stream<List<PathEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.paths).watch();
  }

  Future<void> addPath(PathEntity path) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.into(db.paths).insert(
        PathsCompanion.insert(
          id: path.id,
          coordinates: path.coordinates,
          type: path.type,
          description: path.description,
          timestamp: path.timestamp,
          senderId: path.senderId,
          signature: Value(path.signature),
          trustTier: path.trustTier,
          expiresAt: Value(path.expiresAt),
          isCritical: Value(path.isCritical),
        ),
        mode: InsertMode.insertOrReplace,
      );
      await db.into(db.seenMessageIds).insert(
        SeenMessageIdsCompanion.insert(
          messageId: path.id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> deletePath(String id) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await (db.delete(db.paths)..where((t) => t.id.equals(id))).go();
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
