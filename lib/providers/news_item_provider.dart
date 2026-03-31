import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/database.dart';
import '../database/tables.dart';
import 'database_provider.dart';

part 'news_item_provider.g.dart';

@riverpod
class NewsItemsController extends _$NewsItemsController {
  @override
  Stream<List<NewsItemEntity>> build() {
    final db = ref.watch(databaseProvider);
    return db.select(db.newsItems).watch();
  }

  Future<void> addNewsItem(NewsItemEntity item) async {
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      await db.into(db.newsItems).insert(
        NewsItemsCompanion.insert(
          id: item.id,
          title: item.title,
          content: item.content,
          timestamp: item.timestamp,
          senderId: item.senderId,
          signature: Value(item.signature),
          trustTier: item.trustTier,
          expiresAt: Value(item.expiresAt),
          imageId: Value(item.imageId),
        ),
        mode: InsertMode.insertOrReplace,
      );
      await db.into(db.seenMessageIds).insert(
        SeenMessageIdsCompanion.insert(
          messageId: item.id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> deleteNewsItem(String id) async {
    final db = ref.read(databaseProvider);
    
    final newsItem = await (db.select(db.newsItems)..where((t) => t.id.equals(id))).getSingleOrNull();

    await db.transaction(() async {
      await (db.delete(db.newsItems)..where((t) => t.id.equals(id))).go();
      await db.into(db.deletedItems).insert(
        DeletedItemsCompanion.insert(
          id: id,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrReplace,
      );
    });

    if (newsItem?.imageId != null && newsItem!.imageId!.isNotEmpty) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/${newsItem.imageId}');
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}

