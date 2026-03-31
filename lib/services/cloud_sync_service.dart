import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/database_provider.dart';
import 'mock_gov_api_service.dart';

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
    
    _statusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
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
      
      final markers = await (db.select(db.hazardMarkers)..where((t) {
        var expr = t.timestamp.isBiggerThanValue(lastSync);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final news = await (db.select(db.newsItems)..where((t) {
        var expr = t.timestamp.isBiggerThanValue(lastSync);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final areas = await (db.select(db.areas)..where((t) {
        var expr = t.timestamp.isBiggerThanValue(lastSync);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final paths = await (db.select(db.paths)..where((t) {
        var expr = t.timestamp.isBiggerThanValue(lastSync);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      
      pending = markers.length + news.length + areas.length + paths.length;
    } catch (_) {}
    
    state = state.copyWith(hasInternet: internet, pendingUploads: pending);
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('example.com');
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
      // Simulate network delay for upload/download
      await Future.delayed(const Duration(seconds: 2));

      // 1. "Upload" local data
      final db = ref.read(databaseProvider);
      final lastSync = state.lastSyncTime?.millisecondsSinceEpoch ?? 0;
      
      final markers = await (db.select(db.hazardMarkers)..where((t) {
        var expr = t.timestamp.isBiggerThanValue(lastSync);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final news = await (db.select(db.newsItems)..where((t) {
        var expr = t.timestamp.isBiggerThanValue(lastSync);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final areas = await (db.select(db.areas)..where((t) {
        var expr = t.timestamp.isBiggerThanValue(lastSync);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      final paths = await (db.select(db.paths)..where((t) {
        var expr = t.timestamp.isBiggerThanValue(lastSync);
        if (state.onlyTier1And2) {
          expr = expr & t.trustTier.isSmallerOrEqualValue(2);
        }
        return expr;
      })).get();
      
      print('CloudSync: Uploaded ${markers.length} markers, ${news.length} news, ${areas.length} areas, ${paths.length} paths to the cloud.');
      if (state.syncTextOnly) {
        print('CloudSync: Skipped image uploads (Text Only mode).');
      }

      // 2. "Download" new data from cloud
      // We trigger the MockGovApiService to generate some new data as if it came from the cloud
      await ref.read(mockGovApiServiceProvider.notifier).fetchAndInjectMockData();
      
      print('CloudSync: Downloaded new data from the cloud.');

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_cloud_sync_time', now.millisecondsSinceEpoch);

      state = state.copyWith(isSyncing: false, lastSyncTime: now, pendingUploads: 0);
      return true;
    } catch (e) {
      print('CloudSync: Error syncing with cloud: $e');
      state = state.copyWith(isSyncing: false);
      return false;
    }
  }
}
