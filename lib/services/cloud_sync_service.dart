import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:fixnum/fixnum.dart';
import 'package:floodio/database/database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../protos/models.pb.dart' as pb;
import '../providers/database_provider.dart';
import '../providers/ui_p2p_provider.dart';

part 'cloud_sync_service.g.dart';

class CloudSyncState {
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final int lastSyncEventId;
  final bool hasInternet;
  final int pendingUploads;
  final bool syncTextOnly;
  final bool onlyTier1And2;
  final String? syncMessage;
  final double? syncProgress;

  CloudSyncState({
    this.isSyncing = false,
    this.lastSyncTime,
    this.lastSyncEventId = 0,
    this.hasInternet = false,
    this.pendingUploads = 0,
    this.syncTextOnly = false,
    this.onlyTier1And2 = false,
    this.syncMessage,
    this.syncProgress,
  });

  CloudSyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncTime,
    int? lastSyncEventId,
    bool? hasInternet,
    int? pendingUploads,
    bool? syncTextOnly,
    bool? onlyTier1And2,
    String? syncMessage,
    bool clearSyncMessage = false,
    double? syncProgress,
    bool clearSyncProgress = false,
  }) {
    return CloudSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastSyncEventId: lastSyncEventId ?? this.lastSyncEventId,
      hasInternet: hasInternet ?? this.hasInternet,
      pendingUploads: pendingUploads ?? this.pendingUploads,
      syncTextOnly: syncTextOnly ?? this.syncTextOnly,
      onlyTier1And2: onlyTier1And2 ?? this.onlyTier1And2,
      syncMessage: clearSyncMessage ? null : (syncMessage ?? this.syncMessage),
      syncProgress: clearSyncProgress ? null : (syncProgress ?? this.syncProgress),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudSyncState &&
          runtimeType == other.runtimeType &&
          isSyncing == other.isSyncing &&
          lastSyncTime == other.lastSyncTime &&
          lastSyncEventId == other.lastSyncEventId &&
          hasInternet == other.hasInternet &&
          pendingUploads == other.pendingUploads &&
          syncTextOnly == other.syncTextOnly &&
          onlyTier1And2 == other.onlyTier1And2 &&
          syncMessage == other.syncMessage &&
          syncProgress == other.syncProgress;

  @override
  int get hashCode => Object.hash(
    isSyncing,
    lastSyncTime,
    lastSyncEventId,
    hasInternet,
    pendingUploads,
    syncTextOnly,
    onlyTier1And2,
    syncMessage,
    syncProgress,
  );
}

@Riverpod(keepAlive: true)
class CloudSyncService extends _$CloudSyncService {
  Timer? _timer;
  Timer? _statusTimer;

