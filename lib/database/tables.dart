import 'package:drift/drift.dart';

class HazardMarkerEntity {
  final String id;
  final double latitude;
  final double longitude;
  final String type;
  final String description;
  final int timestamp;
  final String senderId;
  final String? signature;
  final int trustTier;

  HazardMarkerEntity({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.type,
    required this.description,
    required this.timestamp,
    required this.senderId,
    this.signature,
    required this.trustTier,
  });
}

@UseRowClass(HazardMarkerEntity)
class HazardMarkers extends Table {
  TextColumn get id => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  TextColumn get type => text()();
  TextColumn get description => text()();
  IntColumn get timestamp => integer()();
  TextColumn get senderId => text()();
  TextColumn get signature => text().nullable()();
  IntColumn get trustTier => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class NewsItemEntity {
  final String id;
  final String title;
  final String content;
  final int timestamp;
  final String senderId;
  final String? signature;
  final int trustTier;

  NewsItemEntity({
    required this.id,
    required this.title,
    required this.content,
    required this.timestamp,
    required this.senderId,
    this.signature,
    required this.trustTier,
  });
}

@UseRowClass(NewsItemEntity)
class NewsItems extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  IntColumn get timestamp => integer()();
  TextColumn get senderId => text()();
  TextColumn get signature => text().nullable()();
  IntColumn get trustTier => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncPayloadEntity {
  final String id;
  final Uint8List payload;
  final int timestamp;

  SyncPayloadEntity({
    required this.id,
    required this.payload,
    required this.timestamp,
  });
}

@UseRowClass(SyncPayloadEntity)
class SyncPayloads extends Table {
  TextColumn get id => text()();
  BlobColumn get payload => blob()();
  IntColumn get timestamp => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SeenMessageIdEntity {
  final String messageId;
  final int timestamp;

  SeenMessageIdEntity({
    required this.messageId,
    required this.timestamp,
  });
}

@UseRowClass(SeenMessageIdEntity)
class SeenMessageIds extends Table {
  TextColumn get messageId => text()();
  IntColumn get timestamp => integer()();

  @override
  Set<Column> get primaryKey => {messageId};
}

class TrustedSenderEntity {
  final String publicKey;
  final String name;

  TrustedSenderEntity({
    required this.publicKey,
    required this.name,
  });
}

@UseRowClass(TrustedSenderEntity)
class TrustedSenders extends Table {
  TextColumn get publicKey => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {publicKey};
}
