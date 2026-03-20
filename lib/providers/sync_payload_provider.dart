import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'sync_payload_provider.g.dart';

@riverpod
class SyncPayloadsController extends _$SyncPayloadsController {
  @override
  Stream<List<SyncPayloadEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.syncPayloads).watch();
  }

  Future<void> addPayload(SyncPayloadEntity payload) async {
    final db = ref.read(databaseProvider);
    await db.into(db.syncPayloads).insert(
      SyncPayloadsCompanion.insert(
        id: payload.id,
        payload: payload.payload,
        timestamp: payload.timestamp,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }
}