  @override
  CloudSyncState build() {
    ref.onDispose(() {
      _timer?.cancel();
      _statusTimer?.cancel();
    });

    _loadLastSyncTime().then((_) => _updateStatus());

    // Start periodic check (e.g., every 5 minutes)
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      syncWithCloud();
    });

    _statusTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _updateStatus();
    });

    return CloudSyncState();
  }

  void setSyncTextOnly(bool value) {
    state = state.copyWith(syncTextOnly: value);
    _updateStatus();
  }

  void setOnlyTier1And2(bool value) {
    state = state.copyWith(onlyTier1And2: value);
    _updateStatus();
  }

  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('last_cloud_sync_time');
    final eventId = prefs.getInt('last_sync_event_id') ?? 0;
    
    state = state.copyWith(
      lastSyncTime: timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null,
      lastSyncEventId: eventId,
    );
  }

  Future<void> _updateStatus() async {
    print("[CloudSyncService] Updating status...");
    if (state.isSyncing) return;

    final internet = await _hasInternet();

    int pending = 0;
    try {
      final db = ref.read(databaseProvider);

      final recentSeen = await (db.select(
        db.seenMessageIds,
      )..where((t) => t.uploadedToCloud.equals(false))).get();
      final recentSeenSet = recentSeen.map((e) => e.messageId).toSet();

      final skippedMessageIds = <String>{};

      if (state.onlyTier1And2) {
        final markers = await (db.selectOnly(db.hazardMarkers)
              ..addColumns([db.hazardMarkers.id, db.hazardMarkers.timestamp])
              ..where(db.hazardMarkers.trustTier.isBiggerThanValue(2)))
            .get();
        for (final row in markers) {
          skippedMessageIds.add('${row.read(db.hazardMarkers.id)}_${row.read(db.hazardMarkers.timestamp)}');
        }
        
        final news = await (db.selectOnly(db.newsItems)
              ..addColumns([db.newsItems.id, db.newsItems.timestamp])
              ..where(db.newsItems.trustTier.isBiggerThanValue(2)))
            .get();
        for (final row in news) {
          skippedMessageIds.add('${row.read(db.newsItems.id)}_${row.read(db.newsItems.timestamp)}');
        }

        final areas = await (db.selectOnly(db.areas)
              ..addColumns([db.areas.id, db.areas.timestamp])
              ..where(db.areas.trustTier.isBiggerThanValue(2)))
            .get();
        for (final row in areas) {
          skippedMessageIds.add('${row.read(db.areas.id)}_${row.read(db.areas.timestamp)}');
        }

        final paths = await (db.selectOnly(db.paths)
              ..addColumns([db.paths.id, db.paths.timestamp])
              ..where(db.paths.trustTier.isBiggerThanValue(2)))
            .get();
        for (final row in paths) {
          skippedMessageIds.add('${row.read(db.paths.id)}_${row.read(db.paths.timestamp)}');
        }
      }

      pending = recentSeenSet.difference(skippedMessageIds).length;
    } catch (_) {}

    print("[CloudSyncService] Status updated. HasInternet: $internet, PendingUploads: $pending");
    state = state.copyWith(hasInternet: internet, pendingUploads: pending);
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 5));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Future<bool> syncWithCloud() async {
    print("[CloudSyncService] Initiating syncWithCloud...");
    if (state.isSyncing) return false;

    final hasInternet = await _hasInternet();
    if (!hasInternet) {
      state = state.copyWith(hasInternet: false);
      return false;
    }

    state = state.copyWith(
      isSyncing: true, 
      hasInternet: true,
      syncMessage: 'Preparing data for upload...',
      syncProgress: 0.1,
    );

    try {
      final db = ref.read(databaseProvider);

      final recentSeen = await (db.select(
        db.seenMessageIds,
      )..where((t) => t.uploadedToCloud.equals(false))).get();
      
      // Limit upload batch size to prevent massive payloads and timeouts
      final recentSeenSet = recentSeen.map((e) => e.messageId).take(500).toSet();

      final markers = await (db.select(db.hazardMarkers)..where((t) {
        Expression<bool> expr = const Constant(true);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final filteredMarkers = markers.where((m) => recentSeenSet.contains('${m.id}_${m.timestamp}')).toList();

      final news = await (db.select(db.newsItems)..where((t) {
        Expression<bool> expr = const Constant(true);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final filteredNews = news.where((n) => recentSeenSet.contains('${n.id}_${n.timestamp}')).toList();

      final areas = await (db.select(db.areas)..where((t) {
        Expression<bool> expr = const Constant(true);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final filteredAreas = areas.where((a) => recentSeenSet.contains('${a.id}_${a.timestamp}')).toList();

      final paths = await (db.select(db.paths)..where((t) {
        Expression<bool> expr = const Constant(true);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final filteredPaths = paths.where((p) => recentSeenSet.contains('${p.id}_${p.timestamp}')).toList();

      final profiles = (await db.select(db.userProfiles).get())
          .where((p) => recentSeenSet.contains('${p.publicKey}_${p.timestamp}'))
          .toList();
      final deleted = await (db.select(db.deletedItems)..where((t) => t.uploadedToCloud.equals(false))).get();
      final filteredDeleted = deleted.take(500).toList();
      
      final delegations = (await db.select(db.adminTrustedSenders).get())
          .where(
            (d) => recentSeenSet.contains('delg_${d.publicKey}_${d.timestamp}'),
          )
          .toList();
      final revocations = (await db.select(db.revokedDelegations).get())
          .where(
            (r) => recentSeenSet.contains(
              'rev_${r.delegateePublicKey}_${r.timestamp}',
            ),
          )
          .toList();

      final payload = pb.SyncPayload();
      final uploadedMessageIds = <String>[];
      final uploadedDeletedIds = <String>[];

      for (final m in filteredMarkers) {
        uploadedMessageIds.add('${m.id}_${m.timestamp}');
        payload.markers.add(
          pb.HazardMarker(
            id: m.id,
            latitude: m.latitude,
            longitude: m.longitude,
            type: m.type,
            description: m.description,
            timestamp: Int64(m.timestamp),
            senderId: m.senderId,
            signature: m.signature ?? '',
            trustTier: m.trustTier,
            imageId: m.imageId ?? '',
            expiresAt: Int64(m.expiresAt ?? 0),
            isCritical: m.isCritical,
          ),
        );
      }

      for (final n in filteredNews) {
        uploadedMessageIds.add('${n.id}_${n.timestamp}');
        payload.news.add(
          pb.NewsItem(
            id: n.id,
            title: n.title,
            content: n.content,
            timestamp: Int64(n.timestamp),
            senderId: n.senderId,
            signature: n.signature ?? '',
            trustTier: n.trustTier,
            expiresAt: Int64(n.expiresAt ?? 0),
            imageId: n.imageId ?? '',
            isCritical: n.isCritical,
          ),
        );
      }

      for (final a in filteredAreas) {
        uploadedMessageIds.add('${a.id}_${a.timestamp}');
        final areaMarker = pb.AreaMarker(
          id: a.id,
          type: a.type,
          description: a.description,
          timestamp: Int64(a.timestamp),
          senderId: a.senderId,
          signature: a.signature ?? '',
          trustTier: a.trustTier,
          expiresAt: Int64(a.expiresAt ?? 0),
          isCritical: a.isCritical,
        );
        for (final coord in a.coordinates) {
          areaMarker.coordinates.add(
            pb.Coordinate(latitude: coord['lat']!, longitude: coord['lng']!),
          );
        }
        payload.areas.add(areaMarker);
      }

      for (final p in filteredPaths) {
        uploadedMessageIds.add('${p.id}_${p.timestamp}');
        final pathMarker = pb.PathMarker(
          id: p.id,
          type: p.type,
          description: p.description,
          timestamp: Int64(p.timestamp),
          senderId: p.senderId,
          signature: p.signature ?? '',
          trustTier: p.trustTier,
          expiresAt: Int64(p.expiresAt ?? 0),
          isCritical: p.isCritical,
        );
        for (final coord in p.coordinates) {
          pathMarker.coordinates.add(
            pb.Coordinate(latitude: coord['lat']!, longitude: coord['lng']!),
          );
        }
        payload.paths.add(pathMarker);
      }

      for (final p in profiles) {
        uploadedMessageIds.add('${p.publicKey}_${p.timestamp}');
        payload.profiles.add(
          pb.UserProfile(
            publicKey: p.publicKey,
            name: p.name,
            contactInfo: p.contactInfo,
            timestamp: Int64(p.timestamp),
            signature: p.signature,
          ),
        );
      }

      for (final d in filteredDeleted) {
        uploadedDeletedIds.add(d.id);
        uploadedMessageIds.add('del_${d.id}_${d.timestamp}');
        payload.deletedItems.add(
          pb.DeletedItem(id: d.id, timestamp: Int64(d.timestamp)),
        );
      }

      for (final d in delegations) {
        uploadedMessageIds.add('delg_${d.publicKey}_${d.timestamp}');
        payload.delegations.add(
          pb.TrustDelegation(
            id: 'delg_${d.publicKey}',
            delegatorPublicKey: d.delegatorPublicKey,
            delegateePublicKey: d.publicKey,
            timestamp: Int64(d.timestamp),
            signature: d.signature,
          ),
        );
      }

      for (final r in revocations) {
        uploadedMessageIds.add('rev_${r.delegateePublicKey}_${r.timestamp}');
        payload.revokedDelegations.add(
          pb.RevokedDelegation(
            delegateePublicKey: r.delegateePublicKey,
            delegatorPublicKey: r.delegatorPublicKey,
            timestamp: Int64(r.timestamp),
            signature: r.signature,
          ),
        );
      }

      if (!state.syncTextOnly) {
        state = state.copyWith(
          syncMessage: 'Uploading images...',
          syncProgress: 0.2,
        );
        final dir = await getApplicationDocumentsDirectory();
        final imageIds = [
          ...filteredMarkers
              .map((m) => m.imageId)
              .where((id) => id != null && id.isNotEmpty),
          ...filteredNews
              .map((n) => n.imageId)
              .where((id) => id != null && id.isNotEmpty),
        ];

        for (final imageId in imageIds) {
          final file = File('${dir.path}/$imageId');
          if (await file.exists()) {
            try {
              await Supabase.instance.client.storage
                  .from('images')
                  .upload(imageId!, file)
                  .timeout(const Duration(seconds: 30));
            } catch (e) {
              print('[CloudSyncService] Image upload error (might already exist): $e');
              // We don't throw here. If an image fails to upload (e.g. due to size limits, 
              // network blip, or it already exists), we still want the text payload to sync.
              // The image will just be missing on the other end, which the app handles gracefully.
            }
          }
        }
      }

      if (payload.markers.isNotEmpty ||
          payload.news.isNotEmpty ||
          payload.areas.isNotEmpty ||
          payload.paths.isNotEmpty ||
          payload.profiles.isNotEmpty ||
          payload.deletedItems.isNotEmpty ||
          payload.delegations.isNotEmpty ||
          payload.revokedDelegations.isNotEmpty) {
        
        state = state.copyWith(
          syncMessage: 'Uploading to cloud...',
          syncProgress: 0.3,
        );
        final encoded = await Isolate.run(() => base64Encode(payload.writeToBuffer()));
        
        try {
          await Supabase.instance.client.from('sync_events').insert({
            'payload_base64': encoded,
          }).timeout(const Duration(seconds: 30));
          print(
            '[CloudSyncService] Uploaded ${payload.markers.length} markers, ${payload.news.length} news, ${payload.areas.length} areas, ${payload.paths.length} paths to the cloud.',
          );
        } catch (e) {
          print('[CloudSyncService] Failed to upload payload to Supabase: $e');
          throw Exception('Failed to upload payload to cloud: $e');
        }
      }

      await db.transaction(() async {
        if (uploadedMessageIds.isNotEmpty) {
          for (var i = 0; i < uploadedMessageIds.length; i += 500) {
            final chunk = uploadedMessageIds.skip(i).take(500).toList();
            await (db.update(db.seenMessageIds)..where((t) => t.messageId.isIn(chunk)))
                .write(const SeenMessageIdsCompanion(uploadedToCloud: Value(true)));
          }
        }
        if (uploadedDeletedIds.isNotEmpty) {
          for (var i = 0; i < uploadedDeletedIds.length; i += 500) {
            final chunk = uploadedDeletedIds.skip(i).take(500).toList();
            await (db.update(db.deletedItems)..where((t) => t.id.isIn(chunk)))
                .write(const DeletedItemsCompanion(uploadedToCloud: Value(true)));
          }
        }
      });

      // 2. "Download" new data from cloud
      state = state.copyWith(
        syncMessage: 'Checking for new data...',
        syncProgress: 0.5,
      );
      
      bool hasMore = true;
      int currentLastId = state.lastSyncEventId;
      bool downloadedAny = false;
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/cloud_sync_payload_${DateTime.now().millisecondsSinceEpoch}.dat');
      final combinedPayload = pb.SyncPayload();

      int downloadBatches = 0;
      while (hasMore && downloadBatches < 10) { // Limit to 10 batches (500 events) per sync to avoid OOM/timeouts
        downloadBatches++;
        try {
          final response = await Supabase.instance.client
              .from('sync_events')
              .select()
              .gt('id', currentLastId)
              .order('id', ascending: true)
              .limit(50)
              .timeout(const Duration(seconds: 30));

          if (response.isEmpty) {
            hasMore = false;
          } else {
            downloadedAny = true;
            for (final row in response) {
              final encoded = row['payload_base64'] as String;
              try {
                final data = base64Decode(encoded);
                final payload = pb.SyncPayload.fromBuffer(data);

                if (payload.markers.isNotEmpty ||
                    payload.news.isNotEmpty ||
                    payload.profiles.isNotEmpty ||
                    payload.deletedItems.isNotEmpty ||
                    payload.areas.isNotEmpty ||
                    payload.paths.isNotEmpty ||
                    payload.delegations.isNotEmpty ||
                    payload.revokedDelegations.isNotEmpty) {
                  combinedPayload.markers.addAll(payload.markers);
                  combinedPayload.news.addAll(payload.news);
                  combinedPayload.profiles.addAll(payload.profiles);
                  combinedPayload.deletedItems.addAll(payload.deletedItems);
                  combinedPayload.areas.addAll(payload.areas);
                  combinedPayload.paths.addAll(payload.paths);
                  combinedPayload.delegations.addAll(payload.delegations);
                  combinedPayload.revokedDelegations.addAll(payload.revokedDelegations);
                }
              } catch (e) {
                print('[CloudSyncService] Error decoding payload from cloud: $e');
              }
              currentLastId = row['id'] as int;
            }
          }
        } catch (e) {
          print('[CloudSyncService] Error downloading from cloud: $e');
          hasMore = false; // Stop downloading, but process what we have so far
          if (!downloadedAny) {
            throw Exception('Failed to download from cloud: $e');
          }
        }
      }

      bool hasCombinedData = combinedPayload.markers.isNotEmpty ||
          combinedPayload.news.isNotEmpty ||
          combinedPayload.profiles.isNotEmpty ||
          combinedPayload.deletedItems.isNotEmpty ||
          combinedPayload.areas.isNotEmpty ||
          combinedPayload.paths.isNotEmpty ||
          combinedPayload.delegations.isNotEmpty ||
          combinedPayload.revokedDelegations.isNotEmpty;

      if (downloadedAny && hasCombinedData) {
        state = state.copyWith(
          syncMessage: 'Processing downloaded data...',
          syncProgress: 0.9,
        );
        await tempFile.writeAsBytes(combinedPayload.writeToBuffer());
        
        final completer = Completer<bool>();
        final sub = FlutterBackgroundService().on('processPayloadComplete').listen((event) {
          if (event != null && event['success'] == true) {
            if (!completer.isCompleted) completer.complete(true);
          } else {
            if (!completer.isCompleted) completer.complete(false);
          }
        });

        ref.read(uiP2pServiceProvider.notifier).processPayloadFromFile(tempFile.path);

        print('[CloudSyncService] Downloaded and sent new data to background service. Waiting for processing...');
        
        bool processSuccess = false;
        try {
          processSuccess = await completer.future.timeout(const Duration(minutes: 5));
        } catch (e) {
          print('[CloudSyncService] Timeout waiting for payload processing.');
        } finally {
          sub.cancel();
        }

        if (!processSuccess) {
          throw Exception('Failed to process downloaded payload');
        }
      } else {
        print('[CloudSyncService] No new data found in the cloud.');
      }

      final prefs = await SharedPreferences.getInstance();
      final syncEndTime = DateTime.now();
      await prefs.setInt(
        'last_cloud_sync_time',
        syncEndTime.millisecondsSinceEpoch,
      );
      await prefs.setInt('last_sync_event_id', currentLastId);

      state = state.copyWith(
        isSyncing: false,
        lastSyncTime: syncEndTime,
        lastSyncEventId: currentLastId,
        pendingUploads: 0,
        clearSyncMessage: true,
        clearSyncProgress: true,
      );
      return true;
    } catch (e) {
      print('[CloudSyncService] Error syncing with cloud: $e');
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Error: $e',
        clearSyncProgress: true,
      );
      Future.delayed(const Duration(seconds: 3), () => state = state.copyWith(clearSyncMessage: true));
      return false;
    }
  }
}
