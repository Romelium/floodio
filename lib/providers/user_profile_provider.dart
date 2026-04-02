import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'user_profile_provider.g.dart';

@Riverpod(keepAlive: true)
class UserProfilesController extends _$UserProfilesController {
  @override
  Stream<List<UserProfileEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.userProfiles).watch();
  }

  Future<void> saveProfile(UserProfileEntity profile) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db
          .into(db.userProfiles)
          .insert(
            UserProfilesCompanion.insert(
              publicKey: profile.publicKey,
              name: profile.name,
              contactInfo: profile.contactInfo,
              timestamp: profile.timestamp,
              signature: profile.signature,
            ),
            mode: InsertMode.insertOrReplace,
          );
      await db
          .into(db.seenMessageIds)
          .insert(
            SeenMessageIdsCompanion.insert(
              messageId: '${profile.publicKey}_${profile.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
            mode: InsertMode.insertOrReplace,
          );
    });
  }
}
