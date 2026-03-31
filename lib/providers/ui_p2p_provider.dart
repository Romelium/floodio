import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/p2p_models.dart';
import 'p2p_provider.dart';
import 'offline_regions_provider.dart';

part 'ui_p2p_provider.g.dart';

@Riverpod(keepAlive: true)
class UiP2pService extends _$UiP2pService {
  Timer? _timer;

  @override
  P2pState build() {
    final service = FlutterBackgroundService();
    
    service.on('p2pStateUpdate').listen((event) {
      if (event != null) {
        state = P2pState.fromMap(Map<String, dynamic>.from(event));
      }
    });

    service.invoke('requestState');

    _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (await service.isRunning()) {
        service.invoke('requestState');
      }
    });

    ref.onDispose(() {
      _timer?.cancel();
    });

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
    FlutterBackgroundService().invoke('connectToDevice', {'deviceAddress': device.deviceAddress});
  }

  void requestMapRegion(OfflineRegion region) {
    FlutterBackgroundService().invoke('requestMapRegion', region.toJson());
  }

  void broadcastMapRegion(OfflineRegion? region) {
    FlutterBackgroundService().invoke('broadcastMapRegion', {'region': region?.toJson()});
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
}
