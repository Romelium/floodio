import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'trusted_sender_provider.g.dart';

@riverpod
class TrustedSendersController extends _$TrustedSendersController {
  @override
  Stream<List<TrustedSenderEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.trustedSenders).watch();
  }

  Future<void> addTrustedSender(String publicKey, String name) async {
    final db = ref.read(databaseProvider);
    await db.into(db.trustedSenders).insert(
      TrustedSendersCompanion.insert(
        publicKey: publicKey,
        name: name,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }
}
