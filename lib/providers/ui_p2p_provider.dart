import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/p2p_models.dart';
import 'p2p_provider.dart';

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
    FlutterBackgroundService().invoke('connectToDevice', {'deviceAddress': device.deviceAddress});
  }
}
