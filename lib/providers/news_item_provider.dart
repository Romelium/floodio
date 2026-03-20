import 'package:drift/drift.dart';
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
    await db.into(db.newsItems).insert(
      NewsItemsCompanion.insert(
        id: item.id,
        title: item.title,
        content: item.content,
        timestamp: item.timestamp,
        senderId: item.senderId,
        signature: Value(item.signature),
        trustTier: item.trustTier,
      ),
      mode: InsertMode.insertOrReplace,
    );
  }
}
