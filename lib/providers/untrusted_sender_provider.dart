import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'untrusted_sender_provider.g.dart';

@Riverpod(keepAlive: true)
class UntrustedSendersController extends _$UntrustedSendersController {
  @override
  Stream<List<UntrustedSenderEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.untrustedSenders).watch();
  }

  Future<void> addUntrustedSender(String publicKey) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.into(db.untrustedSenders).insert(
        UntrustedSendersCompanion.insert(
          publicKey: publicKey,
        ),
        mode: InsertMode.insertOrReplace,
      );

      await (db.delete(db.hazardMarkers)..where((t) => t.senderId.equals(publicKey))).go();
      await (db.delete(db.newsItems)..where((t) => t.senderId.equals(publicKey))).go();
      await (db.delete(db.areas)..where((t) => t.senderId.equals(publicKey))).go();
    });
  }

  Future<void> removeUntrustedSender(String publicKey) async {
    final db = ref.read(databaseProvider);
    await (db.delete(db.untrustedSenders)..where((t) => t.publicKey.equals(publicKey))).go();
  }
}
