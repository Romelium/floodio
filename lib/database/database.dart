import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [HazardMarkers, NewsItems, SyncPayloads, SeenMessageIds, TrustedSenders, UserProfiles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'floodio_db'));

  @override
  int get schemaVersion => 3;

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
      },
    );
  }
}
