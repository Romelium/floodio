import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

import '../models/p2p_models.dart';
import '../utils/sound_utils.dart';
import 'hero_stats_provider.dart';
import 'offline_regions_provider.dart';
import 'p2p_provider.dart';
import 'settings_provider.dart';
import 'terminal_log_provider.dart';

part 'ui_p2p_provider.g.dart';

@Riverpod(keepAlive: true)
class UiP2pService extends _$UiP2pService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  Uint8List? _chirpBytes;

  @override
  P2pState build() {
    _chirpBytes = generateWalkieTalkieChirp();

    ref.onDispose(() {
      _audioPlayer.dispose();
    });

    final service = FlutterBackgroundService();

    service.on('p2pStateUpdate').listen((event) {
      if (event != null) {
        final newState = P2pState.fromMap(Map<String, dynamic>.from(event));
        
        if (state.isSyncing && !newState.isSyncing) {
          if (newState.syncMessage == 'Successfully synced data.' || 
              newState.syncMessage == 'Up to date.' ||
              newState.syncMessage == 'Map updated successfully.') {
            _playChirp();
          }
        }

        state = newState;
      }
    });

    service.on('terminalLog').listen((event) {
      if (event != null && event['log'] != null) {
        ref.read(terminalLogControllerProvider.notifier).addLog(event['log']);
      }
    });

    service.on('reloadOfflineRegions').listen((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      ref.invalidate(offlineRegionsProvider);
    });

    service.on('reloadSettings').listen((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      ref.invalidate(appSettingsProvider);
    });

    service.on('reloadHeroStats').listen((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      ref.invalidate(heroStatsControllerProvider);
    });

    service.invoke('requestState');

    return const P2pState();
  }

  void _playChirp() async {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    
    if (_chirpBytes != null) {
      try {
        RingerModeStatus ringerStatus = RingerModeStatus.unknown;
        try {
          ringerStatus = await SoundMode.ringerModeStatus;
        } catch (_) {}
        
        if (ringerStatus == RingerModeStatus.normal || ringerStatus == RingerModeStatus.unknown) {
          await _audioPlayer.play(BytesSource(_chirpBytes!));
        }
      } catch (e) {
        print("Error playing chirp: $e");
      }
    }
  }

  void toggleAutoSync() {
    FlutterBackgroundService().invoke('toggleAutoSync');
  }

  void startHosting() {
    FlutterBackgroundService().invoke('startHosting');
  }

  void stopHosting() {
    FlutterBackgroundService().invoke('stopHosting');
  }

  void startScanning() {
    FlutterBackgroundService().invoke('startScanning');
  }

  void stopScanning() {
    FlutterBackgroundService().invoke('stopScanning');
  }

  void disconnect() {
    FlutterBackgroundService().invoke('disconnect');
  }

  void connectToDevice(AppDiscoveredDevice device) {
    FlutterBackgroundService().invoke('connectToDevice', {
      'deviceAddress': device.deviceAddress,
    });
  }

  void requestMapRegion(OfflineRegion region) {
    FlutterBackgroundService().invoke('requestMapRegion', region.toJson());
  }

  void broadcastMapRegion(OfflineRegion? region) {
    FlutterBackgroundService().invoke('broadcastMapRegion', {
      'region': region?.toJson(),
    });
  }

  void triggerSync() {
    FlutterBackgroundService().invoke('triggerSync');
  }

  void broadcastText(String text) {
    FlutterBackgroundService().invoke('broadcastText', {'text': text});
  }

  void broadcastFile(File file) {
    FlutterBackgroundService().invoke('broadcastFile', {'filePath': file.path});
  }

  void processPayload(String base64Data) {
    FlutterBackgroundService().invoke('processPayload', {'data': base64Data});
  }

  void processPayloadFromFile(String filePath) {
    FlutterBackgroundService().invoke('processPayloadFromFile', {'filePath': filePath});
  }

  void mockDiscoveredDevice() {
    FlutterBackgroundService().invoke('mockDiscoveredDevice');
  }

  void mockConnectedClient() {
    FlutterBackgroundService().invoke('mockConnectedClient');
  }

  void mockReceivedHazard() {
    FlutterBackgroundService().invoke('mockReceivedHazard');
  }

  void mockReceivedCriticalHazard() {
    FlutterBackgroundService().invoke('mockReceivedCriticalHazard');
  }

  void mockHostState() {
    FlutterBackgroundService().invoke('mockHostState');
  }

  void mockClientState() {
    FlutterBackgroundService().invoke('mockClientState');
  }

  void mockSyncProgress() {
    FlutterBackgroundService().invoke('mockSyncProgress');
  }
}
