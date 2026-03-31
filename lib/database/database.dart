import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [HazardMarkers, NewsItems, DeletedItems, SeenMessageIds, TrustedSenders, UntrustedSenders, UserProfiles, Areas, AdminTrustedSenders])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 7;

  Future<void> cleanupOldData() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    await transaction(() async {
      await (delete(hazardMarkers)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
      await (delete(newsItems)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
      await (delete(areas)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
      await (delete(deletedItems)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
      await (delete(seenMessageIds)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
    });
  }

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
        if (from < 5) {
          await m.createTable(areas);
        }
        if (from < 6) {
          await m.addColumn(hazardMarkers, hazardMarkers.imageId);
        }
        if (from < 7) {
          await m.createTable(adminTrustedSenders);
        }
      },
    );
  }
}
