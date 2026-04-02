import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fixnum/fixnum.dart';
import 'package:floodio/providers/location_provider.dart';
import 'package:floodio/services/background_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/crypto_service.dart';
import '../database/connection.dart';
import '../database/database.dart';
import '../models/p2p_models.dart';
import '../protos/models.pb.dart' as pb;
import '../services/map_cache_service.dart';
import '../utils/bloom_filter.dart';
import 'database_provider.dart';
import 'local_user_provider.dart'; // <-- Added import
import 'offline_regions_provider.dart';
import 'settings_provider.dart';

part 'p2p_provider.g.dart';

// A unique UUID specifically for the Floodio app's BLE discovery
const String _floodioServiceUuid = "0f0540bd-4a04-46d0-b90d-b0447453ec3a";

class P2pState {
  final bool isHosting;
  final bool isScanning;
  final bool isSyncing;
  final bool isConnecting;
  final bool isAutoSyncing;
  final String? syncMessage;
  final double? syncProgress;
  final int? syncEstimatedSeconds;
  final DateTime? lastSyncTime;
  final AppHostState? hostState;
  final AppClientState? clientState;
  final List<AppDiscoveredDevice> discoveredDevices;
  final List<AppClientInfo> connectedClients;
  final List<String> receivedTexts;
  final List<OfflineRegion> peerOfflineRegions;

  const P2pState({
    this.isHosting = false,
    this.isScanning = false,
    this.isSyncing = false,
    this.isConnecting = false,
    this.isAutoSyncing = false,
    this.syncMessage,
    this.syncProgress,
    this.syncEstimatedSeconds,
    this.lastSyncTime,
    this.hostState,
    this.clientState,
    this.discoveredDevices = const [],
    this.connectedClients = const [],
    this.receivedTexts = const [],
    this.peerOfflineRegions = const [],
  });

  P2pState copyWith({
    bool? isHosting,
    bool? isScanning,
    bool? isSyncing,
    bool? isConnecting,
    bool? isAutoSyncing,
    String? syncMessage,
    double? syncProgress,
    bool clearSyncProgress = false,
    int? syncEstimatedSeconds,
    bool clearSyncEstimatedSeconds = false,
    DateTime? lastSyncTime,
    AppHostState? hostState,
    bool clearHostState = false,
    AppClientState? clientState,
    bool clearClientState = false,
    List<AppDiscoveredDevice>? discoveredDevices,
    List<AppClientInfo>? connectedClients,
    List<String>? receivedTexts,
    List<OfflineRegion>? peerOfflineRegions,
  }) {
    return P2pState(
      isHosting: isHosting ?? this.isHosting,
      isScanning: isScanning ?? this.isScanning,
      isSyncing: isSyncing ?? this.isSyncing,
      isConnecting: isConnecting ?? this.isConnecting,
      isAutoSyncing: isAutoSyncing ?? this.isAutoSyncing,
      syncMessage: syncMessage ?? this.syncMessage,
      syncProgress: clearSyncProgress
          ? null
          : (syncProgress ?? this.syncProgress),
      syncEstimatedSeconds: (clearSyncProgress || clearSyncEstimatedSeconds)
          ? null
          : (syncEstimatedSeconds ?? this.syncEstimatedSeconds),
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      hostState: clearHostState ? null : (hostState ?? this.hostState),
      clientState: clearClientState ? null : (clientState ?? this.clientState),
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
      connectedClients: connectedClients ?? this.connectedClients,
      receivedTexts: receivedTexts ?? this.receivedTexts,
      peerOfflineRegions: peerOfflineRegions ?? this.peerOfflineRegions,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'isHosting': isHosting,
      'isScanning': isScanning,
      'isSyncing': isSyncing,
      'isConnecting': isConnecting,
      'isAutoSyncing': isAutoSyncing,
      'syncMessage': syncMessage,
      'syncProgress': syncProgress,
      'syncEstimatedSeconds': syncEstimatedSeconds,
      'lastSyncTime': lastSyncTime?.millisecondsSinceEpoch,
      'hostState': hostState != null
          ? {
              'isActive': hostState!.isActive,
              'ssid': hostState!.ssid,
              'preSharedKey': hostState!.preSharedKey,
              'hostIpAddress': hostState!.hostIpAddress,
            }
          : null,
      'clientState': clientState != null
          ? {
              'isActive': clientState!.isActive,
              'hostSsid': clientState!.hostSsid,
              'hostGatewayIpAddress': clientState!.hostGatewayIpAddress,
              'hostIpAddress': clientState!.hostIpAddress,
            }
          : null,
      'discoveredDevices': discoveredDevices
          .map(
            (d) => {
              'deviceAddress': d.deviceAddress,
              'deviceName': d.deviceName,
            },
          )
          .toList(),
      'connectedClients': connectedClients
          .map((c) => {'id': c.id, 'username': c.username, 'isHost': c.isHost})
          .toList(),
      'peerOfflineRegions': peerOfflineRegions.map((r) => r.toJson()).toList(),
    };
  }

  factory P2pState.fromMap(Map<String, dynamic> map) {
    return P2pState(
      isHosting: map['isHosting'] ?? false,
      isScanning: map['isScanning'] ?? false,
      isSyncing: map['isSyncing'] ?? false,
      isConnecting: map['isConnecting'] ?? false,
      isAutoSyncing: map['isAutoSyncing'] ?? false,
      syncMessage: map['syncMessage'],
      syncProgress: map['syncProgress']?.toDouble(),
      syncEstimatedSeconds: map['syncEstimatedSeconds'] as int?,
      lastSyncTime: map['lastSyncTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastSyncTime'])
          : null,
      hostState: map['hostState'] != null
          ? AppHostState.fromMap(Map<String, dynamic>.from(map['hostState']))
          : null,
      clientState: map['clientState'] != null
          ? AppClientState.fromMap(
              Map<String, dynamic>.from(map['clientState']),
            )
          : null,
      discoveredDevices:
          (map['discoveredDevices'] as List?)
              ?.map(
                (d) =>
                    AppDiscoveredDevice.fromMap(Map<String, dynamic>.from(d)),
              )
              .toList() ??
          [],
      connectedClients:
          (map['connectedClients'] as List?)
              ?.map((c) => AppClientInfo.fromMap(Map<String, dynamic>.from(c)))
              .toList() ??
          [],
      peerOfflineRegions:
          (map['peerOfflineRegions'] as List?)
              ?.map((r) => OfflineRegion.fromJson(Map<String, dynamic>.from(r)))
              .toList() ??
          [],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is P2pState &&
        other.isHosting == isHosting &&
        other.isScanning == isScanning &&
        other.isSyncing == isSyncing &&
        other.isConnecting == isConnecting &&
        other.isAutoSyncing == isAutoSyncing &&
        other.syncMessage == syncMessage &&
        other.syncProgress == syncProgress &&
        other.syncEstimatedSeconds == syncEstimatedSeconds &&
        other.lastSyncTime == lastSyncTime &&
        other.hostState == hostState &&
        other.clientState == clientState &&
        listEquals(other.discoveredDevices, discoveredDevices) &&
        listEquals(other.connectedClients, connectedClients) &&
        listEquals(other.receivedTexts, receivedTexts) &&
        listEquals(other.peerOfflineRegions, peerOfflineRegions);
  }

  @override
  int get hashCode {
    return Object.hash(
      isHosting,
      isScanning,
      isSyncing,
      isConnecting,
      isAutoSyncing,
      syncMessage,
      syncProgress,
      syncEstimatedSeconds,
      lastSyncTime,
      hostState,
      clientState,
      Object.hashAll(discoveredDevices),
      Object.hashAll(connectedClients),
      Object.hashAll(receivedTexts),
      Object.hashAll(peerOfflineRegions),
    );
  }
}

@Riverpod(
  keepAlive: true,
  dependencies: [
    database,
    OfflineRegions,
    CryptoService,
    mapCacheService,
    sharedPreferences,
    LocalUserController,
  ],
)
class P2pService extends _$P2pService {
  late FlutterP2pHost _host;
  late FlutterP2pClient _client;
  bool _isInitialized = false;

  StreamSubscription? _hostStateSub;
  StreamSubscription? _clientStateSub;
  StreamSubscription? _hostClientListSub;
  StreamSubscription? _hostTextSub;
  StreamSubscription? _clientTextSub;
  StreamSubscription? _scanSub;
  StreamSubscription? _hostReceivedFilesSub;
  StreamSubscription? _clientReceivedFilesSub;
  StreamSubscription? _hostSentFilesSub;
  StreamSubscription? _clientSentFilesSub;
  Timer? _autoSyncTimer;
  bool _disposed = false;

  bool _lastRoleWasHost = false;
  int _idleTicks = 0;
  List<BleDiscoveredDevice> _rawDiscoveredDevices = [];
  final Map<String, DateTime> _downloadStartTimes = {};
  bool _isToggling = false;

  String? _originalBluetoothName;
  static const _systemChannel = MethodChannel('com.example.floodio/system');
  bool _isSwitchingRoles = false;

