import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [HazardMarkers, NewsItems, DeletedItems, SeenMessageIds, TrustedSenders, UntrustedSenders, UserProfiles, Areas, Paths, AdminTrustedSenders, RevokedDelegations])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 12;

  Future<void> cleanupOldData() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    
    final expiredMarkers = await (select(hazardMarkers)..where((t) =>
        (t.expiresAt.isNotNull() & t.expiresAt.isSmallerThanValue(now)) |
        (t.expiresAt.isNull() & t.timestamp.isSmallerThanValue(cutoff))
    )).get();
    
    final expiredNews = await (select(newsItems)..where((t) =>
        (t.expiresAt.isNotNull() & t.expiresAt.isSmallerThanValue(now)) |
        (t.expiresAt.isNull() & t.timestamp.isSmallerThanValue(cutoff))
    )).get();

    final imageIdsToDelete = [
      ...expiredMarkers.map((m) => m.imageId).where((id) => id != null && id.isNotEmpty),
      ...expiredNews.map((n) => n.imageId).where((id) => id != null && id.isNotEmpty),
    ];

    await transaction(() async {
      await (delete(hazardMarkers)..where((t) => 
          (t.expiresAt.isNotNull() & t.expiresAt.isSmallerThanValue(now)) |
          (t.expiresAt.isNull() & t.timestamp.isSmallerThanValue(cutoff))
      )).go();
      await (delete(newsItems)..where((t) => 
          (t.expiresAt.isNotNull() & t.expiresAt.isSmallerThanValue(now)) |
          (t.expiresAt.isNull() & t.timestamp.isSmallerThanValue(cutoff))
      )).go();
      await (delete(areas)..where((t) => 
          (t.expiresAt.isNotNull() & t.expiresAt.isSmallerThanValue(now)) |
          (t.expiresAt.isNull() & t.timestamp.isSmallerThanValue(cutoff))
      )).go();
      await (delete(paths)..where((t) =>
          (t.expiresAt.isNotNull() & t.expiresAt.isSmallerThanValue(now)) |
          (t.expiresAt.isNull() & t.timestamp.isSmallerThanValue(cutoff))
      )).go();
      await (delete(deletedItems)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
      await (delete(seenMessageIds)..where((t) => t.timestamp.isSmallerThanValue(cutoff))).go();
    });

    if (imageIdsToDelete.isNotEmpty) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        for (final imageId in imageIdsToDelete) {
          final file = File('${dir.path}/$imageId');
          if (await file.exists()) {
            await file.delete();
          }
        }
      } catch (_) {}
    }
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
        if (from < 8) {
          await m.addColumn(hazardMarkers, hazardMarkers.expiresAt);
          await m.addColumn(newsItems, newsItems.expiresAt);
          await m.addColumn(areas, areas.expiresAt);
        }
        if (from < 9) {
          await m.createTable(revokedDelegations);
        }
        if (from < 10) {
          await m.addColumn(newsItems, newsItems.imageId);
        }
        if (from < 11) {
          await m.createTable(paths);
        }
        if (from < 12) {
          await m.addColumn(hazardMarkers, hazardMarkers.isCritical);
        }
      },
    );
  }
}
