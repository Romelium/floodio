import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/database_provider.dart';
import 'mock_gov_api_service.dart';

part 'cloud_sync_service.g.dart';

class CloudSyncState {
  final bool isSyncing;
  final DateTime? lastSyncTime;

  CloudSyncState({this.isSyncing = false, this.lastSyncTime});
}

@Riverpod(keepAlive: true)
class CloudSyncService extends _$CloudSyncService {
  Timer? _timer;

  @override
  CloudSyncState build() {
    ref.onDispose(() {
      _timer?.cancel();
    });
    
    _loadLastSyncTime();

    // Start periodic check (e.g., every 5 minutes)
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      syncWithCloud();
    });
    
    return CloudSyncState();
  }

  Future<void> _loadLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timestamp = prefs.getInt('last_cloud_sync_time');
    if (timestamp != null) {
      state = CloudSyncState(
        isSyncing: state.isSyncing,
        lastSyncTime: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    }
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
    if (!hasInternet) return false;

    state = CloudSyncState(isSyncing: true, lastSyncTime: state.lastSyncTime);
    
    try {
      // Simulate network delay for upload/download
      await Future.delayed(const Duration(seconds: 2));

      // 1. "Upload" local data
      final db = ref.read(databaseProvider);
      final markers = await db.select(db.hazardMarkers).get();
      final news = await db.select(db.newsItems).get();
      final areas = await db.select(db.areas).get();
      
      print('CloudSync: Uploaded ${markers.length} markers, ${news.length} news, ${areas.length} areas to the cloud.');

      // 2. "Download" new data from cloud
      // We trigger the MockGovApiService to generate some new data as if it came from the cloud
      await ref.read(mockGovApiServiceProvider.notifier).fetchAndInjectMockData();
      
      print('CloudSync: Downloaded new data from the cloud.');

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_cloud_sync_time', now.millisecondsSinceEpoch);

      state = CloudSyncState(isSyncing: false, lastSyncTime: now);
      return true;
    } catch (e) {
      print('CloudSync: Error syncing with cloud: $e');
      state = CloudSyncState(isSyncing: false, lastSyncTime: state.lastSyncTime);
      return false;
    }
  }
}
