import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:fixnum/fixnum.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../protos/models.pb.dart' as pb;
import '../providers/database_provider.dart';
import '../providers/p2p_provider.dart';

part 'cloud_sync_service.g.dart';

class CloudSyncState {
  final bool isSyncing;
  final DateTime? lastSyncTime;
  final bool hasInternet;
  final int pendingUploads;
  final bool syncTextOnly;
  final bool onlyTier1And2;

  CloudSyncState({
    this.isSyncing = false,
    this.lastSyncTime,
    this.hasInternet = false,
    this.pendingUploads = 0,
    this.syncTextOnly = false,
    this.onlyTier1And2 = false,
  });

  CloudSyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncTime,
    bool? hasInternet,
    int? pendingUploads,
    bool? syncTextOnly,
    bool? onlyTier1And2,
  }) {
    return CloudSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      hasInternet: hasInternet ?? this.hasInternet,
      pendingUploads: pendingUploads ?? this.pendingUploads,
      syncTextOnly: syncTextOnly ?? this.syncTextOnly,
      onlyTier1And2: onlyTier1And2 ?? this.onlyTier1And2,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudSyncState &&
          runtimeType == other.runtimeType &&
          isSyncing == other.isSyncing &&
          lastSyncTime == other.lastSyncTime &&
          hasInternet == other.hasInternet &&
          pendingUploads == other.pendingUploads &&
          syncTextOnly == other.syncTextOnly &&
          onlyTier1And2 == other.onlyTier1And2;

  @override
  int get hashCode => Object.hash(isSyncing, lastSyncTime, hasInternet, pendingUploads, syncTextOnly, onlyTier1And2);
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
    if (timestamp != null) {
      state = state.copyWith(
        lastSyncTime: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    }
  }

  Future<void> _updateStatus() async {
    if (state.isSyncing) return;
    
    final internet = await _hasInternet();
    
    int pending = 0;
    try {
      final db = ref.read(databaseProvider);
      final lastSync = state.lastSyncTime?.millisecondsSinceEpoch ?? 0;
      
      final recentSeen = await (db.select(db.seenMessageIds)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      final recentSeenSet = recentSeen.map((e) => e.messageId).toSet();

      final markers = (await db.select(db.hazardMarkers).get()).where((m) {
        if (state.onlyTier1And2 && m.trustTier > 2) return false;
        return recentSeenSet.contains('${m.id}_${m.timestamp}');
      }).toList();

      final news = (await db.select(db.newsItems).get()).where((n) {
        if (state.onlyTier1And2 && n.trustTier > 2) return false;
        return recentSeenSet.contains('${n.id}_${n.timestamp}');
      }).toList();

      final areas = (await db.select(db.areas).get()).where((a) {
        if (state.onlyTier1And2 && a.trustTier > 2) return false;
        return recentSeenSet.contains('${a.id}_${a.timestamp}');
      }).toList();

      final paths = (await db.select(db.paths).get()).where((p) {
        if (state.onlyTier1And2 && p.trustTier > 2) return false;
        return recentSeenSet.contains('${p.id}_${p.timestamp}');
      }).toList();

      final profiles = (await db.select(db.userProfiles).get()).where((p) => recentSeenSet.contains('${p.publicKey}_${p.timestamp}')).toList();
      final deleted = (await db.select(db.deletedItems).get()).where((d) => recentSeenSet.contains('del_${d.id}_${d.timestamp}')).toList();
      final delegations = (await db.select(db.adminTrustedSenders).get()).where((d) => recentSeenSet.contains('delg_${d.publicKey}_${d.timestamp}')).toList();
      final revocations = (await db.select(db.revokedDelegations).get()).where((r) => recentSeenSet.contains('rev_${r.delegateePublicKey}_${r.timestamp}')).toList();

      pending = markers.length + news.length + areas.length + paths.length + profiles.length + deleted.length + delegations.length + revocations.length;
    } catch (_) {}
    
    state = state.copyWith(hasInternet: internet, pendingUploads: pending);
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } on SocketException catch (_) {
      return false;
    }
    return false;
  }

  Future<bool> syncWithCloud() async {
    if (state.isSyncing) return false;
    
    final hasInternet = await _hasInternet();
    if (!hasInternet) {
      state = state.copyWith(hasInternet: false);
      return false;
    }

    state = state.copyWith(isSyncing: true, hasInternet: true);
    
    try {
      final syncStartTime = DateTime.now();
      final db = ref.read(databaseProvider);
      final lastSync = state.lastSyncTime?.millisecondsSinceEpoch ?? 0;
      
      final recentSeen = await (db.select(db.seenMessageIds)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      final recentSeenSet = recentSeen.map((e) => e.messageId).toSet();

      final markers = (await db.select(db.hazardMarkers).get()).where((m) {
        if (state.onlyTier1And2 && m.trustTier > 2) return false;
        return recentSeenSet.contains('${m.id}_${m.timestamp}');
      }).toList();

      final news = (await db.select(db.newsItems).get()).where((n) {
        if (state.onlyTier1And2 && n.trustTier > 2) return false;
        return recentSeenSet.contains('${n.id}_${n.timestamp}');
      }).toList();

      final areas = (await db.select(db.areas).get()).where((a) {
        if (state.onlyTier1And2 && a.trustTier > 2) return false;
        return recentSeenSet.contains('${a.id}_${a.timestamp}');
      }).toList();

      final paths = (await db.select(db.paths).get()).where((p) {
        if (state.onlyTier1And2 && p.trustTier > 2) return false;
        return recentSeenSet.contains('${p.id}_${p.timestamp}');
      }).toList();

      final profiles = (await db.select(db.userProfiles).get()).where((p) => recentSeenSet.contains('${p.publicKey}_${p.timestamp}')).toList();
      final deleted = (await db.select(db.deletedItems).get()).where((d) => recentSeenSet.contains('del_${d.id}_${d.timestamp}')).toList();
      final delegations = (await db.select(db.adminTrustedSenders).get()).where((d) => recentSeenSet.contains('delg_${d.publicKey}_${d.timestamp}')).toList();
      final revocations = (await db.select(db.revokedDelegations).get()).where((r) => recentSeenSet.contains('rev_${r.delegateePublicKey}_${r.timestamp}')).toList();
      
      final payload = pb.SyncPayload();

      for (final m in markers) {
        payload.markers.add(pb.HazardMarker(
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
        ));
      }

      for (final n in news) {
        payload.news.add(pb.NewsItem(
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
        ));
      }

      for (final a in areas) {
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
          areaMarker.coordinates.add(pb.Coordinate(
            latitude: coord['lat']!,
            longitude: coord['lng']!,
          ));
        }
        payload.areas.add(areaMarker);
      }

      for (final p in paths) {
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
          pathMarker.coordinates.add(pb.Coordinate(
            latitude: coord['lat']!,
            longitude: coord['lng']!,
          ));
        }
        payload.paths.add(pathMarker);
      }

      for (final p in profiles) {
        payload.profiles.add(pb.UserProfile(
          publicKey: p.publicKey,
          name: p.name,
          contactInfo: p.contactInfo,
          timestamp: Int64(p.timestamp),
          signature: p.signature,
        ));
      }

      for (final d in deleted) {
        payload.deletedItems.add(pb.DeletedItem(
          id: d.id,
          timestamp: Int64(d.timestamp),
        ));
      }

      for (final d in delegations) {
        payload.delegations.add(pb.TrustDelegation(
          id: 'delg_${d.publicKey}',
          delegatorPublicKey: d.delegatorPublicKey,
          delegateePublicKey: d.publicKey,
          timestamp: Int64(d.timestamp),
          signature: d.signature,
        ));
      }

      for (final r in revocations) {
        payload.revokedDelegations.add(pb.RevokedDelegation(
          delegateePublicKey: r.delegateePublicKey,
          delegatorPublicKey: r.delegatorPublicKey,
          timestamp: Int64(r.timestamp),
          signature: r.signature,
        ));
      }

      if (payload.markers.isNotEmpty || payload.news.isNotEmpty || payload.areas.isNotEmpty || payload.paths.isNotEmpty || payload.profiles.isNotEmpty || payload.deletedItems.isNotEmpty || payload.delegations.isNotEmpty || payload.revokedDelegations.isNotEmpty) {
        final encoded = base64Encode(payload.writeToBuffer());
        await Supabase.instance.client.from('sync_events').insert({
          'payload_base64': encoded,
        });
        print('CloudSync: Uploaded ${payload.markers.length} markers, ${payload.news.length} news, ${payload.areas.length} areas, ${payload.paths.length} paths to the cloud.');
      }

      if (!state.syncTextOnly) {
        final dir = await getApplicationDocumentsDirectory();
        final imageIds = [
          ...markers.map((m) => m.imageId).where((id) => id != null && id.isNotEmpty),
          ...news.map((n) => n.imageId).where((id) => id != null && id.isNotEmpty),
        ];
        
        for (final imageId in imageIds) {
          final file = File('${dir.path}/$imageId');
          if (await file.exists()) {
            try {
              await Supabase.instance.client.storage.from('images').upload(imageId!, file);
            } catch (e) {
              // Ignore if already exists or error
            }
          }
        }
      }

      // 2. "Download" new data from cloud
      final lastSyncIso = DateTime.fromMillisecondsSinceEpoch(lastSync).toUtc().toIso8601String();
      final response = await Supabase.instance.client
          .from('sync_events')
          .select()
          .gt('created_at', lastSyncIso)
          .order('created_at', ascending: true);

      for (final row in response) {
        final encoded = row['payload_base64'] as String;
        await ref.read(p2pServiceProvider.notifier).processPayload(encoded);
      }
      
      print('CloudSync: Downloaded new data from the cloud.');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_cloud_sync_time', syncStartTime.millisecondsSinceEpoch);

      state = state.copyWith(isSyncing: false, lastSyncTime: syncStartTime, pendingUploads: 0);
      return true;
    } catch (e) {
      print('CloudSync: Error syncing with cloud: $e');
      state = state.copyWith(isSyncing: false);
      return false;
    }
  }
}
