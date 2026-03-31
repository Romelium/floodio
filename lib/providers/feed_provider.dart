import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/tables.dart';
import 'database_provider.dart';

part 'feed_provider.g.dart';

@riverpod
class FeedLimit extends _$FeedLimit {
  @override
  int build() => 50;

  void loadMore() {
    state += 50;
  }
}

class FeedFilter {
  final String searchQuery;
  final String typeFilter;
  final int? trustFilter;

  FeedFilter({
    this.searchQuery = '',
    this.typeFilter = 'All',
    this.trustFilter,
  });

  FeedFilter copyWith({
    String? searchQuery,
    String? typeFilter,
    int? trustFilter,
    bool clearTrustFilter = false,
  }) {
    return FeedFilter(
      searchQuery: searchQuery ?? this.searchQuery,
      typeFilter: typeFilter ?? this.typeFilter,
      trustFilter: clearTrustFilter ? null : (trustFilter ?? this.trustFilter),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedFilter &&
          runtimeType == other.runtimeType &&
          searchQuery == other.searchQuery &&
          typeFilter == other.typeFilter &&
          trustFilter == other.trustFilter;

  @override
  int get hashCode => Object.hash(searchQuery, typeFilter, trustFilter);
}

@riverpod
class FeedFilterController extends _$FeedFilterController {
  @override
  FeedFilter build() => FeedFilter();

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void updateTypeFilter(String type) {
    state = state.copyWith(typeFilter: type);
  }

  void updateTrustFilter(int? tier) {
    state = state.copyWith(trustFilter: tier, clearTrustFilter: tier == null);
  }
}

@riverpod
Stream<List<HazardMarkerEntity>> filteredHazardMarkers(Ref ref) {
  final db = ref.watch(databaseProvider);
  final limit = ref.watch(feedLimitProvider);
  final filter = ref.watch(feedFilterControllerProvider);

  var query = db.select(db.hazardMarkers);
  query.where((t) {
    Expression<bool> expr = const Constant(true);
    if (filter.trustFilter != null) {
      expr = expr & t.trustTier.equals(filter.trustFilter!);
    }
    if (filter.searchQuery.isNotEmpty) {
      final q = '%${filter.searchQuery}%';
      expr = expr & (t.type.like(q) | t.description.like(q));
    }
    return expr;
  });
  query.orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
  query.limit(limit);
  return query.watch();
}

@riverpod
Stream<List<NewsItemEntity>> filteredNewsItems(Ref ref) {
  final db = ref.watch(databaseProvider);
  final limit = ref.watch(feedLimitProvider);
  final filter = ref.watch(feedFilterControllerProvider);

  var query = db.select(db.newsItems);
  query.where((t) {
    Expression<bool> expr = const Constant(true);
    if (filter.trustFilter != null) {
      expr = expr & t.trustTier.equals(filter.trustFilter!);
    }
    if (filter.searchQuery.isNotEmpty) {
      final q = '%${filter.searchQuery}%';
      expr = expr & (t.title.like(q) | t.content.like(q));
    }
    return expr;
  });
  query.orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
  query.limit(limit);
  return query.watch();
}

@riverpod
Stream<List<AreaEntity>> filteredAreas(Ref ref) {
  final db = ref.watch(databaseProvider);
  final limit = ref.watch(feedLimitProvider);
  final filter = ref.watch(feedFilterControllerProvider);

  var query = db.select(db.areas);
  query.where((t) {
    Expression<bool> expr = const Constant(true);
    if (filter.trustFilter != null) {
      expr = expr & t.trustTier.equals(filter.trustFilter!);
    }
    if (filter.searchQuery.isNotEmpty) {
      final q = '%${filter.searchQuery}%';
      expr = expr & (t.type.like(q) | t.description.like(q));
    }
    return expr;
  });
  query.orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
  query.limit(limit);
  return query.watch();
}

@riverpod
Stream<List<PathEntity>> filteredPaths(Ref ref) {
  final db = ref.watch(databaseProvider);
  final limit = ref.watch(feedLimitProvider);
  final filter = ref.watch(feedFilterControllerProvider);

  var query = db.select(db.paths);
  query.where((t) {
    Expression<bool> expr = const Constant(true);
    if (filter.trustFilter != null) {
      expr = expr & t.trustTier.equals(filter.trustFilter!);
    }
    if (filter.searchQuery.isNotEmpty) {
      final q = '%${filter.searchQuery}%';
      expr = expr & (t.type.like(q) | t.description.like(q));
    }
    return expr;
  });
  query.orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
  query.limit(limit);
  return query.watch();
}

@riverpod
List<dynamic> combinedFeed(Ref ref) {
  final filter = ref.watch(feedFilterControllerProvider);
  
  final markers = ref.watch(filteredHazardMarkersProvider).value ?? [];
  final news = ref.watch(filteredNewsItemsProvider).value ?? [];
  final areas = ref.watch(filteredAreasProvider).value ?? [];
  final paths = ref.watch(filteredPathsProvider).value ?? [];

  var combined = <dynamic>[];

  if (filter.typeFilter == 'All' || filter.typeFilter == 'Hazards') {
    combined.addAll(markers);
  }
  if (filter.typeFilter == 'All' || filter.typeFilter == 'News') {
    combined.addAll(news);
  }
  if (filter.typeFilter == 'All' || filter.typeFilter == 'Areas') {
    combined.addAll(areas);
  }
  if (filter.typeFilter == 'All' || filter.typeFilter == 'Paths') {
    combined.addAll(paths);
  }

  combined.sort((a, b) => (b.timestamp as int).compareTo(a.timestamp as int));
  
  final limit = ref.watch(feedLimitProvider);
  return combined.take(limit).toList();
}
