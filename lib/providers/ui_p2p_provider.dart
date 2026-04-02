import 'dart:io';

import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/p2p_models.dart';
import 'offline_regions_provider.dart';
import 'p2p_provider.dart';
import 'settings_provider.dart';

part 'ui_p2p_provider.g.dart';

@Riverpod(keepAlive: true)
class UiP2pService extends _$UiP2pService {
  @override
  P2pState build() {
    final service = FlutterBackgroundService();

    service.on('p2pStateUpdate').listen((event) {
      if (event != null) {
        state = P2pState.fromMap(Map<String, dynamic>.from(event));
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

    service.invoke('requestState');

    return const P2pState();
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
}
