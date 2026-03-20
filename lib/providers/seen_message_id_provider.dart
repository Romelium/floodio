import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'seen_message_id_provider.g.dart';

@riverpod
class SeenMessageIdsController extends _$SeenMessageIdsController {
  @override
  Stream<List<SeenMessageIdEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.seenMessageIds).watch();
  }

  Future<void> addSeenMessageId(SeenMessageIdEntity seenMessageId) async {
    final db = ref.read(databaseProvider);
    await db.into(db.seenMessageIds).insert(
      SeenMessageIdsCompanion.insert(
        messageId: seenMessageId.messageId,
        timestamp: seenMessageId.timestamp,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }
}
