import 'package:audioplayers/audioplayers.dart';
import 'package:drift/drift.dart';
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';
import 'package:torch_light/torch_light.dart';
import 'package:volume_controller/volume_controller.dart';

import '../database/tables.dart';
import 'database_provider.dart';

part 'critical_alert_provider.g.dart';

class RedAlertState {
  final bool isActive;
  final bool isMuted;
  final String? latestAlertTitle;

  RedAlertState({
    this.isActive = false,
    this.isMuted = false,
    this.latestAlertTitle,
  });
}

@Riverpod(keepAlive: true)
class RedAlertController extends _$RedAlertController {
  List<HazardMarkerEntity> _markers = [];
  List<NewsItemEntity> _news = [];
  List<AreaEntity> _areas = [];
  List<PathEntity> _paths = [];
  final Set<String> _notifiedIds = {};
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isVibrating = false;
  bool _isFlashing = false;

  @override
  RedAlertState build() {
    final db = ref.watch(databaseProvider);

    void check() {
      final now = DateTime.now().millisecondsSinceEpoch;
      final activeMarkers = _markers.where((t) => t.expiresAt == null || t.expiresAt! > now).toList();
      final activeNews = _news.where((t) => t.expiresAt == null || t.expiresAt! > now).toList();
      final activeAreas = _areas.where((t) => t.expiresAt == null || t.expiresAt! > now).toList();
      final activePaths = _paths.where((t) => t.expiresAt == null || t.expiresAt! > now).toList();

      final hasAlerts = activeMarkers.isNotEmpty || activeNews.isNotEmpty || activeAreas.isNotEmpty || activePaths.isNotEmpty;

      String? latestTitle;
      int latestTs = 0;

      for (final m in activeMarkers) {
        if (m.timestamp > latestTs) {
          latestTs = m.timestamp;
          latestTitle = m.type;
        }
      }
      for (final n in activeNews) {
        if (n.timestamp > latestTs) {
          latestTs = n.timestamp;
          latestTitle = n.title;
        }
      }
      for (final a in activeAreas) {
        if (a.timestamp > latestTs) {
          latestTs = a.timestamp;
          latestTitle = a.type;
        }
      }
      for (final p in activePaths) {
        if (p.timestamp > latestTs) {
          latestTs = p.timestamp;
          latestTitle = p.type;
        }
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

      if (hasAlerts != state.isActive || latestTitle != state.latestAlertTitle || newAlert) {
        state = RedAlertState(
          isActive: hasAlerts,
          isMuted: newAlert ? false : state.isMuted,
          latestAlertTitle: latestTitle,
        );
      }

      if (newAlert && !state.isMuted) {
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
      _isFlashing = false;
      _audioPlayer.dispose();
      try {
        TorchLight.disableTorch();
      } catch (_) {}
    });

    return RedAlertState();
  }

  void _triggerAlarm() async {
    if (state.isMuted) return;
    _isVibrating = true;
    _isFlashing = true;
    _vibrateLoop();
    _flashLoop();
    try {
      try {
        await SoundMode.setSoundMode(RingerModeStatus.normal);
      } catch (_) {}
      try {
        VolumeController.instance.showSystemUI = false;
        await VolumeController.instance.setVolume(1.0);
      } catch (_) {}

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

  void _flashLoop() async {
    bool torchOn = false;
    while (_isFlashing) {
      try {
        if (torchOn) {
          await TorchLight.disableTorch();
        } else {
          await TorchLight.enableTorch();
        }
        torchOn = !torchOn;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 300));
    }
    try {
      await TorchLight.disableTorch();
    } catch (_) {}
  }

  void stopAlarm() {
    _isVibrating = false;
    _isFlashing = false;
    try {
      _audioPlayer.stop();
    } catch (_) {}
    try {
      TorchLight.disableTorch();
    } catch (_) {}
    state = RedAlertState(
      isActive: state.isActive,
      isMuted: true,
      latestAlertTitle: state.latestAlertTitle,
    );
  }
}
