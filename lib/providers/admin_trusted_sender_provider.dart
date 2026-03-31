import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'admin_trusted_sender_provider.g.dart';

@Riverpod(keepAlive: true)
class AdminTrustedSendersController extends _$AdminTrustedSendersController {
  @override
  Stream<List<AdminTrustedSenderEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.adminTrustedSenders).watch();
  }

  Future<void> addAdminTrustedSender(AdminTrustedSenderEntity entity) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.into(db.adminTrustedSenders).insert(
        AdminTrustedSendersCompanion.insert(
          publicKey: entity.publicKey,
          delegatorPublicKey: entity.delegatorPublicKey,
          timestamp: entity.timestamp,
          signature: entity.signature,
        ),
        mode: InsertMode.insertOrReplace,
      );

      await (db.update(db.hazardMarkers)..where((t) => t.senderId.equals(entity.publicKey) & t.trustTier.isBiggerThanValue(2)))
          .write(const HazardMarkersCompanion(trustTier: Value(2)));

      await (db.update(db.newsItems)..where((t) => t.senderId.equals(entity.publicKey) & t.trustTier.isBiggerThanValue(2)))
          .write(const NewsItemsCompanion(trustTier: Value(2)));

      await (db.update(db.areas)..where((t) => t.senderId.equals(entity.publicKey) & t.trustTier.isBiggerThanValue(2)))
          .write(const AreasCompanion(trustTier: Value(2)));
    });
  }
}