  Future<void> _setBluetoothName(String prefix) async {
    try {
      if (!isBackgroundIsolate) {
        final currentName =
            await _systemChannel.invokeMethod('getBluetoothName') as String?;
        if (currentName != null && !currentName.startsWith('FLD-')) {
          _originalBluetoothName = currentName;
        }
        final localUser = await ref.read(localUserControllerProvider.future);
        final username = localUser.name.isNotEmpty ? localUser.name : "User";

        String safeName = username;
        while (utf8.encode(safeName).length > 15 && safeName.isNotEmpty) {
          safeName = safeName.substring(0, safeName.length - 1);
        }
        await _systemChannel.invokeMethod('setBluetoothName', {
          'name': '$prefix: $safeName',
        });
      }
    } catch (e) {
      print("Failed to set BT name: $e");
    }
  }

  Future<void> _restoreBluetoothName() async {
    try {
      if (!isBackgroundIsolate && _originalBluetoothName != null) {
        await _systemChannel.invokeMethod('setBluetoothName', {
          'name': _originalBluetoothName,
        });
      }
    } catch (e) {
      print("Failed to restore BT name: $e");
    }
  }

  @override
  P2pState build() {
    ref.onDispose(() {
      _disposed = true;
      _autoSyncTimer?.cancel();
      _hostStateSub?.cancel();
      _clientStateSub?.cancel();
      _hostClientListSub?.cancel();
      _hostTextSub?.cancel();
      _clientTextSub?.cancel();
      _scanSub?.cancel();
      _hostReceivedFilesSub?.cancel();
      _clientReceivedFilesSub?.cancel();
      _hostSentFilesSub?.cancel();
      _clientSentFilesSub?.cancel();
      if (_isInitialized) {
        _host.dispose();
        _client.dispose();
      }
      _restoreBluetoothName();
    });
    return const P2pState();
  }

  Future<void> _initP2p() async {
    if (_isInitialized) return;
    final localUser = await ref.read(localUserControllerProvider.future);
    final username = localUser.name.isNotEmpty
        ? localUser.name
        : "Floodio User";

    _host = FlutterP2pHost(
      serviceUuid: _floodioServiceUuid,
      username: username,
    );
    _client = FlutterP2pClient(
      serviceUuid: _floodioServiceUuid,
      username: username,
    );

    await _host.initialize();
    await _client.initialize();

    _hostStateSub = _host.streamHotspotState().listen((hotspotState) {
      state = state.copyWith(
        hostState: AppHostState(
          isActive: hotspotState.isActive,
          ssid: hotspotState.ssid,
          preSharedKey: hotspotState.preSharedKey,
          hostIpAddress: hotspotState.hostIpAddress,
        ),
      );
      if (hotspotState.isActive) {
        state = state.copyWith(
          syncMessage: 'Broadcasting presence. Waiting for peers...',
          clearSyncProgress: true,
        );
      }
    });

    _hostClientListSub = _host.streamClientList().listen((clients) {
      final previousCount = state.connectedClients.length;
      final appClients = clients
          .map(
            (c) =>
                AppClientInfo(id: c.id, username: c.username, isHost: c.isHost),
          )
          .toList();
      state = state.copyWith(connectedClients: appClients);
      if (clients.length > previousCount) {
        state = state.copyWith(
          syncMessage: 'Client connected. Initiating 2-way sync...',
          clearSyncProgress: true,
        );
        _sendManifest();
      } else if (clients.isEmpty) {
        state = state.copyWith(
          isSyncing: false,
          syncMessage: 'Broadcasting presence. Waiting for peers...',
          clearSyncProgress: true,
        );
        if (state.isAutoSyncing &&
            previousCount > 0 &&
            !_disposed &&
            !_isSwitchingRoles) {
          _idleTicks = 0;
          _autoSyncTimer?.cancel();
          _runAutoSyncCycle();
        }
      }
    });
    _hostReceivedFilesSub = _host.streamReceivedFilesInfo().listen(
      (files) => _handleReceivedFiles(files, _host),
    );
    _hostSentFilesSub = _host.streamSentFilesInfo().listen(
      (files) => _idleTicks = 0,
    );

    _clientStateSub = _client.streamHotspotState().listen((hotspotState) {
      final wasActive = state.clientState?.isActive ?? false;
      state = state.copyWith(
        clientState: AppClientState(
          isActive: hotspotState.isActive,
          hostSsid: hotspotState.hostSsid,
          hostGatewayIpAddress: hotspotState.hostGatewayIpAddress,
          hostIpAddress: hotspotState.hostIpAddress,
        ),
      );
      if (!wasActive && hotspotState.isActive) {
        state = state.copyWith(
          syncMessage: 'Wi-Fi connected. Connecting to host...',
          clearSyncProgress: true,
        );
      } else if (wasActive && !hotspotState.isActive) {
        state = state.copyWith(
          isSyncing: false,
          syncMessage: 'Disconnected from host.',
          clearSyncProgress: true,
        );
        if (state.isAutoSyncing && !_disposed && !_isSwitchingRoles) {
          _idleTicks = 0;
          _autoSyncTimer?.cancel();
          _runAutoSyncCycle();
        }
      }
    });
    _clientReceivedFilesSub = _client.streamReceivedFilesInfo().listen(
      (files) => _handleReceivedFiles(files, _client),
    );
    _clientSentFilesSub = _client.streamSentFilesInfo().listen(
      (files) => _idleTicks = 0,
    );

    _isInitialized = true;
  }

  Future<void> toggleAutoSync() async {
    if (_isToggling) return;
    _isToggling = true;
    try {
      _autoSyncTimer?.cancel();
      if (state.isAutoSyncing) {
        state = state.copyWith(
          isAutoSyncing: false,
          syncMessage: 'Auto-sync disabled.',
          clearSyncProgress: true,
        );
        _isSwitchingRoles = true;
        try {
          await stopHosting();
          await disconnect();
        } finally {
          _isSwitchingRoles = false;
        }
      } else {
        state = state.copyWith(
          isAutoSyncing: true,
          syncMessage: 'Auto-sync enabled. Starting...',
          clearSyncProgress: true,
        );
        _idleTicks = 0;
        _runAutoSyncCycle();
      }
    } finally {
      _isToggling = false;
    }
  }

  Future<void> _runAutoSyncCycle() async {
    _autoSyncTimer?.cancel();
    if (!state.isAutoSyncing || _disposed) return;

    if (state.isSyncing || state.isConnecting) {
      _idleTicks = 0;
      _autoSyncTimer = Timer(const Duration(seconds: 5), _runAutoSyncCycle);
      return;
    }

    final isHostWithClients =
        state.isHosting && state.connectedClients.isNotEmpty;
    final isClientConnected = state.clientState?.isActive == true;

    // If we are actively connected to someone, we stay in this role but monitor idle time
    if (isHostWithClients || isClientConnected) {
      _idleTicks++;

      // If idle for 30 seconds (6 * 5s) while connected, disconnect to find new peers
      if (_idleTicks >= 6) {
        _idleTicks = 0;
        _isSwitchingRoles = true;
        try {
          if (isClientConnected) {
            await disconnect();
          } else {
            await stopHosting();
          }
        } finally {
          _isSwitchingRoles = false;
        }
      } else {
        _autoSyncTimer = Timer(const Duration(seconds: 5), _runAutoSyncCycle);
        return;
      }
    } else {
      _idleTicks = 0;
    }

    _isSwitchingRoles = true;
    try {
      // Alternate role
      if (_lastRoleWasHost) {
        _lastRoleWasHost = false;
        state = state.copyWith(
          syncMessage: 'Switching to Scanner...',
          clearSyncProgress: true,
        );
        await stopHosting();
        if (!state.isAutoSyncing || _disposed) return;

        // Give OS time to reset network state
        await Future.delayed(const Duration(seconds: 2));

        if (!state.isAutoSyncing || _disposed) return;
        await startScanning();
      } else {
        _lastRoleWasHost = true;
        state = state.copyWith(
          syncMessage: 'Switching to Broadcaster...',
          clearSyncProgress: true,
        );
        await disconnect(); // stops scanning
        if (!state.isAutoSyncing || _disposed) return;

        await Future.delayed(
          const Duration(seconds: 2),
        ); // Give OS time to reset network state
        if (!state.isAutoSyncing || _disposed) return;
        await startHosting();
      }
    } finally {
      _isSwitchingRoles = false;
    }

    if (state.isAutoSyncing && !_disposed) {
      // Read the latest interval from preferences
      final prefs = ref.read(sharedPreferencesProvider);
      final baseInterval = prefs.getInt('settings_sync_interval') ?? 15;

      // Large jitter to prevent perfect sync loops between two devices.
      int nextCycleSeconds = baseInterval + Random().nextInt(20);
      
      if (state.isHosting) {
        // Give the host extra time so clients have a chance to discover and 
        // complete the connection process before the host tears down the group.
        nextCycleSeconds += 15;
      }

      _autoSyncTimer = Timer(
        Duration(seconds: nextCycleSeconds),
        _runAutoSyncCycle,
      );
    }
  }

