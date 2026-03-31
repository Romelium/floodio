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

  CloudSyncState({
    this.isSyncing = false,
    this.lastSyncTime,
    this.hasInternet = false,
    this.pendingUploads = 0,
  });

  CloudSyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncTime,
    bool? hasInternet,
    int? pendingUploads,
  }) {
    return CloudSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      hasInternet: hasInternet ?? this.hasInternet,
      pendingUploads: pendingUploads ?? this.pendingUploads,
    );
  }
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
    
        _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
          _updateStatus();
        });
    
    return CloudSyncState();
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
      
      final markers = await (db.select(db.hazardMarkers)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      final news = await (db.select(db.newsItems)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      final areas = await (db.select(db.areas)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      final paths = await (db.select(db.paths)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      
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
      
      final markers = await (db.select(db.hazardMarkers)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      final news = await (db.select(db.newsItems)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      final areas = await (db.select(db.areas)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      final paths = await (db.select(db.paths)..where((t) => t.timestamp.isBiggerThanValue(lastSync))).get();
      
      print('CloudSync: Uploaded ${markers.length} markers, ${news.length} news, ${areas.length} areas, ${paths.length} paths to the cloud.');

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
