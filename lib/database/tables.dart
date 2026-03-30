import 'dart:convert';
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

class DeletedItemEntity {
  final String id;
  final int timestamp;

  DeletedItemEntity({
    required this.id,
    required this.timestamp,
  });
}

@UseRowClass(DeletedItemEntity)
class DeletedItems extends Table {
  TextColumn get id => text()();
  IntColumn get timestamp => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class UntrustedSenderEntity {
  final String publicKey;

  UntrustedSenderEntity({
    required this.publicKey,
  });
}

@UseRowClass(UntrustedSenderEntity)
class UntrustedSenders extends Table {
  TextColumn get publicKey => text()();

  @override
  Set<Column> get primaryKey => {publicKey};
}

class UserProfileEntity {
  final String publicKey;
  final String name;
  final String contactInfo;
  final int timestamp;
  final String signature;

  UserProfileEntity({
    required this.publicKey,
    required this.name,
    required this.contactInfo,
    required this.timestamp,
    required this.signature,
  });
}

@UseRowClass(UserProfileEntity)
class UserProfiles extends Table {
  TextColumn get publicKey => text()();
  TextColumn get name => text()();
  TextColumn get contactInfo => text()();
  IntColumn get timestamp => integer()();
  TextColumn get signature => text()();

  @override
  Set<Column> get primaryKey => {publicKey};
}

class CoordinateListConverter extends TypeConverter<List<Map<String, double>>, String> {
  const CoordinateListConverter();

  @override
  List<Map<String, double>> fromSql(String fromDb) {
    final List<dynamic> decoded = json.decode(fromDb);
    return decoded.map((e) => Map<String, double>.from(e)).toList();
  }

  @override
  String toSql(List<Map<String, double>> value) {
    return json.encode(value);
  }
}

class AreaEntity {
  final String id;
  final List<Map<String, double>> coordinates;
  final String type;
  final String description;
  final int timestamp;
  final String senderId;
  final String? signature;
  final int trustTier;

  AreaEntity({
    required this.id,
    required this.coordinates,
    required this.type,
    required this.description,
    required this.timestamp,
    required this.senderId,
    this.signature,
    required this.trustTier,
  });
}

@UseRowClass(AreaEntity)
class Areas extends Table {
  TextColumn get id => text()();
  TextColumn get coordinates => text().map(const CoordinateListConverter())();
  TextColumn get type => text()();
  TextColumn get description => text()();
  IntColumn get timestamp => integer()();
  TextColumn get senderId => text()();
  TextColumn get signature => text().nullable()();
  IntColumn get trustTier => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