  Future<void> startHosting() async {
    await _initP2p();
    if (state.isHosting) return;
    await disconnect(); // Ensure client is fully stopped before hosting

    state = state.copyWith(
      isHosting: true,
      syncMessage: 'Initializing broadcaster...',
      clearSyncProgress: true,
    );

    // 1. Platform & Permission Redundancy Checks
    if (!Platform.isAndroid) {
      state = state.copyWith(
        isAutoSyncing: false,
        syncMessage: 'P2P is only supported on Android.',
        clearSyncProgress: true,
      );
      await stopHosting();
      return;
    }

    bool p2pGranted = await _host.checkP2pPermissions();
    bool btGranted = await _host.checkBluetoothPermissions();

    if (!p2pGranted || !btGranted) {
      state = state.copyWith(
        isAutoSyncing: false,
        syncMessage: 'Permissions denied. Cannot start.',
        clearSyncProgress: true,
      );
      await stopHosting();
      return;
    }

    // 2. Hardware Services Redundancy Checks
    bool locEnabled = await _host.checkLocationEnabled();
    bool btEnabled = await _host.checkBluetoothEnabled();

    // 3. Short Polling Loop (Wait up to 3 seconds for OS to reflect state)
    int retries = 3;
    while ((!locEnabled || !btEnabled) && retries > 0) {
      if (_disposed) return;
      state = state.copyWith(
        syncMessage: 'Waiting for services to enable ($retries)...',
        clearSyncProgress: true,
      );
      await Future.delayed(const Duration(seconds: 1));
      locEnabled = await _host.checkLocationEnabled();
      btEnabled = await _host.checkBluetoothEnabled();
      retries--;
    }

    if (!locEnabled || !btEnabled) {
      state = state.copyWith(
        isHosting: false,
        isAutoSyncing: false,
        syncMessage: 'Services disabled. Cannot host.',
        clearSyncProgress: true,
      );
      await stopHosting();
      return;
    }

    await _setBluetoothName('FLD-H');

    try {
      state = state.copyWith(
        syncMessage: 'Starting Hotspot...',
        clearSyncProgress: true,
      );
      try {
        await _host.removeGroup();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (_) {}

      await _host.createGroup(advertise: true);
      if (!state.isHosting || _disposed) {
        await _host.removeGroup();
      } else {
        _hostTextSub?.cancel();
        _hostTextSub = _host.streamReceivedTexts().listen(_handleReceivedText);
      }
    } catch (e) {
      print("Failed to create group: $e");
      state = state.copyWith(
        syncMessage: 'Failed to start host: $e',
        clearSyncProgress: true,
      );
      await stopHosting();
    }
  }

  Future<void> stopHosting() async {
    _hostTextSub?.cancel();
    if (_isInitialized) {
      await _host.removeGroup();
    }
    state = state.copyWith(
      isHosting: false,
      isSyncing: false,
      clearHostState: true,
      connectedClients: [],
      syncMessage: 'Host stopped.',
      clearSyncProgress: true,
    );

    await _restoreBluetoothName();
  }

  Future<void> startScanning() async {
    await _initP2p();
    if (state.isScanning) return;
    await stopHosting(); // Ensure host is fully stopped before scanning

    state = state.copyWith(
      isScanning: true,
      discoveredDevices: [],
      syncMessage: 'Initializing scanner...',
      clearSyncProgress: true,
    );

    // 1. Platform & Permission Redundancy Checks
    if (!Platform.isAndroid) {
      state = state.copyWith(
        isAutoSyncing: false,
        isScanning: false,
        syncMessage: 'P2P is only supported on Android.',
        clearSyncProgress: true,
      );
      await disconnect();
      return;
    }

    bool p2pGranted = await _client.checkP2pPermissions();
    bool btGranted = await _client.checkBluetoothPermissions();

    if (!p2pGranted || !btGranted) {
      state = state.copyWith(
        isAutoSyncing: false,
        isScanning: false,
        syncMessage: 'Permissions denied. Cannot scan.',
        clearSyncProgress: true,
      );
      await disconnect();
      return;
    }

    // 2. Hardware Services Redundancy Checks
    bool locEnabled = await _client.checkLocationEnabled();
    bool wifiEnabled = await _client.checkWifiEnabled();
    bool btEnabled = await _client.checkBluetoothEnabled();

    // 3. Short Polling Loop (Wait up to 3 seconds for OS to reflect state)
    int retries = 3;
    while ((!locEnabled || !wifiEnabled || !btEnabled) && retries > 0) {
      if (_disposed) return;
      state = state.copyWith(
        syncMessage: 'Waiting for services to enable ($retries)...',
        clearSyncProgress: true,
      );
      await Future.delayed(const Duration(seconds: 1));
      locEnabled = await _client.checkLocationEnabled();
      wifiEnabled = await _client.checkWifiEnabled();
      btEnabled = await _client.checkBluetoothEnabled();
      retries--;
    }

    if (!locEnabled || !wifiEnabled || !btEnabled) {
      state = state.copyWith(
        isScanning: false,
        isAutoSyncing: false,
        syncMessage: 'Services disabled. Cannot scan.',
        clearSyncProgress: true,
      );
      await disconnect();
      return;
    }

    await _setBluetoothName('FLD-S');

    try {
      state = state.copyWith(
        syncMessage: 'Looking for nearby devices...',
        clearSyncProgress: true,
      );

      try {
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 5));
      } catch (_) {}

      await FlutterBluePlus.startScan(
        withServices: [Guid(_floodioServiceUuid)],
        timeout: const Duration(seconds: 30),
      );

      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        _rawDiscoveredDevices = results
            .map(
              (r) => BleDiscoveredDevice(
                deviceAddress: r.device.remoteId.str,
                deviceName: r.device.platformName,
              ),
            )
            .toList();

        final appDevices = results
            .map(
              (r) => AppDiscoveredDevice(
                deviceAddress: r.device.remoteId.str,
                deviceName: r.device.platformName,
              ),
            )
            .toList();

        state = state.copyWith(discoveredDevices: appDevices);
        if (state.isAutoSyncing &&
            appDevices.isNotEmpty &&
            state.clientState?.isActive != true &&
            !state.isConnecting) {
          connectToDeviceByAddress(appDevices.first.deviceAddress);
        }
      });

      if (!state.isScanning || _disposed) {
        await stopScanning();
      }
    } catch (e) {
      print("Failed to start scan: $e");
      state = state.copyWith(
        isScanning: false,
        syncMessage: 'Scan failed: $e',
        clearSyncProgress: true,
      );
    }
  }

  Future<void> connectToDeviceByAddress(String address) async {
    if (!_isInitialized || state.isConnecting) return;
    try {
      final device = _rawDiscoveredDevices.firstWhere(
        (d) => d.deviceAddress == address,
      );
      state = state.copyWith(
        isConnecting: true,
        syncMessage: 'Connecting... Please ACCEPT the system Wi-Fi prompt!',
        clearSyncProgress: true,
      );
      await stopScanning();

      // Allow the Android BLE stack a brief moment to settle after stopping the scan
      // before initiating a new GATT connection, preventing dropped connection requests (GATT 133).
      await Future.delayed(const Duration(milliseconds: 2500));

      if (_disposed) {
        state = state.copyWith(isConnecting: false);
        return;
      }

      // Ensure Wi-Fi is enabled before attempting to connect
      bool wifiEnabled = await _client.checkWifiEnabled();
      int wifiRetries = 5;
      while (!wifiEnabled && wifiRetries > 0) {
        state = state.copyWith(
          syncMessage: 'Waiting for Wi-Fi to enable ($wifiRetries)...',
        );
        await Future.delayed(const Duration(seconds: 1));
        wifiEnabled = await _client.checkWifiEnabled();
        wifiRetries--;
      }

      if (!wifiEnabled) {
        throw Exception("Wi-Fi is disabled. Cannot connect to hotspot.");
      }

      // The plugin's connectWithDevice handles BLE read + Wi-Fi connect.
      // It will throw a TimeoutException if the user doesn't accept the prompt within 60s.
      await _client.connectWithDevice(
        device,
        timeout: const Duration(seconds: 25),
      );

      if (!state.isConnecting || _disposed) {
        await _client.disconnect();
        return;
      }

      await _setBluetoothName('FLD-C');

      _clientTextSub?.cancel();
      _clientTextSub = _client.streamReceivedTexts().listen(
        _handleReceivedText,
      );

      state = state.copyWith(isConnecting: false, clearSyncProgress: true);

      // Trigger manifest here!
      state = state.copyWith(
        syncMessage: 'Connected to host. Initiating 2-way sync...',
        clearSyncProgress: true,
      );
      _sendManifest();
    } catch (e) {
      print("Connection failed: $e");
      await _client.disconnect(); // Ensure cleanup
      state = state.copyWith(
        isConnecting: false,
        syncMessage: 'Connection failed: $e',
        clearSyncProgress: true,
      );
      if (state.isAutoSyncing && !_disposed && !_isSwitchingRoles) {
        // If connection failed, don't wait for the full cycle, try switching roles soon
        _autoSyncTimer?.cancel();
        _autoSyncTimer = Timer(const Duration(seconds: 2), _runAutoSyncCycle);
      }
    }
  }

  Future<void> stopScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (_isInitialized) {
      await _client.stopScan();
    }
    state = state.copyWith(isScanning: false);
  }

  Future<void> disconnect() async {
    _clientTextSub?.cancel();
    await stopScanning();
    if (_isInitialized) {
      await _client.disconnect();
    }
    state = state.copyWith(
      clearClientState: true,
      discoveredDevices: [],
      isConnecting: false,
      isSyncing: false,
      syncMessage: 'Disconnected.',
      clearSyncProgress: true,
    );
    await _restoreBluetoothName();
  }

  void _handleReceivedText(String text) async {
    _idleTicks = 0;
    print("Received text: $text");
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        if (json['type'] == 'manifest') {
          await _handleManifest(json);
          return;
        } else if (json['type'] == 'payload') {
          await processPayload(json['data']);
          return;
        } else if (json['type'] == 'request_map') {
          await _handleRequestMap(json);
          return;
        } else if (json['type'] == 'request_image') {
          await _handleRequestImage(json['imageId']);
          return;
        } else if (json['type'] == 'up_to_date') {
          state = state.copyWith(
            isSyncing: false,
            lastSyncTime: DateTime.now(),
            syncMessage: 'Up to date.',
            clearSyncProgress: true,
          );
          return;
        }
      }
    } catch (e) {
      // Not JSON, ignore and treat as normal text
      print("Failed to decode JSON or handle text: $e");
    }

    state = state.copyWith(receivedTexts: [...state.receivedTexts, text]);
  }

  Future<void> _handleRequestImage(String imageId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$imageId');
      if (await file.exists()) {
        await broadcastFile(file);
      }
    } catch (e) {
      print("Error handling request_image: $e");
    }
  }

  void _handleReceivedFiles(
    List<ReceivableFileInfo> files,
    dynamic p2pInstance,
  ) async {
    bool isDownloadingAny = false;
    for (final file in files) {
      if (file.state == ReceivableFileState.idle) {
        isDownloadingAny = true;
        final dir = await getApplicationDocumentsDirectory();

        state = state.copyWith(
          isSyncing: true,
          syncMessage: 'Downloading ${file.info.name}...',
          syncProgress: 0.0,
          clearSyncEstimatedSeconds: true,
        );
        _downloadStartTimes[file.info.id] = DateTime.now();

        p2pInstance.downloadFile(
          file.info.id,
          '${dir.path}/',
          onProgress: (progress) {
            _idleTicks = 0; // Reset idle timer during download

            int? estimatedSeconds;
            final startTime = _downloadStartTimes[file.info.id];
            if (startTime != null && progress.bytesDownloaded > 0) {
              final elapsed = DateTime.now()
                  .difference(startTime)
                  .inMilliseconds;
              if (elapsed > 1000) {
                final bytesPerMs = progress.bytesDownloaded / elapsed;
                final remainingBytes =
                    progress.totalSize - progress.bytesDownloaded;
                estimatedSeconds = (remainingBytes / bytesPerMs / 1000).round();
              }
            }

            if (progress.progressPercent.toInt() % 5 == 0) {
              state = state.copyWith(
                isSyncing: true,
                syncMessage:
                    'Downloading file: ${progress.progressPercent.toStringAsFixed(0)}%',
                syncProgress: progress.progressPercent / 100.0,
                syncEstimatedSeconds: estimatedSeconds,
              );
            }
          },
        );
      } else if (file.state == ReceivableFileState.completed) {
        _downloadStartTimes.remove(file.info.id);
        if (file.info.name.endsWith('.fmap')) {
          final dir = await getApplicationDocumentsDirectory();
          final downloadedFile = File('${dir.path}/${file.info.name}');
          if (await downloadedFile.exists()) {
            state = state.copyWith(
              isSyncing: true,
              syncMessage: 'Unpacking map...',
              clearSyncProgress: true,
            );
            try {
              final mapCache = ref.read(mapCacheServiceProvider);
              await mapCache.unpackMap(downloadedFile);

              if (file.info.name.startsWith('map_')) {
                try {
                  final parts = file.info.name
                      .replaceAll('.fmap', '')
                      .split('_');
                  if (parts.length == 7) {
                    final region = OfflineRegion(
                      bounds: LatLngBounds(
                        LatLng(
                          double.parse(parts[2]),
                          double.parse(parts[4]),
                        ), // south, west
                        LatLng(
                          double.parse(parts[1]),
                          double.parse(parts[3]),
                        ), // north, east
                      ),
                      minZoom: int.parse(parts[5]),
                      maxZoom: int.parse(parts[6]),
                    );
                    ref.read(offlineRegionsProvider.notifier).addRegion(region);
                  }
                } catch (e) {
                  print("Failed to parse region from map filename: $e");
                }
              }

              state = state.copyWith(
                isSyncing: false,
                syncMessage: 'Map updated successfully.',
                clearSyncProgress: true,
              );

              // Trigger a manifest sync so other connected peers know we have a new map
              _sendManifest();
            } catch (e) {
              print("Error unpacking map: $e");
              state = state.copyWith(
                isSyncing: false,
                syncMessage: 'Failed to unpack map.',
                clearSyncProgress: true,
              );
            } finally {
              if (await downloadedFile.exists()) {
                await downloadedFile.delete();
              }
            }
          }
        } else if (file.info.name.startsWith('img_')) {
          // Image downloaded, no special unpacking needed.
        }
      } else if (file.state == ReceivableFileState.downloading) {
        isDownloadingAny = true;
      } else if (file.state == ReceivableFileState.error) {
        print("Failed to download file ${file.info.name}");
      }
    }

    if (isDownloadingAny) {
      // state = state.copyWith(isSyncing: true); // Handled in onProgress
    } else if (!isDownloadingAny &&
        state.isSyncing &&
        state.syncMessage?.startsWith('Downloading') == true) {
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Downloads complete.',
        clearSyncProgress: true,
      );
    }
  }

  Future<void> _sendManifest() async {
    _idleTicks = 0;
    try {
      final (bloomBits, bloomSize) = await Isolate.run(() async {
        final connection = await getSharedConnection();
        final db = AppDatabase(connection);

        final seenIds = await db.select(db.seenMessageIds).get();
        final deletedItems = await db.select(db.deletedItems).get();

        final itemCount = seenIds.length + deletedItems.length;
        final size = max<int>(32768, itemCount * 10);
        final bloomFilter = BloomFilter(size, 5);

        for (final seen in seenIds) {
          bloomFilter.add(seen.messageId);
        }
        for (final d in deletedItems) {
          bloomFilter.add('del_${d.id}_${d.timestamp}');
        }

        final adminTrusted = await db.select(db.adminTrustedSenders).get();
        for (final a in adminTrusted) {
          bloomFilter.add('delg_${a.publicKey}_${a.timestamp}');
        }

        final revoked = await db.select(db.revokedDelegations).get();
        for (final r in revoked) {
          bloomFilter.add('rev_${r.delegateePublicKey}_${r.timestamp}');
        }

        await db.close();
        return (bloomFilter.bits, size);
      });

      final offlineRegions = ref.read(offlineRegionsProvider).value ?? [];

      final manifest = {
        'type': 'manifest',
        'bloomFilter': bloomBits,
        'bloomSize': bloomSize,
        'offlineRegions': offlineRegions.map((r) => r.toJson()).toList(),
      };

      await broadcastText(jsonEncode(manifest));
      state = state.copyWith(
        syncMessage: 'Sync data sent. Waiting for peer...',
        clearSyncProgress: true,
      );

      // Timeout to clear isSyncing if no response (allows time for heavy crypto processing)
      Future.delayed(const Duration(seconds: 60), () {
        if (state.isSyncing &&
            state.syncMessage == 'Sync data sent. Waiting for peer...') {
          state = state.copyWith(
            isSyncing: false,
            syncMessage: 'Sync timeout or up to date.',
            clearSyncProgress: true,
          );
        }
      });
    } catch (e) {
      print("Error sending manifest: $e");
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Error sending sync data.',
        clearSyncProgress: true,
      );
    }
  }

  Future<void> _handleManifest(Map<String, dynamic> json) async {
    _idleTicks = 0;
    state = state.copyWith(
      isSyncing: true,
      syncMessage: 'Comparing data...',
      clearSyncProgress: true,
    );
    try {
      final peerRegionsJson = json['offlineRegions'] as List<dynamic>? ?? [];
      final peerRegions = peerRegionsJson
          .map((e) => OfflineRegion.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      state = state.copyWith(peerOfflineRegions: peerRegions);

      final bloomSize = json['bloomSize'] as int? ?? 32768;
      final bloomBits =
          (json['bloomFilter'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [];

      final filterResult = await Isolate.run(() async {
        final peerBloomFilter = BloomFilter.fromList(bloomBits, bloomSize, 5);

        final connection = await getSharedConnection();
        final db = AppDatabase(connection);

        final allHazards = await db.select(db.hazardMarkers).get();
        final allNews = await db.select(db.newsItems).get();
        final allProfiles = await db.select(db.userProfiles).get();
        final allDeleted = await db.select(db.deletedItems).get();
        final allAreas = await db.select(db.areas).get();
        final allPaths = await db.select(db.paths).get();
        final allAdminTrusted = await db.select(db.adminTrustedSenders).get();
        final allRevoked = await db.select(db.revokedDelegations).get();

        final newHazards = allHazards
            .where(
              (h) => !peerBloomFilter.mightContain('${h.id}_${h.timestamp}'),
            )
            .take(200)
            .toList();
        final newNews = allNews
            .where(
              (n) => !peerBloomFilter.mightContain('${n.id}_${n.timestamp}'),
            )
            .take(200)
            .toList();
        final newProfiles = allProfiles
            .where(
              (p) => !peerBloomFilter.mightContain(
                '${p.publicKey}_${p.timestamp}',
              ),
            )
            .take(200)
            .toList();
        final newDeleted = allDeleted
            .where(
              (d) =>
                  !peerBloomFilter.mightContain('del_${d.id}_${d.timestamp}'),
            )
            .take(200)
            .toList();
        final newAreas = allAreas
            .where(
              (a) => !peerBloomFilter.mightContain('${a.id}_${a.timestamp}'),
            )
            .take(200)
            .toList();
        final newPaths = allPaths
            .where(
              (p) => !peerBloomFilter.mightContain('${p.id}_${p.timestamp}'),
            )
            .take(200)
            .toList();
        final newDelegations = allAdminTrusted
            .where(
              (a) => !peerBloomFilter.mightContain(
                'delg_${a.publicKey}_${a.timestamp}',
              ),
            )
            .take(200)
            .toList();
        final newRevocations = allRevoked
            .where(
              (r) => !peerBloomFilter.mightContain(
                'rev_${r.delegateePublicKey}_${r.timestamp}',
              ),
            )
            .take(200)
            .toList();

        await db.close();

        return (
          newHazards,
          newNews,
          newProfiles,
          newDeleted,
          newAreas,
          newPaths,
          newDelegations,
          newRevocations,
        );
      });

      final newHazards = filterResult.$1;
      final newNews = filterResult.$2;
      final newProfiles = filterResult.$3;
      final newDeleted = filterResult.$4;
      final newAreas = filterResult.$5;
      final newPaths = filterResult.$6;
      final newDelegations = filterResult.$7;
      final newRevocations = filterResult.$8;

      if (newHazards.isEmpty &&
          newNews.isEmpty &&
          newProfiles.isEmpty &&
          newDeleted.isEmpty &&
          newAreas.isEmpty &&
          newPaths.isEmpty &&
          newDelegations.isEmpty &&
          newRevocations.isEmpty) {
        await broadcastText(jsonEncode({'type': 'up_to_date'}));
        state = state.copyWith(
          isSyncing: false,
          lastSyncTime: DateTime.now(),
          syncMessage: 'Up to date.',
          clearSyncProgress: true,
        );
        return;
      }

      state = state.copyWith(
        syncMessage:
            'Sending ${newHazards.length} markers, ${newNews.length} news, ${newProfiles.length} profiles, ${newAreas.length} areas, ${newPaths.length} paths, ${newDeleted.length} deletions, ${newDelegations.length} delegations, ${newRevocations.length} revocations...',
        clearSyncProgress: true,
      );

      final payload = pb.SyncPayload();

      for (final h in newHazards) {
        payload.markers.add(
          pb.HazardMarker(
            id: h.id,
            latitude: h.latitude,
            longitude: h.longitude,
            type: h.type,
            description: h.description,
            timestamp: Int64(h.timestamp),
            senderId: h.senderId,
            signature: h.signature ?? '',
            trustTier: h.trustTier,
            imageId: h.imageId ?? '',
            expiresAt: Int64(h.expiresAt ?? 0),
            isCritical: h.isCritical,
          ),
        );
      }

      for (final n in newNews) {
        payload.news.add(
          pb.NewsItem(
            id: n.id,
            title: n.title,
            content: n.content,
            timestamp: Int64(n.timestamp),
            senderId: n.senderId,
            signature: n.signature ?? '',
            trustTier: n.trustTier,
            expiresAt: Int64(n.expiresAt ?? 0),
            imageId: n.imageId ?? '',
            isCritical: n.isCritical,
          ),
        );
      }

      for (final p in newProfiles) {
        payload.profiles.add(
          pb.UserProfile(
            publicKey: p.publicKey,
            name: p.name,
            contactInfo: p.contactInfo,
            timestamp: Int64(p.timestamp),
            signature: p.signature,
          ),
        );
      }

      for (final d in newDeleted) {
        payload.deletedItems.add(
          pb.DeletedItem(id: d.id, timestamp: Int64(d.timestamp)),
        );
      }

      for (final a in newAreas) {
        final areaMarker = pb.AreaMarker(
          id: a.id,
          type: a.type,
          description: a.description,
          timestamp: Int64(a.timestamp),
          senderId: a.senderId,
          signature: a.signature ?? '',
          trustTier: a.trustTier,
          expiresAt: Int64(a.expiresAt ?? 0),
          isCritical: a.isCritical,
        );
        for (final coord in a.coordinates) {
          areaMarker.coordinates.add(
            pb.Coordinate(latitude: coord['lat']!, longitude: coord['lng']!),
          );
        }
        payload.areas.add(areaMarker);
      }

      for (final p in newPaths) {
        final pathMarker = pb.PathMarker(
          id: p.id,
          type: p.type,
          description: p.description,
          timestamp: Int64(p.timestamp),
          senderId: p.senderId,
          signature: p.signature ?? '',
          trustTier: p.trustTier,
          expiresAt: Int64(p.expiresAt ?? 0),
          isCritical: p.isCritical,
        );
        for (final coord in p.coordinates) {
          pathMarker.coordinates.add(
            pb.Coordinate(latitude: coord['lat']!, longitude: coord['lng']!),
          );
        }
        payload.paths.add(pathMarker);
      }

      for (final d in newDelegations) {
        payload.delegations.add(
          pb.TrustDelegation(
            id: 'delg_${d.publicKey}',
            delegatorPublicKey: d.delegatorPublicKey,
            delegateePublicKey: d.publicKey,
            timestamp: Int64(d.timestamp),
            signature: d.signature,
          ),
        );
      }

      for (final r in newRevocations) {
        payload.revokedDelegations.add(
          pb.RevokedDelegation(
            delegateePublicKey: r.delegateePublicKey,
            delegatorPublicKey: r.delegatorPublicKey,
            timestamp: Int64(r.timestamp),
            signature: r.signature,
          ),
        );
      }

      final encoded = base64Encode(payload.writeToBuffer());
      await broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));
      state = state.copyWith(
        syncMessage: 'Data sent successfully.',
        clearSyncProgress: true,
      );
    } catch (e) {
      print("Error handling manifest: $e");
      state = state.copyWith(
        syncMessage: 'Error sending data.',
        clearSyncProgress: true,
      );
    } finally {
      state = state.copyWith(isSyncing: false, clearSyncProgress: true);
    }
  }

  Future<void> _handleRequestMap(Map<String, dynamic> json) async {
    OfflineRegion? region;
    if (json['region'] != null) {
      region = OfflineRegion.fromJson(
        Map<String, dynamic>.from(json['region']),
      );
    }
    await broadcastMapRegion(region);
  }

  Future<void> broadcastMapRegion(OfflineRegion? region) async {
    state = state.copyWith(
      isSyncing: true,
      syncMessage: 'Packing offline map for transfer...',
      clearSyncProgress: true,
    );
    try {
      final mapCache = ref.read(mapCacheServiceProvider);
      final packFile = await mapCache.packMap(region: region);

      if (state.isHosting) {
        await _host.broadcastFile(packFile);
      } else {
        await _client.broadcastFile(packFile);
      }
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Map file sent.',
        clearSyncProgress: true,
      );
    } catch (e) {
      print("Error sending map: $e");
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Error sending map.',
        clearSyncProgress: true,
      );
    }
  }

  Future<void> processPayload(String base64Data) async {
    _idleTicks = 0;
    state = state.copyWith(
      isSyncing: true,
      syncMessage: 'Receiving data...',
      clearSyncProgress: true,
    );
    try {
      final data = base64Decode(base64Data);
      final payload = pb.SyncPayload.fromBuffer(data);

      if (payload.markers.isEmpty &&
          payload.news.isEmpty &&
          payload.profiles.isEmpty &&
          payload.deletedItems.isEmpty &&
          payload.areas.isEmpty &&
          payload.paths.isEmpty &&
          payload.delegations.isEmpty &&
          payload.revokedDelegations.isEmpty) {
        state = state.copyWith(
          syncMessage: 'Empty payload received.',
          clearSyncProgress: true,
        );
        return;
      }

      state = state.copyWith(
        syncMessage: 'Verifying signatures...',
        clearSyncProgress: true,
      );

      final db = ref.read(databaseProvider);
      await ref.read(
        cryptoServiceProvider.future,
      ); // Ensure crypto is initialized
      final crypto = ref.read(cryptoServiceProvider.notifier);

      final trustedSenders = await db.select(db.trustedSenders).get();
      final trustedKeys = trustedSenders.map((e) => e.publicKey).toList();

      final untrustedSenders = await db.select(db.untrustedSenders).get();
      final untrustedKeys = untrustedSenders.map((e) => e.publicKey).toList();

      final adminTrustedSenders = await db.select(db.adminTrustedSenders).get();
      final adminTrustedKeys = adminTrustedSenders
          .map((e) => e.publicKey)
          .toList();
      final delegationTimestamps = {
        for (var d in adminTrustedSenders) d.publicKey: d.timestamp,
      };

      final deletedItems = await db.select(db.deletedItems).get();
      final deletedIds = deletedItems.map((e) => e.id).toSet();

      final allRevocations = await db.select(db.revokedDelegations).get();
      final revocationTimestamps = {
        for (var r in allRevocations) r.delegateePublicKey: r.timestamp,
      };
      final revokedKeys = allRevocations
          .map((e) => e.delegateePublicKey)
          .toList();

      // Fetch existing timestamps for LWW CRDT resolution (optimized with isIn)
      final payloadMarkerIds = payload.markers.map((m) => m.id).toList();
      final existingMarkers = payloadMarkerIds.isEmpty
          ? []
          : await (db.select(
              db.hazardMarkers,
            )..where((t) => t.id.isIn(payloadMarkerIds))).get();
      final markerTimestamps = {
        for (var m in existingMarkers) m.id: m.timestamp,
      };

      final payloadNewsIds = payload.news.map((n) => n.id).toList();
      final existingNews = payloadNewsIds.isEmpty
          ? []
          : await (db.select(
              db.newsItems,
            )..where((t) => t.id.isIn(payloadNewsIds))).get();
      final newsTimestamps = {for (var n in existingNews) n.id: n.timestamp};

      final payloadProfileKeys = payload.profiles
          .map((p) => p.publicKey)
          .toList();
      final existingProfiles = payloadProfileKeys.isEmpty
          ? []
          : await (db.select(
              db.userProfiles,
            )..where((t) => t.publicKey.isIn(payloadProfileKeys))).get();
      final profileTimestamps = {
        for (var p in existingProfiles) p.publicKey: p.timestamp,
      };

      final payloadAreaIds = payload.areas.map((a) => a.id).toList();
      final existingAreas = payloadAreaIds.isEmpty
          ? []
          : await (db.select(
              db.areas,
            )..where((t) => t.id.isIn(payloadAreaIds))).get();
      final areaTimestamps = {for (var a in existingAreas) a.id: a.timestamp};

      final payloadPathIds = payload.paths.map((p) => p.id).toList();
      final existingPaths = payloadPathIds.isEmpty
          ? []
          : await (db.select(
              db.paths,
            )..where((t) => t.id.isIn(payloadPathIds))).get();
      final pathTimestamps = {for (var p in existingPaths) p.id: p.timestamp};

      final existingDeleted = await db.select(db.deletedItems).get();
      final existingDeletedIds = existingDeleted.map((e) => e.id).toSet();
      final validDeleted = <DeletedItemsCompanion>[];

      final seenIds = <SeenMessageIdsCompanion>[];

      for (final d in payload.deletedItems) {
        deletedIds.add(d.id);
        if (!existingDeletedIds.contains(d.id)) {
          validDeleted.add(
            DeletedItemsCompanion.insert(
              id: d.id,
              timestamp: d.timestamp.toInt(),
            ),
          );
          seenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: 'del_${d.id}_${d.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
      }

      // Track progress to update the UI during heavy cryptography
      int totalCryptoItems =
          payload.delegations.length +
          payload.revokedDelegations.length +
          payload.markers.length +
          payload.news.length +
          payload.profiles.length +
          payload.areas.length +
          payload.paths.length;
      int processedCryptoItems = 0;

      void updateCryptoProgress(String type) {
        processedCryptoItems++;
        if (processedCryptoItems % 5 == 0 ||
            processedCryptoItems == totalCryptoItems) {
          state = state.copyWith(
            syncMessage:
                'Verifying $type ($processedCryptoItems/$totalCryptoItems)...',
            syncProgress: totalCryptoItems > 0
                ? processedCryptoItems / totalCryptoItems
                : 0.0,
          );
        }
      }

      final validDelegations = <AdminTrustedSendersCompanion>[];
      for (final d in payload.delegations) {
        await Future.delayed(
          const Duration(milliseconds: 2),
        ); // Throttle to allow Android UI to render
        final existingTs = delegationTimestamps[d.delegateePublicKey] ?? 0;
        if (d.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final isValid = await crypto.verifyDelegation(
          delegateePublicKeyStr: d.delegateePublicKey,
          timestamp: d.timestamp.toInt(),
          signatureStr: d.signature,
          delegatorPublicKeyStr: d.delegatorPublicKey,
        );
        if (isValid) {
          validDelegations.add(
            AdminTrustedSendersCompanion.insert(
              publicKey: d.delegateePublicKey,
              delegatorPublicKey: d.delegatorPublicKey,
              timestamp: d.timestamp.toInt(),
              signature: d.signature,
            ),
          );
          adminTrustedKeys.add(d.delegateePublicKey);
          seenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: 'delg_${d.delegateePublicKey}_${d.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        } else {
          print("Invalid signature for delegation ${d.id}, dropping.");
        }
        updateCryptoProgress('delegations');
      }

      final validRevocations = <RevokedDelegationsCompanion>[];
      for (final r in payload.revokedDelegations) {
        await Future.delayed(const Duration(milliseconds: 2));
        final existingTs = revocationTimestamps[r.delegateePublicKey] ?? 0;
        if (r.timestamp.toInt() <= existingTs) continue;

        final isValid = await crypto.verifyRevocation(
          delegateePublicKeyStr: r.delegateePublicKey,
          timestamp: r.timestamp.toInt(),
          signatureStr: r.signature,
          delegatorPublicKeyStr: r.delegatorPublicKey,
        );
        if (isValid) {
          validRevocations.add(
            RevokedDelegationsCompanion.insert(
              delegateePublicKey: r.delegateePublicKey,
              delegatorPublicKey: r.delegatorPublicKey,
              timestamp: r.timestamp.toInt(),
              signature: r.signature,
            ),
          );
          seenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: 'rev_${r.delegateePublicKey}_${r.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        } else {
          print(
            "Invalid signature for revocation ${r.delegateePublicKey}, dropping.",
          );
        }
        updateCryptoProgress('revocations');
      }

      for (final r in validRevocations) {
        revokedKeys.add(r.delegateePublicKey.value);
      }

      final validMarkers = <HazardMarkersCompanion>[];
      for (final m in payload.markers) {
        await Future.delayed(const Duration(milliseconds: 2));
        if (deletedIds.contains(m.id)) continue;
        final existingTs = markerTimestamps[m.id] ?? 0;
        if (m.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final imageIdStr = m.imageId.isEmpty ? "" : m.imageId;
        final expiresAtStr = m.expiresAt == 0 ? "" : m.expiresAt.toString();
        final isCriticalStr = m.isCritical ? "1" : "0";
        final payloadToSign = utf8.encode(
          '${m.id}${m.latitude}${m.longitude}${m.type}${m.description}${m.timestamp}$imageIdStr$expiresAtStr$isCriticalStr',
        );
        final trustTier = await crypto.verifyAndGetTrustTier(
          data: payloadToSign,
          signatureStr: m.signature,
          senderPublicKeyStr: m.senderId,
          trustedPublicKeys: trustedKeys,
          adminTrustedPublicKeys: adminTrustedKeys,
          untrustedPublicKeys: untrustedKeys,
          revokedPublicKeys: revokedKeys,
        );

        if (trustTier != 5) {
          validMarkers.add(
            HazardMarkersCompanion.insert(
              id: m.id,
              latitude: m.latitude,
              longitude: m.longitude,
              type: m.type,
              description: m.description,
              timestamp: m.timestamp.toInt(),
              senderId: m.senderId,
              signature: Value(m.signature),
              trustTier: trustTier,
              imageId: Value(m.imageId.isEmpty ? null : m.imageId),
              expiresAt: Value(m.expiresAt == 0 ? null : m.expiresAt.toInt()),
              isCritical: Value(m.isCritical),
            ),
          );
          seenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${m.id}_${m.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        } else {
          print("Invalid signature for marker ${m.id}, dropping.");
        }
        updateCryptoProgress('markers');
      }

      final validNews = <NewsItemsCompanion>[];
      for (final n in payload.news) {
        await Future.delayed(const Duration(milliseconds: 2));
        if (deletedIds.contains(n.id)) continue;
        final existingTs = newsTimestamps[n.id] ?? 0;
        if (n.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final imageIdStr = n.imageId.isEmpty ? "" : n.imageId;
        final expiresAtStr = n.expiresAt == 0 ? "" : n.expiresAt.toString();
        final isCriticalStr = n.isCritical ? "1" : "0";
        final payloadToSign = utf8.encode(
          '${n.id}${n.title}${n.content}${n.timestamp}$imageIdStr$expiresAtStr$isCriticalStr',
        );
        final trustTier = await crypto.verifyAndGetTrustTier(
          data: payloadToSign,
          signatureStr: n.signature,
          senderPublicKeyStr: n.senderId,
          trustedPublicKeys: trustedKeys,
          adminTrustedPublicKeys: adminTrustedKeys,
          untrustedPublicKeys: untrustedKeys,
          revokedPublicKeys: revokedKeys,
        );

        if (trustTier != 5) {
          validNews.add(
            NewsItemsCompanion.insert(
              id: n.id,
              title: n.title,
              content: n.content,
              timestamp: n.timestamp.toInt(),
              senderId: n.senderId,
              signature: Value(n.signature),
              trustTier: trustTier,
              expiresAt: Value(n.expiresAt == 0 ? null : n.expiresAt.toInt()),
              imageId: Value(n.imageId.isEmpty ? null : n.imageId),
              isCritical: Value(n.isCritical),
            ),
          );
          seenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${n.id}_${n.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        } else {
          print("Invalid signature for news ${n.id}, dropping.");
        }
        updateCryptoProgress('news');
      }

      final validProfiles = <UserProfilesCompanion>[];
      for (final p in payload.profiles) {
        await Future.delayed(const Duration(milliseconds: 2));
        final existingTs = profileTimestamps[p.publicKey] ?? 0;
        if (p.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final payloadToSign = utf8.encode(
          '${p.publicKey}${p.name}${p.contactInfo}${p.timestamp}',
        );
        final trustTier = await crypto.verifyAndGetTrustTier(
          data: payloadToSign,
          signatureStr: p.signature,
          senderPublicKeyStr: p.publicKey,
          trustedPublicKeys: trustedKeys,
          adminTrustedPublicKeys: adminTrustedKeys,
          untrustedPublicKeys: untrustedKeys,
          revokedPublicKeys: revokedKeys,
        );

        if (trustTier != 5) {
          validProfiles.add(
            UserProfilesCompanion.insert(
              publicKey: p.publicKey,
              name: p.name,
              contactInfo: p.contactInfo,
              timestamp: p.timestamp.toInt(),
              signature: p.signature,
            ),
          );
          seenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${p.publicKey}_${p.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        } else {
          print("Invalid signature for profile ${p.publicKey}, dropping.");
        }
        updateCryptoProgress('profiles');
      }

      final validAreas = <AreasCompanion>[];
      for (final a in payload.areas) {
        await Future.delayed(const Duration(milliseconds: 2));
        if (deletedIds.contains(a.id)) continue;
        final existingTs = areaTimestamps[a.id] ?? 0;
        if (a.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final expiresAtStr = a.expiresAt == 0 ? "" : a.expiresAt.toString();
        final isCriticalStr = a.isCritical ? "1" : "0";
        final coordsStr = a.coordinates
            .map((c) => '${c.latitude},${c.longitude}')
            .join('|');
        final payloadToSign = utf8.encode(
          '${a.id}$coordsStr${a.type}${a.description}${a.timestamp}$expiresAtStr$isCriticalStr',
        );
        final trustTier = await crypto.verifyAndGetTrustTier(
          data: payloadToSign,
          signatureStr: a.signature,
          senderPublicKeyStr: a.senderId,
          trustedPublicKeys: trustedKeys,
          adminTrustedPublicKeys: adminTrustedKeys,
          untrustedPublicKeys: untrustedKeys,
          revokedPublicKeys: revokedKeys,
        );

        if (trustTier != 5) {
          final coords = a.coordinates
              .map((c) => {'lat': c.latitude, 'lng': c.longitude})
              .toList();
          validAreas.add(
            AreasCompanion.insert(
              id: a.id,
              coordinates: coords,
              type: a.type,
              description: a.description,
              timestamp: a.timestamp.toInt(),
              senderId: a.senderId,
              signature: Value(a.signature),
              trustTier: trustTier,
              expiresAt: Value(a.expiresAt == 0 ? null : a.expiresAt.toInt()),
              isCritical: Value(a.isCritical),
            ),
          );
          seenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${a.id}_${a.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        } else {
          print("Invalid signature for area ${a.id}, dropping.");
        }
        updateCryptoProgress('areas');
      }

      final validPaths = <PathsCompanion>[];
      for (final p in payload.paths) {
        await Future.delayed(const Duration(milliseconds: 2));
        if (deletedIds.contains(p.id)) continue;
        final existingTs = pathTimestamps[p.id] ?? 0;
        if (p.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final expiresAtStr = p.expiresAt == 0 ? "" : p.expiresAt.toString();
        final isCriticalStr = p.isCritical ? "1" : "0";
        final coordsStr = p.coordinates
            .map((c) => '${c.latitude},${c.longitude}')
            .join('|');
        final payloadToSign = utf8.encode(
          '${p.id}$coordsStr${p.type}${p.description}${p.timestamp}$expiresAtStr$isCriticalStr',
        );
        final trustTier = await crypto.verifyAndGetTrustTier(
          data: payloadToSign,
          signatureStr: p.signature,
          senderPublicKeyStr: p.senderId,
          trustedPublicKeys: trustedKeys,
          adminTrustedPublicKeys: adminTrustedKeys,
          untrustedPublicKeys: untrustedKeys,
          revokedPublicKeys: revokedKeys,
        );

        if (trustTier != 5) {
          final coords = p.coordinates
              .map((c) => {'lat': c.latitude, 'lng': c.longitude})
              .toList();
          validPaths.add(
            PathsCompanion.insert(
              id: p.id,
              coordinates: coords,
              type: p.type,
              description: p.description,
              timestamp: p.timestamp.toInt(),
              senderId: p.senderId,
              signature: Value(p.signature),
              trustTier: trustTier,
              expiresAt: Value(p.expiresAt == 0 ? null : p.expiresAt.toInt()),
              isCritical: Value(p.isCritical),
            ),
          );
          seenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${p.id}_${p.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        } else {
          print("Invalid signature for path ${p.id}, dropping.");
        }
        updateCryptoProgress('paths');
      }

      state = state.copyWith(
        syncMessage: 'Saving to database...',
        clearSyncProgress: true,
      );

      await db.batch((batch) {
        batch.insertAll(
          db.hazardMarkers,
          validMarkers,
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          db.newsItems,
          validNews,
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          db.userProfiles,
          validProfiles,
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(db.areas, validAreas, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.paths, validPaths, mode: InsertMode.insertOrReplace);
        batch.insertAll(
          db.seenMessageIds,
          seenIds,
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          db.deletedItems,
          validDeleted,
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          db.adminTrustedSenders,
          validDelegations,
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          db.revokedDelegations,
          validRevocations,
          mode: InsertMode.insertOrReplace,
        );
      });

      final dir = await getApplicationDocumentsDirectory();
      await db.transaction(() async {
        for (final d in validDeleted) {
          final marker = await (db.select(
            db.hazardMarkers,
          )..where((t) => t.id.equals(d.id.value))).getSingleOrNull();
          if (marker?.imageId != null && marker!.imageId!.isNotEmpty) {
            final file = File('${dir.path}/${marker.imageId}');
            if (await file.exists()) await file.delete();
          }

          final news = await (db.select(
            db.newsItems,
          )..where((t) => t.id.equals(d.id.value))).getSingleOrNull();
          if (news?.imageId != null && news!.imageId!.isNotEmpty) {
            final file = File('${dir.path}/${news.imageId}');
            if (await file.exists()) await file.delete();
          }

          await (db.delete(
            db.hazardMarkers,
          )..where((t) => t.id.equals(d.id.value))).go();
          await (db.delete(
            db.newsItems,
          )..where((t) => t.id.equals(d.id.value))).go();
          await (db.delete(
            db.areas,
          )..where((t) => t.id.equals(d.id.value))).go();
          await (db.delete(
            db.paths,
          )..where((t) => t.id.equals(d.id.value))).go();
        }
        for (final d in validDelegations) {
          if (revokedKeys.contains(d.publicKey.value)) continue;
          await (db.update(db.hazardMarkers)..where(
                (t) =>
                    t.senderId.equals(d.publicKey.value) &
                    t.trustTier.isBiggerThanValue(2),
              ))
              .write(const HazardMarkersCompanion(trustTier: Value(2)));
          await (db.update(db.newsItems)..where(
                (t) =>
                    t.senderId.equals(d.publicKey.value) &
                    t.trustTier.isBiggerThanValue(2),
              ))
              .write(const NewsItemsCompanion(trustTier: Value(2)));
          await (db.update(db.areas)..where(
                (t) =>
                    t.senderId.equals(d.publicKey.value) &
                    t.trustTier.isBiggerThanValue(2),
              ))
              .write(const AreasCompanion(trustTier: Value(2)));
          await (db.update(db.paths)..where(
                (t) =>
                    t.senderId.equals(d.publicKey.value) &
                    t.trustTier.isBiggerThanValue(2),
              ))
              .write(const PathsCompanion(trustTier: Value(2)));
        }
        for (final r in validRevocations) {
          final fallbackTier = trustedKeys.contains(r.delegateePublicKey.value)
              ? 3
              : 4;
          await (db.update(db.hazardMarkers)..where(
                (t) =>
                    t.senderId.equals(r.delegateePublicKey.value) &
                    t.trustTier.equals(2),
              ))
              .write(HazardMarkersCompanion(trustTier: Value(fallbackTier)));
          await (db.update(db.newsItems)..where(
                (t) =>
                    t.senderId.equals(r.delegateePublicKey.value) &
                    t.trustTier.equals(2),
              ))
              .write(NewsItemsCompanion(trustTier: Value(fallbackTier)));
          await (db.update(db.areas)..where(
                (t) =>
                    t.senderId.equals(r.delegateePublicKey.value) &
                    t.trustTier.equals(2),
              ))
              .write(AreasCompanion(trustTier: Value(fallbackTier)));
          await (db.update(db.paths)..where(
                (t) =>
                    t.senderId.equals(r.delegateePublicKey.value) &
                    t.trustTier.equals(2),
              ))
              .write(PathsCompanion(trustTier: Value(fallbackTier)));
        }
      });

      // Request missing images
      for (final m in validMarkers) {
        final imageId = m.imageId.value;
        if (imageId != null && imageId.isNotEmpty) {
          final file = File('${dir.path}/$imageId');
          if (!await file.exists()) {
            bool downloaded = false;
            try {
              final bytes = await Supabase.instance.client.storage
                  .from('images')
                  .download(imageId);
              await file.writeAsBytes(bytes);
              downloaded = true;
            } catch (_) {}

            if (!downloaded) {
              await broadcastText(
                jsonEncode({'type': 'request_image', 'imageId': imageId}),
              );
            }
          }
        }
      }
      for (final n in validNews) {
        final imageId = n.imageId.value;
        if (imageId != null && imageId.isNotEmpty) {
          final file = File('${dir.path}/$imageId');
          if (!await file.exists()) {
            bool downloaded = false;
            try {
              final bytes = await Supabase.instance.client.storage
                  .from('images')
                  .download(imageId);
              await file.writeAsBytes(bytes);
              downloaded = true;
            } catch (_) {}

            if (!downloaded) {
              await broadcastText(
                jsonEncode({'type': 'request_image', 'imageId': imageId}),
              );
            }
          }
        }
      }

      // Forward newly received and validated data to other connected peers
      final forwardPayload = pb.SyncPayload();
      bool hasNewData = false;

      for (final m in validMarkers) {
        hasNewData = true;
        forwardPayload.markers.add(
          pb.HazardMarker(
            id: m.id.value,
            latitude: m.latitude.value,
            longitude: m.longitude.value,
            type: m.type.value,
            description: m.description.value,
            timestamp: Int64(m.timestamp.value),
            senderId: m.senderId.value,
            signature: m.signature.value ?? '',
            trustTier: m.trustTier.value,
            imageId: m.imageId.value ?? '',
            expiresAt: Int64(m.expiresAt.value ?? 0),
            isCritical: m.isCritical.value,
          ),
        );
      }

      for (final n in validNews) {
        hasNewData = true;
        forwardPayload.news.add(
          pb.NewsItem(
            id: n.id.value,
            title: n.title.value,
            content: n.content.value,
            timestamp: Int64(n.timestamp.value),
            senderId: n.senderId.value,
            signature: n.signature.value ?? '',
            trustTier: n.trustTier.value,
            expiresAt: Int64(n.expiresAt.value ?? 0),
            imageId: n.imageId.value ?? '',
            isCritical: n.isCritical.value,
          ),
        );
      }

      for (final p in validProfiles) {
        hasNewData = true;
        forwardPayload.profiles.add(
          pb.UserProfile(
            publicKey: p.publicKey.value,
            name: p.name.value,
            contactInfo: p.contactInfo.value,
            timestamp: Int64(p.timestamp.value),
            signature: p.signature.value,
          ),
        );
      }

      for (final a in validAreas) {
        hasNewData = true;
        final areaMarker = pb.AreaMarker(
          id: a.id.value,
          type: a.type.value,
          description: a.description.value,
          timestamp: Int64(a.timestamp.value),
          senderId: a.senderId.value,
          signature: a.signature.value ?? '',
          trustTier: a.trustTier.value,
          expiresAt: Int64(a.expiresAt.value ?? 0),
          isCritical: a.isCritical.value,
        );
        for (final coord in a.coordinates.value) {
          areaMarker.coordinates.add(
            pb.Coordinate(latitude: coord['lat']!, longitude: coord['lng']!),
          );
        }
        forwardPayload.areas.add(areaMarker);
      }

      for (final p in validPaths) {
        hasNewData = true;
        final pathMarker = pb.PathMarker(
          id: p.id.value,
          type: p.type.value,
          description: p.description.value,
          timestamp: Int64(p.timestamp.value),
          senderId: p.senderId.value,
          signature: p.signature.value ?? '',
          trustTier: p.trustTier.value,
          expiresAt: Int64(p.expiresAt.value ?? 0),
          isCritical: p.isCritical.value,
        );
        for (final coord in p.coordinates.value) {
          pathMarker.coordinates.add(
            pb.Coordinate(latitude: coord['lat']!, longitude: coord['lng']!),
          );
        }
        forwardPayload.paths.add(pathMarker);
      }

      for (final d in validDeleted) {
        hasNewData = true;
        forwardPayload.deletedItems.add(
          pb.DeletedItem(id: d.id.value, timestamp: Int64(d.timestamp.value)),
        );
      }

      for (final d in validDelegations) {
        hasNewData = true;
        forwardPayload.delegations.add(
          pb.TrustDelegation(
            id: 'delg_${d.publicKey.value}',
            delegatorPublicKey: d.delegatorPublicKey.value,
            delegateePublicKey: d.publicKey.value,
            timestamp: Int64(d.timestamp.value),
            signature: d.signature.value,
          ),
        );
      }

      for (final r in validRevocations) {
        hasNewData = true;
        forwardPayload.revokedDelegations.add(
          pb.RevokedDelegation(
            delegateePublicKey: r.delegateePublicKey.value,
            delegatorPublicKey: r.delegatorPublicKey.value,
            timestamp: Int64(r.timestamp.value),
            signature: r.signature.value,
          ),
        );
      }

      if (hasNewData) {
        // Prevent Echo Storm: Only forward the payload if we are a Host with MULTIPLE clients.
        // If we are a Client, or a Host with only 1 client, the sender already has this data.
        if (state.isHosting && state.connectedClients.length > 1) {
          final encoded = base64Encode(forwardPayload.writeToBuffer());
          await broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));
        } else {
          await broadcastText(jsonEncode({'type': 'up_to_date'}));
        }
      } else {
        await broadcastText(jsonEncode({'type': 'up_to_date'}));
      }

      state = state.copyWith(
        isSyncing: false,
        lastSyncTime: DateTime.now(),
        syncMessage: 'Successfully synced data.',
        clearSyncProgress: true,
      );
      print(
        "Successfully synced ${payload.markers.length} markers, ${payload.news.length} news, ${payload.profiles.length} profiles, ${payload.areas.length} areas, ${payload.paths.length} paths, ${payload.deletedItems.length} deletions, ${payload.delegations.length} delegations, ${payload.revokedDelegations.length} revocations.",
      );
    } catch (e) {
      print("Error handling payload: $e");
      state = state.copyWith(
        syncMessage: 'Error syncing data.',
        clearSyncProgress: true,
      );
    } finally {
      state = state.copyWith(isSyncing: false, clearSyncProgress: true);
    }
  }

  Future<void> triggerSync() async {
    await _sendManifest();
  }

  Future<void> requestMapRegion(OfflineRegion region) async {
    await broadcastText(
      jsonEncode({'type': 'request_map', 'region': region.toJson()}),
    );
  }

  Future<void> broadcastText(String text) async {
    try {
      _idleTicks = 0;
      if (_isInitialized) {
        if (state.isHosting) {
          await _host.broadcastText(text);
        } else {
          await _client.broadcastText(text);
        }
      }
    } catch (e) {
      print("Error broadcasting text: $e");
    }
  }

  Future<void> broadcastFile(File file) async {
    try {
      _idleTicks = 0;
      if (_isInitialized) {
        if (state.isHosting) {
          await _host.broadcastFile(file);
        } else {
          await _client.broadcastFile(file);
        }
      }
    } catch (e) {
      print("Error broadcasting file: $e");
    }
  }

  void mockDiscoveredDevice() {
    final newDevice = AppDiscoveredDevice(
      deviceAddress: '00:11:22:33:44:${Random().nextInt(99).toString().padLeft(2, '0')}',
      deviceName: 'Mock Peer ${Random().nextInt(1000)}',
    );
    state = state.copyWith(
      discoveredDevices: [...state.discoveredDevices, newDevice],
    );
  }

  void mockConnectedClient() {
    final newClient = AppClientInfo(
      id: 'mock_client_${Random().nextInt(1000)}',
      username: 'Mock User ${Random().nextInt(1000)}',
      isHost: false,
    );
    state = state.copyWith(
      connectedClients: [...state.connectedClients, newClient],
    );
  }

  Future<void> mockReceivedHazard() async {
    final db = ref.read(databaseProvider);
    await ref.read(cryptoServiceProvider.future);
    final crypto = ref.read(cryptoServiceProvider.notifier);
    final myPubKey = await crypto.getPublicKeyString();
    
    final id = 'mock_hazard_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    final loc = await ref.read(locationControllerProvider.notifier).getCurrentPosition();
    final lat = loc?.latitude ?? 10.730185;
    final lng = loc?.longitude ?? 122.559115;

    final newMarker = HazardMarkersCompanion.insert(
      id: id,
      latitude: lat + (Random().nextDouble() - 0.5) * 0.02,
      longitude: lng + (Random().nextDouble() - 0.5) * 0.02,
      type: 'Flood',
      description: 'Mocked flood report from debug menu',
      timestamp: timestamp,
      senderId: myPubKey,
      signature: const Value('mock_signature'),
      trustTier: 4,
      isCritical: const Value(false),
    );
    
    await db.into(db.hazardMarkers).insert(newMarker);
  }

  void mockHostState() {
    state = state.copyWith(
      isHosting: true,
      hostState: AppHostState(
        isActive: true,
        ssid: 'DIRECT-Mock-Host',
        preSharedKey: 'mockpassword',
        hostIpAddress: '192.168.49.1',
      ),
      syncMessage: 'Mock Host Active',
      clearSyncProgress: true,
    );
  }

  void mockClientState() {
    state = state.copyWith(
      clientState: AppClientState(
        isActive: true,
        hostSsid: 'DIRECT-Mock-Host',
        hostGatewayIpAddress: '192.168.49.1',
        hostIpAddress: '192.168.49.123',
      ),
      syncMessage: 'Mock Client Active',
      clearSyncProgress: true,
    );
  }

  void mockSyncProgress() {
    state = state.copyWith(
      isSyncing: true,
      syncMessage: 'Mock syncing...',
      syncProgress: 0.0,
      syncEstimatedSeconds: 10,
    );
    
    int progress = 0;
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      progress += 10;
      if (progress > 100) {
        timer.cancel();
        state = state.copyWith(
          isSyncing: false,
          syncMessage: 'Mock sync complete',
          clearSyncProgress: true,
        );
      } else {
        state = state.copyWith(
          syncProgress: progress / 100.0,
          syncEstimatedSeconds: 10 - (progress ~/ 10),
        );
      }
    });
  }
}
