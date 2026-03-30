import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'trusted_sender_provider.g.dart';

@Riverpod(keepAlive: true)
class TrustedSendersController extends _$TrustedSendersController {
  @override
  Stream<List<TrustedSenderEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.trustedSenders).watch();
  }

  Future<void> addTrustedSender(String publicKey, String name) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.into(db.trustedSenders).insert(
        TrustedSendersCompanion.insert(
          publicKey: publicKey,
          name: name,
        ),
        mode: InsertMode.insertOrReplace,
      );

      // Update existing hazard markers
      await (db.update(db.hazardMarkers)..where((t) => t.senderId.equals(publicKey)))
          .write(const HazardMarkersCompanion(trustTier: Value(3)));

      // Update existing news items
      await (db.update(db.newsItems)..where((t) => t.senderId.equals(publicKey)))
          .write(const NewsItemsCompanion(trustTier: Value(3)));

      // Update existing areas
      await (db.update(db.areas)..where((t) => t.senderId.equals(publicKey)))
          .write(const AreasCompanion(trustTier: Value(3)));
    });
  }

  Future<void> removeTrustedSender(String publicKey) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await (db.delete(db.trustedSenders)..where((t) => t.publicKey.equals(publicKey))).go();

      // Downgrade existing hazard markers
      await (db.update(db.hazardMarkers)..where((t) => t.senderId.equals(publicKey)))
          .write(const HazardMarkersCompanion(trustTier: Value(4)));

      // Downgrade existing news items
      await (db.update(db.newsItems)..where((t) => t.senderId.equals(publicKey)))
          .write(const NewsItemsCompanion(trustTier: Value(4)));

      // Downgrade existing areas
      await (db.update(db.areas)..where((t) => t.senderId.equals(publicKey)))
          .write(const AreasCompanion(trustTier: Value(4)));
    });
  }
}

