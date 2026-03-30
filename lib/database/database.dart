import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [HazardMarkers, NewsItems, DeletedItems, SeenMessageIds, TrustedSenders, UntrustedSenders, UserProfiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.createTable(trustedSenders);
        }
        if (from < 3) {
          await m.createTable(userProfiles);
        }
        if (from < 4) {
          await m.createTable(deletedItems);
          await m.createTable(untrustedSenders);
          await customStatement('DROP TABLE IF EXISTS sync_payloads;');
        }
      },
    );
  }
}
