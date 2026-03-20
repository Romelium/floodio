import 'dart:async';

import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'p2p_provider.g.dart';

class P2pState {
  final bool isHosting;
  final bool isScanning;
  final HotspotHostState? hostState;
  final HotspotClientState? clientState;
  final List<BleDiscoveredDevice> discoveredDevices;
  final List<String> receivedTexts;

  const P2pState({
    this.isHosting = false,
    this.isScanning = false,
    this.hostState,
    this.clientState,
    this.discoveredDevices = const [],
    this.receivedTexts = const [],
  });

  P2pState copyWith({
    bool? isHosting,
    bool? isScanning,
    HotspotHostState? hostState,
    bool clearHostState = false,
    HotspotClientState? clientState,
    bool clearClientState = false,
    List<BleDiscoveredDevice>? discoveredDevices,
    List<String>? receivedTexts,
  }) {
    return P2pState(
      isHosting: isHosting ?? this.isHosting,
      isScanning: isScanning ?? this.isScanning,
      hostState: clearHostState ? null : (hostState ?? this.hostState),
      clientState: clearClientState ? null : (clientState ?? this.clientState),
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      receivedTexts: receivedTexts ?? this.receivedTexts,
    );
  }
}

@Riverpod(keepAlive: true)
class P2pService extends _$P2pService {
  FlutterP2pHost? _host;
  FlutterP2pClient? _client;

  StreamSubscription? _hostStateSub;
  StreamSubscription? _clientStateSub;
  StreamSubscription? _hostTextSub;
  StreamSubscription? _clientTextSub;
  StreamSubscription? _scanSub;

  @override
  P2pState build() {
    ref.onDispose(() {
      _hostStateSub?.cancel();
      _clientStateSub?.cancel();
      _hostTextSub?.cancel();
      _clientTextSub?.cancel();
      _scanSub?.cancel();
      _host?.dispose();
      _client?.dispose();
    });
    return const P2pState();
  }

  Future<void> startHosting() async {
    if (_host != null) return;

    _host = FlutterP2pHost();
    await _host!.initialize();

    if (!await _host!.checkP2pPermissions()) await _host!.askP2pPermissions();
    if (!await _host!.checkBluetoothPermissions()) await _host!.askBluetoothPermissions();
    if (!await _host!.checkLocationEnabled()) await _host!.enableLocationServices();
    if (!await _host!.checkWifiEnabled()) await _host!.enableWifiServices();
    if (!await _host!.checkBluetoothEnabled()) await _host!.enableBluetoothServices();

    _hostStateSub = _host!.streamHotspotState().listen((state) {
      this.state = this.state.copyWith(hostState: state);
    });

    _hostTextSub = _host!.streamReceivedTexts().listen((text) {
      _handleReceivedText(text);
    });

    try {
      await _host!.createGroup(advertise: true);
      state = state.copyWith(isHosting: true);
    } catch (e) {
      print("Failed to create group: $e");
      await stopHosting();
    }
  }

  Future<void> stopHosting() async {
    await _host?.removeGroup();
    await _host?.dispose();
    _hostStateSub?.cancel();
    _hostTextSub?.cancel();
    _host = null;
    state = state.copyWith(isHosting: false, clearHostState: true);
  }

  Future<void> startScanning() async {
    if (_client != null) return;

    _client = FlutterP2pClient();
    await _client!.initialize();

    if (!await _client!.checkP2pPermissions()) await _client!.askP2pPermissions();
    if (!await _client!.checkBluetoothPermissions()) await _client!.askBluetoothPermissions();
    if (!await _client!.checkLocationEnabled()) await _client!.enableLocationServices();
    if (!await _client!.checkWifiEnabled()) await _client!.enableWifiServices();
    if (!await _client!.checkBluetoothEnabled()) await _client!.enableBluetoothServices();

    _clientStateSub = _client!.streamHotspotState().listen((state) {
      this.state = this.state.copyWith(clientState: state);
    });

    _clientTextSub = _client!.streamReceivedTexts().listen((text) {
      _handleReceivedText(text);
    });

    state = state.copyWith(isScanning: true, discoveredDevices: []);

    try {
      _scanSub = await _client!.startScan((devices) {
        state = state.copyWith(discoveredDevices: devices);
      });
    } catch (e) {
      print("Failed to start scan: $e");
      state = state.copyWith(isScanning: false);
    }
  }

  Future<void> connectToDevice(BleDiscoveredDevice device) async {
    if (_client == null) return;
    await stopScanning();
    try {
      await _client!.connectWithDevice(device);
    } catch (e) {
      print("Connection failed: $e");
    }
  }

  Future<void> stopScanning() async {
    await _scanSub?.cancel();
    await _client?.stopScan();
    state = state.copyWith(isScanning: false);
  }

  Future<void> disconnect() async {
    await _client?.disconnect();
    await _client?.dispose();
    _clientStateSub?.cancel();
    _clientTextSub?.cancel();
    _scanSub?.cancel();
    _client = null;
    state = state.copyWith(clearClientState: true, discoveredDevices: []);
  }

  void _handleReceivedText(String text) {
    print("Received text: $text");
    state = state.copyWith(
      receivedTexts: [...state.receivedTexts, text],
    );
  }

  Future<void> broadcastText(String text) async {
    if (_host != null && state.hostState?.isActive == true) {
      await _host!.broadcastText(text);
    } else if (_client != null && state.clientState?.isActive == true) {
      await _client!.broadcastText(text);
    }
  }
}
