import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'revoked_delegation_provider.g.dart';

@Riverpod(keepAlive: true)
class RevokedDelegationsController extends _$RevokedDelegationsController {
  @override
  Stream<List<RevokedDelegationEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.revokedDelegations).watch();
  }

  Future<void> addRevokedDelegation(RevokedDelegationEntity entity) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.into(db.revokedDelegations).insert(
        RevokedDelegationsCompanion.insert(
          delegateePublicKey: entity.delegateePublicKey,
          delegatorPublicKey: entity.delegatorPublicKey,
          timestamp: entity.timestamp,
          signature: entity.signature,
        ),
        mode: InsertMode.insertOrReplace,
      );

      await (db.update(db.hazardMarkers)..where((t) => t.senderId.equals(entity.delegateePublicKey) & t.trustTier.equals(2)))
          .write(const HazardMarkersCompanion(trustTier: Value(4)));

      await (db.update(db.newsItems)..where((t) => t.senderId.equals(entity.delegateePublicKey) & t.trustTier.equals(2)))
          .write(const NewsItemsCompanion(trustTier: Value(4)));

      await (db.update(db.areas)..where((t) => t.senderId.equals(entity.delegateePublicKey) & t.trustTier.equals(2)))
          .write(const AreasCompanion(trustTier: Value(4)));
          
      await (db.delete(db.adminTrustedSenders)..where((t) => t.publicKey.equals(entity.delegateePublicKey))).go();
    });
  }
}
