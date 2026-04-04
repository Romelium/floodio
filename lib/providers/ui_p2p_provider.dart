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
  Uint8List? _successBytes;
  Uint8List? _errorBytes;
  Uint8List? _connectionBytes;
  Uint8List? _notificationBytes;

  @override
  P2pState build() {
    _chirpBytes = generateWalkieTalkieChirp();
    _successBytes = generateSuccessChirp();
    _errorBytes = generateErrorChirp();
    _connectionBytes = generateConnectionChirp();
    _notificationBytes = generateNotificationChirp();

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
            playSuccess();
          } else if (newState.syncMessage?.startsWith('Error') == true || newState.syncMessage?.startsWith('Failed') == true) {
            playError();
          } else {
            playChirp();
          }
        }

        if (!state.isConnecting && newState.isConnecting) {
          playConnection();
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

  void playSuccess() => _playSound(_successBytes, HapticFeedback.mediumImpact);
  void playError() => _playSound(_errorBytes, HapticFeedback.heavyImpact);
  void playConnection() => _playSound(_connectionBytes, HapticFeedback.lightImpact);
  void playNotification() => _playSound(_notificationBytes, HapticFeedback.lightImpact);
  void playChirp() => _playSound(_chirpBytes, HapticFeedback.lightImpact);

  void _playSound(Uint8List? bytes, Future<void> Function() haptic) async {
    try {
      haptic();
    } catch (_) {}
    
    if (bytes != null) {
      try {
        RingerModeStatus ringerStatus = RingerModeStatus.unknown;
        try {
          ringerStatus = await SoundMode.ringerModeStatus;
        } catch (_) {}
        
        if (ringerStatus == RingerModeStatus.normal || ringerStatus == RingerModeStatus.unknown) {
          await _audioPlayer.play(BytesSource(bytes));
        }
      } catch (e) {
        print("Error playing chirp: $e");
      }
    }
  }

  void toggleAutoSync() {
    HapticFeedback.lightImpact();
    FlutterBackgroundService().invoke('toggleAutoSync');
  }

  void startHosting() {
    HapticFeedback.lightImpact();
    FlutterBackgroundService().invoke('startHosting');
  }

  void stopHosting() {
    HapticFeedback.lightImpact();
    FlutterBackgroundService().invoke('stopHosting');
  }

  void startScanning() {
    HapticFeedback.lightImpact();
    FlutterBackgroundService().invoke('startScanning');
  }

  void stopScanning() {
    HapticFeedback.lightImpact();
    FlutterBackgroundService().invoke('stopScanning');
  }

  void disconnect() {
    HapticFeedback.lightImpact();
    FlutterBackgroundService().invoke('disconnect');
  }

  void connectToDevice(AppDiscoveredDevice device) {
    HapticFeedback.mediumImpact();
    FlutterBackgroundService().invoke('connectToDevice', {
      'deviceAddress': device.deviceAddress,
    });
  }

  void requestMapRegion(OfflineRegion region) {
    HapticFeedback.mediumImpact();
    FlutterBackgroundService().invoke('requestMapRegion', region.toJson());
  }

  void broadcastMapRegion(OfflineRegion? region) {
    HapticFeedback.mediumImpact();
    FlutterBackgroundService().invoke('broadcastMapRegion', {
      'region': region?.toJson(),
    });
  }

  void triggerSync() {
    HapticFeedback.mediumImpact();
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
