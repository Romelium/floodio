import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../database/tables.dart';
import 'database_provider.dart';

part 'critical_alert_provider.g.dart';

@Riverpod(keepAlive: true)
class RedAlertController extends _$RedAlertController {
  List<HazardMarkerEntity> _markers = [];
  List<NewsItemEntity> _news = [];
  List<AreaEntity> _areas = [];
  List<PathEntity> _paths = [];
  final Set<String> _notifiedIds = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isVibrating = false;

  @override
  bool build() {
    final db = ref.watch(databaseProvider);

    void check() {
      final now = DateTime.now().millisecondsSinceEpoch;
      final activeMarkers = _markers.where((t) => t.expiresAt == null || t.expiresAt! > now).toList();
      final activeNews = _news.where((t) => t.expiresAt == null || t.expiresAt! > now).toList();
      final activeAreas = _areas.where((t) => t.expiresAt == null || t.expiresAt! > now).toList();
      final activePaths = _paths.where((t) => t.expiresAt == null || t.expiresAt! > now).toList();

      final hasAlerts = activeMarkers.isNotEmpty || activeNews.isNotEmpty || activeAreas.isNotEmpty || activePaths.isNotEmpty;

      if (hasAlerts != state) {
        state = hasAlerts;
      }

      bool newAlert = false;
      for (final m in activeMarkers) {
        if (!_notifiedIds.contains(m.id)) {
          _notifiedIds.add(m.id);
          newAlert = true;
        }
      }
      for (final n in activeNews) {
        if (!_notifiedIds.contains(n.id)) {
          _notifiedIds.add(n.id);
          newAlert = true;
        }
      }
      for (final a in activeAreas) {
        if (!_notifiedIds.contains(a.id)) {
          _notifiedIds.add(a.id);
          newAlert = true;
        }
      }
      for (final p in activePaths) {
        if (!_notifiedIds.contains(p.id)) {
          _notifiedIds.add(p.id);
          newAlert = true;
        }
      }

      if (newAlert) {
        _triggerAlarm();
      }
    }

    final mSub = (db.select(db.hazardMarkers)..where((t) => t.trustTier.equals(1) & t.isCritical.equals(true))).watch().listen((data) {
      _markers = data;
      check();
    });
    final nSub = (db.select(db.newsItems)..where((t) => t.trustTier.equals(1) & t.isCritical.equals(true))).watch().listen((data) {
      _news = data;
      check();
    });
    final aSub = (db.select(db.areas)..where((t) => t.trustTier.equals(1) & t.isCritical.equals(true))).watch().listen((data) {
      _areas = data;
      check();
    });
    final pSub = (db.select(db.paths)..where((t) => t.trustTier.equals(1) & t.isCritical.equals(true))).watch().listen((data) {
      _paths = data;
      check();
    });

    ref.onDispose(() {
      mSub.cancel();
      nSub.cancel();
      aSub.cancel();
      pSub.cancel();
      _isVibrating = false;
      _audioPlayer.dispose();
    });

    return false;
  }

  void _triggerAlarm() async {
    _isVibrating = true;
    _vibrateLoop();
    try {
      _audioPlayer.setReleaseMode(ReleaseMode.loop);
      await _audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/alarms/alarm_clock.ogg'));
    } catch (_) {}
  }

  void _vibrateLoop() async {
    while (_isVibrating) {
      try {
        HapticFeedback.heavyImpact();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  void stopAlarm() {
    _isVibrating = false;
    try {
      _audioPlayer.stop();
    } catch (_) {}
  }
}
