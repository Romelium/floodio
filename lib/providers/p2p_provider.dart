import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fixnum/fixnum.dart';
import 'package:floodio/providers/offline_regions_provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import '../database/connection.dart';
import '../database/database.dart';
import '../models/p2p_models.dart';
import '../protos/models.pb.dart' as pb;
import '../services/map_cache_service.dart';
import '../utils/bloom_filter.dart';
import 'database_provider.dart';

part 'p2p_provider.g.dart';

class P2pState {
  final bool isHosting;
  final bool isScanning;
  final bool isSyncing;
  final bool isConnecting;
  final bool isAutoSyncing;
  final String? syncMessage;
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
      'hostState': hostState != null ? {
        'isActive': hostState!.isActive,
        'ssid': hostState!.ssid,
        'preSharedKey': hostState!.preSharedKey,
        'hostIpAddress': hostState!.hostIpAddress,
      } : null,
      'clientState': clientState != null ? {
        'isActive': clientState!.isActive,
        'hostSsid': clientState!.hostSsid,
        'hostGatewayIpAddress': clientState!.hostGatewayIpAddress,
        'hostIpAddress': clientState!.hostIpAddress,
      } : null,
      'discoveredDevices': discoveredDevices.map((d) => {
        'deviceAddress': d.deviceAddress,
        'deviceName': d.deviceName,
      }).toList(),
      'connectedClients': connectedClients.map((c) => {
        'id': c.id,
        'username': c.username,
        'isHost': c.isHost,
      }).toList(),
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
      hostState: map['hostState'] != null ? AppHostState.fromMap(Map<String, dynamic>.from(map['hostState'])) : null,
      clientState: map['clientState'] != null ? AppClientState.fromMap(Map<String, dynamic>.from(map['clientState'])) : null,
      discoveredDevices: (map['discoveredDevices'] as List?)?.map((d) => AppDiscoveredDevice.fromMap(Map<String, dynamic>.from(d))).toList() ?? [],
      connectedClients: (map['connectedClients'] as List?)?.map((c) => AppClientInfo.fromMap(Map<String, dynamic>.from(c))).toList() ?? [],
      peerOfflineRegions: (map['peerOfflineRegions'] as List?)?.map((r) => OfflineRegion.fromJson(Map<String, dynamic>.from(r))).toList() ?? [],
    );
  }
}

@Riverpod(keepAlive: true)
class P2pService extends _$P2pService {
  FlutterP2pHost? _host;
  FlutterP2pClient? _client;

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
      _host?.dispose();
      _client?.dispose();
    });
    return const P2pState();
  }

  Future<void> toggleAutoSync() async {
    _autoSyncTimer?.cancel();
    if (state.isAutoSyncing) {
      state = state.copyWith(isAutoSyncing: false, syncMessage: 'Auto-sync disabled.');
      await stopHosting();
      await disconnect();
    } else {
      state = state.copyWith(isAutoSyncing: true, syncMessage: 'Auto-sync enabled. Starting...');
      _idleTicks = 0;
      _runAutoSyncCycle();
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

    final isHostWithClients = state.isHosting && state.connectedClients.isNotEmpty;
    final isClientConnected = state.clientState?.isActive == true;

    if (isHostWithClients || isClientConnected) {
      _idleTicks++;
      if (_idleTicks >= 6) { // 30 seconds idle after sync
        _idleTicks = 0;
        if (isClientConnected) {
          await disconnect();
        } else {
          await stopHosting();
        }
      } else {
        _autoSyncTimer = Timer(const Duration(seconds: 5), _runAutoSyncCycle);
        return;
      }
    } else {
      _idleTicks = 0;
    }

    // Alternate role
    if (_lastRoleWasHost) {
      _lastRoleWasHost = false;
      await stopHosting();
      if (!state.isAutoSyncing || _disposed) return;
      await Future.delayed(const Duration(seconds: 1));
      if (!state.isAutoSyncing || _disposed) return;
      await startScanning();
    } else {
      _lastRoleWasHost = true;
      await disconnect(); // stops scanning
      if (!state.isAutoSyncing || _disposed) return;
      await Future.delayed(const Duration(seconds: 1));
      if (!state.isAutoSyncing || _disposed) return;
      await startHosting();
    }

    if (state.isAutoSyncing && !_disposed) {
      // Read the latest interval from preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final baseInterval = prefs.getInt('settings_sync_interval') ?? 30;
      
      // Add a small jitter (0-5s) to prevent perfect sync loops between two devices
      final nextCycleSeconds = baseInterval + Random().nextInt(6);
      _autoSyncTimer = Timer(Duration(seconds: nextCycleSeconds), _runAutoSyncCycle);
    }
  }

  Future<void> startHosting() async {
    if (_host != null) return;
    await disconnect(); // Ensure client is fully stopped before hosting

    state = state.copyWith(isHosting: true, syncMessage: 'Initializing host...');

    _host = FlutterP2pHost();
    await _host!.initialize();

    if (!await _host!.checkP2pPermissions()) await _host!.askP2pPermissions();
    if (!await _host!.checkBluetoothPermissions()) await _host!.askBluetoothPermissions();
    if (!await _host!.checkLocationEnabled()) await _host!.enableLocationServices();
    if (!await _host!.checkWifiEnabled()) await _host!.enableWifiServices();
    if (!await _host!.checkBluetoothEnabled()) await _host!.enableBluetoothServices();

    _hostStateSub = _host!.streamHotspotState().listen((hotspotState) {
      state = state.copyWith(hostState: AppHostState(
        isActive: hotspotState.isActive,
        ssid: hotspotState.ssid,
        preSharedKey: hotspotState.preSharedKey,
        hostIpAddress: hotspotState.hostIpAddress,
      ));
    });

    _hostClientListSub = _host!.streamClientList().listen((clients) {
      final previousCount = state.connectedClients.length;
      final appClients = clients.map((c) => AppClientInfo(id: c.id, username: c.username, isHost: c.isHost)).toList();
      state = state.copyWith(connectedClients: appClients);
      if (clients.length > previousCount) {
        state = state.copyWith(syncMessage: 'Client connected. Initiating sync...');
        _sendManifest();
      } else if (clients.isEmpty) {
        state = state.copyWith(syncMessage: 'Waiting for clients...');
        if (state.isAutoSyncing && previousCount > 0 && !_disposed) {
          _idleTicks = 0;
          _autoSyncTimer?.cancel();
          _runAutoSyncCycle();
        }
      }
    });

    _hostTextSub = _host!.streamReceivedTexts().listen((text) {
      _handleReceivedText(text);
    });

    _hostReceivedFilesSub = _host!.streamReceivedFilesInfo().listen((files) {
      _handleReceivedFiles(files, _host!);
    });

    _hostSentFilesSub = _host!.streamSentFilesInfo().listen((files) {
      _idleTicks = 0;
    });

    final host = _host;
    if (host == null || _disposed) return;

    try {
      await host.createGroup(advertise: true);
      if (!state.isHosting || _disposed) {
        await host.removeGroup();
      } else {
        state = state.copyWith(syncMessage: 'Hosting network. Waiting for peers...');
      }
    } catch (e) {
      print("Failed to create group: $e");
      state = state.copyWith(syncMessage: 'Failed to start host: $e');
      await stopHosting();
    }
  }

  Future<void> stopHosting() async {
    await _host?.removeGroup();
    await _host?.dispose();
    _hostStateSub?.cancel();
    _hostClientListSub?.cancel();
    _hostTextSub?.cancel();
    _hostReceivedFilesSub?.cancel();
    _hostSentFilesSub?.cancel();
    _host = null;
    state = state.copyWith(
      isHosting: false,
      isSyncing: false,
      clearHostState: true,
      connectedClients: [],
      syncMessage: 'Host stopped.'
    );
  }

  Future<void> startScanning() async {
    if (_client != null) return;
    await stopHosting(); // Ensure host is fully stopped before scanning

    state = state.copyWith(isScanning: true, discoveredDevices: [], syncMessage: 'Initializing scanner...');

    _client = FlutterP2pClient();
    await _client!.initialize();

    if (!await _client!.checkP2pPermissions()) await _client!.askP2pPermissions();
    if (!await _client!.checkBluetoothPermissions()) await _client!.askBluetoothPermissions();
    if (!await _client!.checkLocationEnabled()) await _client!.enableLocationServices();
    if (!await _client!.checkWifiEnabled()) await _client!.enableWifiServices();
    if (!await _client!.checkBluetoothEnabled()) await _client!.enableBluetoothServices();

    _clientStateSub = _client!.streamHotspotState().listen((hotspotState) {
      final wasActive = state.clientState?.isActive ?? false;
      state = state.copyWith(clientState: AppClientState(
        isActive: hotspotState.isActive,
        hostSsid: hotspotState.hostSsid,
        hostGatewayIpAddress: hotspotState.hostGatewayIpAddress,
        hostIpAddress: hotspotState.hostIpAddress,
      ));
      if (!wasActive && hotspotState.isActive) {
        state = state.copyWith(syncMessage: 'Connected to host. Initiating sync...');
        _sendManifest();
      } else if (wasActive && !hotspotState.isActive) {
        state = state.copyWith(isSyncing: false, syncMessage: 'Disconnected from host.');
        if (state.isAutoSyncing && !_disposed) {
          _idleTicks = 0;
          _autoSyncTimer?.cancel();
          _runAutoSyncCycle();
        }
      }
    });

    _clientTextSub = _client!.streamReceivedTexts().listen((text) {
      _handleReceivedText(text);
    });

    _clientReceivedFilesSub = _client!.streamReceivedFilesInfo().listen((files) {
      _handleReceivedFiles(files, _client!);
    });

    _clientSentFilesSub = _client!.streamSentFilesInfo().listen((files) {
      _idleTicks = 0;
    });

    final client = _client;
    if (client == null || _disposed) return;

    try {
      state = state.copyWith(syncMessage: 'Scanning for nearby devices...');
      final sub = await client.startScan((devices) {
        _rawDiscoveredDevices = devices;
        final appDevices = devices.map((d) => AppDiscoveredDevice(deviceAddress: d.deviceAddress, deviceName: d.deviceName)).toList();
        state = state.copyWith(discoveredDevices: appDevices);
        if (state.isAutoSyncing && devices.isNotEmpty && state.clientState?.isActive != true && !state.isConnecting) {
          connectToDeviceByAddress(devices.first.deviceAddress);
        }
      });
      _scanSub = sub;
      if (!state.isScanning || _disposed) {
        await stopScanning();
      }
    } catch (e) {
      print("Failed to start scan: $e");
      state = state.copyWith(isScanning: false, syncMessage: 'Scan failed: $e');
    }
  }

  Future<void> connectToDeviceByAddress(String address) async {
    if (_client == null || state.isConnecting) return;
    try {
      final device = _rawDiscoveredDevices.firstWhere((d) => d.deviceAddress == address);
      state = state.copyWith(isConnecting: true, syncMessage: 'Connecting to ${device.deviceName}...');
      await stopScanning();

      final client = _client;
      if (client == null || _disposed) {
        state = state.copyWith(isConnecting: false);
        return;
      }

      await client.connectWithDevice(device, timeout: const Duration(seconds: 15));
      if (!state.isConnecting || _disposed) {
        await client.disconnect();
        return;
      }
      state = state.copyWith(isConnecting: false);
    } catch (e) {
      print("Connection failed: $e");
      state = state.copyWith(isConnecting: false, syncMessage: 'Connection failed: $e');
      if (state.isAutoSyncing && !_disposed) {
        // If connection failed, don't wait for the full cycle, try switching roles soon
        _autoSyncTimer?.cancel();
        _autoSyncTimer = Timer(const Duration(seconds: 2), _runAutoSyncCycle);
      }
    }
  }

  Future<void> stopScanning() async {
    await _scanSub?.cancel();
    _scanSub = null;
    await _client?.stopScan();
    state = state.copyWith(isScanning: false);
  }

  Future<void> disconnect() async {
    await stopScanning();
    await _client?.disconnect();
    await _client?.dispose();
    _clientStateSub?.cancel();
    _clientTextSub?.cancel();
    _scanSub?.cancel();
    _clientReceivedFilesSub?.cancel();
    _clientSentFilesSub?.cancel();
    _client = null;
    state = state.copyWith(
      clearClientState: true,
      discoveredDevices: [],
      isConnecting: false,
      isSyncing: false,
      syncMessage: 'Disconnected.'
    );
  }

  void _handleReceivedText(String text) async {
    print("Received text: $text");
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        if (json['type'] == 'manifest') {
          await _handleManifest(json);
          return;
        } else if (json['type'] == 'payload') {
          await _handlePayload(json);
          return;
        } else if (json['type'] == 'request_map') {
          await _handleRequestMap(json);
          return;
        } else if (json['type'] == 'request_image') {
          await _handleRequestImage(json['imageId']);
          return;
        }
      }
    } catch (e) {
      // Not JSON, ignore and treat as normal text
      print("Failed to decode JSON or handle text: $e");
    }

    state = state.copyWith(
      receivedTexts: [...state.receivedTexts, text],
    );
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

  void _handleReceivedFiles(List<ReceivableFileInfo> files, dynamic p2pInstance) async {
    bool isDownloadingAny = false;
    for (final file in files) {
      if (file.state == ReceivableFileState.idle) {
        isDownloadingAny = true;
        final dir = await getApplicationDocumentsDirectory();
        
        state = state.copyWith(isSyncing: true, syncMessage: 'Downloading ${file.info.name}...');
        
        p2pInstance.downloadFile(
          file.info.id,
          dir.path,
          onProgress: (progress) {
            _idleTicks = 0; // Reset idle timer during download
            if (progress.progressPercent % 10 < 1) {
              state = state.copyWith(isSyncing: true, syncMessage: 'Downloading file: ${progress.progressPercent.toStringAsFixed(0)}%');
            }
          }
        );
      } else if (file.state == ReceivableFileState.completed) {
        if (file.info.name.endsWith('.fmap')) {
          final dir = await getApplicationDocumentsDirectory();
          final downloadedFile = File('${dir.path}/${file.info.name}');
          if (await downloadedFile.exists()) {
            state = state.copyWith(isSyncing: true, syncMessage: 'Unpacking map...');
            try {
              final mapCache = ref.read(mapCacheServiceProvider);
              await mapCache.unpackMap(downloadedFile);
              
              if (file.info.name.startsWith('map_')) {
                try {
                  final parts = file.info.name.replaceAll('.fmap', '').split('_');
                  if (parts.length == 7) {
                    final region = OfflineRegion(
                      bounds: LatLngBounds(
                        LatLng(double.parse(parts[2]), double.parse(parts[4])), // south, west
                        LatLng(double.parse(parts[1]), double.parse(parts[3])), // north, east
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
              
              state = state.copyWith(isSyncing: false, syncMessage: 'Map updated successfully.');
            } catch (e) {
              print("Error unpacking map: $e");
              state = state.copyWith(isSyncing: false, syncMessage: 'Failed to unpack map.');
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
      }
    }
    
    if (isDownloadingAny) {
      state = state.copyWith(isSyncing: true);
    } else if (!isDownloadingAny && state.isSyncing && state.syncMessage?.startsWith('Downloading') == true) {
       state = state.copyWith(isSyncing: false, syncMessage: 'Downloads complete.');
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
          bloomFilter.add('del_${d.id}');
        }
        
        final adminTrusted = await db.select(db.adminTrustedSenders).get();
        for (final a in adminTrusted) {
          bloomFilter.add('delg_${a.publicKey}');
        }

        final revoked = await db.select(db.revokedDelegations).get();
        for (final r in revoked) {
          bloomFilter.add('rev_${r.delegateePublicKey}');
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
    } catch (e) {
      print("Error sending manifest: $e");
    }
  }

  Future<void> _handleManifest(Map<String, dynamic> json) async {
    _idleTicks = 0;
    state = state.copyWith(isSyncing: true, syncMessage: 'Comparing data...');
    try {
      final peerRegionsJson = json['offlineRegions'] as List<dynamic>? ?? [];
      final peerRegions = peerRegionsJson.map((e) => OfflineRegion.fromJson(Map<String, dynamic>.from(e))).toList();

      state = state.copyWith(peerOfflineRegions: peerRegions);

      final bloomSize = json['bloomSize'] as int? ?? 32768;
      final bloomBits = (json['bloomFilter'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [];

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

        final newHazards = allHazards.where((h) => !peerBloomFilter.mightContain(h.id)).take(200).toList();
        final newNews = allNews.where((n) => !peerBloomFilter.mightContain(n.id)).take(200).toList();
        final newProfiles = allProfiles.where((p) => !peerBloomFilter.mightContain('${p.publicKey}_${p.timestamp}')).take(200).toList();
        final newDeleted = allDeleted.where((d) => !peerBloomFilter.mightContain('del_${d.id}')).take(200).toList();
        final newAreas = allAreas.where((a) => !peerBloomFilter.mightContain(a.id)).take(200).toList();
        final newPaths = allPaths.where((p) => !peerBloomFilter.mightContain(p.id)).take(200).toList();
        final newDelegations = allAdminTrusted.where((a) => !peerBloomFilter.mightContain('delg_${a.publicKey}')).take(200).toList();
        final newRevocations = allRevoked.where((r) => !peerBloomFilter.mightContain('rev_${r.delegateePublicKey}')).take(200).toList();

        await db.close();

        return (newHazards, newNews, newProfiles, newDeleted, newAreas, newPaths, newDelegations, newRevocations);
      });

      final newHazards = filterResult.$1;
      final newNews = filterResult.$2;
      final newProfiles = filterResult.$3;
      final newDeleted = filterResult.$4;
      final newAreas = filterResult.$5;
      final newPaths = filterResult.$6;
      final newDelegations = filterResult.$7;
      final newRevocations = filterResult.$8;

      if (newHazards.isEmpty && newNews.isEmpty && newProfiles.isEmpty && newDeleted.isEmpty && newAreas.isEmpty && newPaths.isEmpty && newDelegations.isEmpty && newRevocations.isEmpty) {
        state = state.copyWith(isSyncing: false, syncMessage: 'Up to date.');
        return;
      }

      state = state.copyWith(syncMessage: 'Sending ${newHazards.length} markers, ${newNews.length} news, ${newProfiles.length} profiles, ${newAreas.length} areas, ${newPaths.length} paths, ${newDeleted.length} deletions, ${newDelegations.length} delegations, ${newRevocations.length} revocations...');

      final payload = pb.SyncPayload();

      for (final h in newHazards) {
        payload.markers.add(pb.HazardMarker(
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
        ));
      }

      for (final n in newNews) {
        payload.news.add(pb.NewsItem(
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
        ));
      }

      for (final p in newProfiles) {
        payload.profiles.add(pb.UserProfile(
          publicKey: p.publicKey,
          name: p.name,
          contactInfo: p.contactInfo,
          timestamp: Int64(p.timestamp),
          signature: p.signature,
        ));
      }

      for (final d in newDeleted) {
        payload.deletedItems.add(pb.DeletedItem(
          id: d.id,
          timestamp: Int64(d.timestamp),
        ));
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
          areaMarker.coordinates.add(pb.Coordinate(
            latitude: coord['lat']!,
            longitude: coord['lng']!,
          ));
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
          pathMarker.coordinates.add(pb.Coordinate(
            latitude: coord['lat']!,
            longitude: coord['lng']!,
          ));
        }
        payload.paths.add(pathMarker);
      }

      for (final d in newDelegations) {
        payload.delegations.add(pb.TrustDelegation(
          id: 'delg_${d.publicKey}',
          delegatorPublicKey: d.delegatorPublicKey,
          delegateePublicKey: d.publicKey,
          timestamp: Int64(d.timestamp),
          signature: d.signature,
        ));
      }

      for (final r in newRevocations) {
        payload.revokedDelegations.add(pb.RevokedDelegation(
          delegateePublicKey: r.delegateePublicKey,
          delegatorPublicKey: r.delegatorPublicKey,
          timestamp: Int64(r.timestamp),
          signature: r.signature,
        ));
      }

      final encoded = base64Encode(payload.writeToBuffer());
      await broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));
      state = state.copyWith(syncMessage: 'Data sent successfully.');
    } catch (e) {
      print("Error handling manifest: $e");
      state = state.copyWith(syncMessage: 'Error sending data.');
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  Future<void> _handleRequestMap(Map<String, dynamic> json) async {
    state = state.copyWith(isSyncing: true, syncMessage: 'Packing offline map for transfer...');
    try {
      OfflineRegion? region;
      if (json['region'] != null) {
        region = OfflineRegion.fromJson(Map<String, dynamic>.from(json['region']));
      }
      final mapCache = ref.read(mapCacheServiceProvider);
      final packFile = await mapCache.packMap(region: region);
      
      if (_host != null && state.hostState?.isActive == true) {
        await _host!.broadcastFile(packFile);
      } else if (_client != null && state.clientState?.isActive == true) {
        await _client!.broadcastFile(packFile);
      }
      state = state.copyWith(isSyncing: false, syncMessage: 'Map file sent.');
    } catch (e) {
      print("Error sending map: $e");
      state = state.copyWith(isSyncing: false, syncMessage: 'Error sending map.');
    }
  }

  Future<void> _handlePayload(Map<String, dynamic> json) async {
    _idleTicks = 0;
    state = state.copyWith(isSyncing: true, syncMessage: 'Receiving data...');
    try {
      if (json['data'] == null) {
        state = state.copyWith(syncMessage: 'Invalid payload received.');
        return;
      }
      final data = base64Decode(json['data']);
      final payload = pb.SyncPayload.fromBuffer(data);

      if (payload.markers.isEmpty && payload.news.isEmpty && payload.profiles.isEmpty && payload.deletedItems.isEmpty && payload.areas.isEmpty && payload.paths.isEmpty && payload.delegations.isEmpty && payload.revokedDelegations.isEmpty) {
        state = state.copyWith(syncMessage: 'Empty payload received.');
        return;
      }

      state = state.copyWith(syncMessage: 'Verifying signatures...');

      final db = ref.read(databaseProvider);
      await ref.read(cryptoServiceProvider.future); // Ensure crypto is initialized
      final crypto = ref.read(cryptoServiceProvider.notifier);

      final trustedSenders = await db.select(db.trustedSenders).get();
      final trustedKeys = trustedSenders.map((e) => e.publicKey).toList();

      final untrustedSenders = await db.select(db.untrustedSenders).get();
      final untrustedKeys = untrustedSenders.map((e) => e.publicKey).toList();

      final adminTrustedSenders = await db.select(db.adminTrustedSenders).get();
      final adminTrustedKeys = adminTrustedSenders.map((e) => e.publicKey).toList();
      final delegationTimestamps = {for (var d in adminTrustedSenders) d.publicKey: d.timestamp};

      final deletedItems = await db.select(db.deletedItems).get();
      final deletedIds = deletedItems.map((e) => e.id).toSet();

      final allRevocations = await db.select(db.revokedDelegations).get();
      final revocationTimestamps = {for (var r in allRevocations) r.delegateePublicKey: r.timestamp};
      final revokedKeys = allRevocations.map((e) => e.delegateePublicKey).toList();

      // Fetch existing timestamps for LWW CRDT resolution (optimized with isIn)
      final payloadMarkerIds = payload.markers.map((m) => m.id).toList();
      final existingMarkers = payloadMarkerIds.isEmpty ? [] : await (db.select(db.hazardMarkers)..where((t) => t.id.isIn(payloadMarkerIds))).get();
      final markerTimestamps = {for (var m in existingMarkers) m.id: m.timestamp};

      final payloadNewsIds = payload.news.map((n) => n.id).toList();
      final existingNews = payloadNewsIds.isEmpty ? [] : await (db.select(db.newsItems)..where((t) => t.id.isIn(payloadNewsIds))).get();
      final newsTimestamps = {for (var n in existingNews) n.id: n.timestamp};

      final payloadProfileKeys = payload.profiles.map((p) => p.publicKey).toList();
      final existingProfiles = payloadProfileKeys.isEmpty ? [] : await (db.select(db.userProfiles)..where((t) => t.publicKey.isIn(payloadProfileKeys))).get();
      final profileTimestamps = {for (var p in existingProfiles) p.publicKey: p.timestamp};

      final payloadAreaIds = payload.areas.map((a) => a.id).toList();
      final existingAreas = payloadAreaIds.isEmpty ? [] : await (db.select(db.areas)..where((t) => t.id.isIn(payloadAreaIds))).get();
      final areaTimestamps = {for (var a in existingAreas) a.id: a.timestamp};

      final payloadPathIds = payload.paths.map((p) => p.id).toList();
      final existingPaths = payloadPathIds.isEmpty ? [] : await (db.select(db.paths)..where((t) => t.id.isIn(payloadPathIds))).get();
      final pathTimestamps = {for (var p in existingPaths) p.id: p.timestamp};

      for (final d in payload.deletedItems) {
        deletedIds.add(d.id);
      }

      final seenIds = <SeenMessageIdsCompanion>[];
      final validDelegations = <AdminTrustedSendersCompanion>[];
      for (final d in payload.delegations) {
        final existingTs = delegationTimestamps[d.delegateePublicKey] ?? 0;
        if (d.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final isValid = await crypto.verifyDelegation(
          delegateePublicKeyStr: d.delegateePublicKey,
          timestamp: d.timestamp.toInt(),
          signatureStr: d.signature,
          delegatorPublicKeyStr: d.delegatorPublicKey,
        );
        if (isValid) {
          validDelegations.add(AdminTrustedSendersCompanion.insert(
            publicKey: d.delegateePublicKey,
            delegatorPublicKey: d.delegatorPublicKey,
            timestamp: d.timestamp.toInt(),
            signature: d.signature,
          ));
          adminTrustedKeys.add(d.delegateePublicKey);
          seenIds.add(SeenMessageIdsCompanion.insert(
            messageId: d.id,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          print("Invalid signature for delegation ${d.id}, dropping.");
        }
      }

      final validRevocations = <RevokedDelegationsCompanion>[];
      for (final r in payload.revokedDelegations) {
        final existingTs = revocationTimestamps[r.delegateePublicKey] ?? 0;
        if (r.timestamp.toInt() <= existingTs) continue;

        final isValid = await crypto.verifyRevocation(
          delegateePublicKeyStr: r.delegateePublicKey,
          timestamp: r.timestamp.toInt(),
          signatureStr: r.signature,
          delegatorPublicKeyStr: r.delegatorPublicKey,
        );
        if (isValid) {
          validRevocations.add(RevokedDelegationsCompanion.insert(
            delegateePublicKey: r.delegateePublicKey,
            delegatorPublicKey: r.delegatorPublicKey,
            timestamp: r.timestamp.toInt(),
            signature: r.signature,
          ));
          seenIds.add(SeenMessageIdsCompanion.insert(
            messageId: 'rev_${r.delegateePublicKey}',
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          print("Invalid signature for revocation ${r.delegateePublicKey}, dropping.");
        }
      }

      for (final r in validRevocations) {
        revokedKeys.add(r.delegateePublicKey.value);
      }

      final validMarkers = <HazardMarkersCompanion>[];
      for (final m in payload.markers) {
        if (deletedIds.contains(m.id)) continue;
        final existingTs = markerTimestamps[m.id] ?? 0;
        if (m.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final imageIdStr = m.imageId.isEmpty ? "" : m.imageId;
        final expiresAtStr = m.expiresAt == 0 ? "" : m.expiresAt.toString();
        final isCriticalStr = m.isCritical ? "1" : "0";
        final payloadToSign = utf8.encode('${m.id}${m.latitude}${m.longitude}${m.type}${m.description}${m.timestamp}$imageIdStr$expiresAtStr$isCriticalStr');
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
          validMarkers.add(HazardMarkersCompanion.insert(
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
          ));
          seenIds.add(SeenMessageIdsCompanion.insert(
            messageId: m.id,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          print("Invalid signature for marker ${m.id}, dropping.");
        }
      }

      final validNews = <NewsItemsCompanion>[];
      for (final n in payload.news) {
        if (deletedIds.contains(n.id)) continue;
        final existingTs = newsTimestamps[n.id] ?? 0;
        if (n.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final imageIdStr = n.imageId.isEmpty ? "" : n.imageId;
        final expiresAtStr = n.expiresAt == 0 ? "" : n.expiresAt.toString();
        final isCriticalStr = n.isCritical ? "1" : "0";
        final payloadToSign = utf8.encode('${n.id}${n.title}${n.content}${n.timestamp}$imageIdStr$expiresAtStr$isCriticalStr');
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
          validNews.add(NewsItemsCompanion.insert(
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
          ));
          seenIds.add(SeenMessageIdsCompanion.insert(
            messageId: n.id,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          print("Invalid signature for news ${n.id}, dropping.");
        }
      }

      final validProfiles = <UserProfilesCompanion>[];
      for (final p in payload.profiles) {
        final existingTs = profileTimestamps[p.publicKey] ?? 0;
        if (p.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final payloadToSign = utf8.encode('${p.publicKey}${p.name}${p.contactInfo}${p.timestamp}');
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
          validProfiles.add(UserProfilesCompanion.insert(
            publicKey: p.publicKey,
            name: p.name,
            contactInfo: p.contactInfo,
            timestamp: p.timestamp.toInt(),
            signature: p.signature,
          ));
          seenIds.add(SeenMessageIdsCompanion.insert(
            messageId: '${p.publicKey}_${p.timestamp}',
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          print("Invalid signature for profile ${p.publicKey}, dropping.");
        }
      }

      final validAreas = <AreasCompanion>[];
      for (final a in payload.areas) {
        if (deletedIds.contains(a.id)) continue;
        final existingTs = areaTimestamps[a.id] ?? 0;
        if (a.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final expiresAtStr = a.expiresAt == 0 ? "" : a.expiresAt.toString();
        final isCriticalStr = a.isCritical ? "1" : "0";
        final coordsStr = a.coordinates.map((c) => '${c.latitude},${c.longitude}').join('|');
        final payloadToSign = utf8.encode('${a.id}$coordsStr${a.type}${a.description}${a.timestamp}$expiresAtStr$isCriticalStr');
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
          final coords = a.coordinates.map((c) => {'lat': c.latitude, 'lng': c.longitude}).toList();
          validAreas.add(AreasCompanion.insert(
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
          ));
          seenIds.add(SeenMessageIdsCompanion.insert(
            messageId: a.id,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          print("Invalid signature for area ${a.id}, dropping.");
        }
      }

      final validPaths = <PathsCompanion>[];
      for (final p in payload.paths) {
        if (deletedIds.contains(p.id)) continue;
        final existingTs = pathTimestamps[p.id] ?? 0;
        if (p.timestamp.toInt() <= existingTs) continue; // LWW CRDT

        final expiresAtStr = p.expiresAt == 0 ? "" : p.expiresAt.toString();
        final isCriticalStr = p.isCritical ? "1" : "0";
        final coordsStr = p.coordinates.map((c) => '${c.latitude},${c.longitude}').join('|');
        final payloadToSign = utf8.encode('${p.id}$coordsStr${p.type}${p.description}${p.timestamp}$expiresAtStr$isCriticalStr');
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
          final coords = p.coordinates.map((c) => {'lat': c.latitude, 'lng': c.longitude}).toList();
          validPaths.add(PathsCompanion.insert(
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
          ));
          seenIds.add(SeenMessageIdsCompanion.insert(
            messageId: p.id,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          print("Invalid signature for path ${p.id}, dropping.");
        }
      }

      final validDeleted = <DeletedItemsCompanion>[];
      for (final d in payload.deletedItems) {
        validDeleted.add(DeletedItemsCompanion.insert(
          id: d.id,
          timestamp: d.timestamp.toInt(),
        ));
      }

      state = state.copyWith(syncMessage: 'Saving to database...');

      await db.batch((batch) {
        batch.insertAll(db.hazardMarkers, validMarkers, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.newsItems, validNews, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.userProfiles, validProfiles, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.areas, validAreas, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.paths, validPaths, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.seenMessageIds, seenIds, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.deletedItems, validDeleted, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.adminTrustedSenders, validDelegations, mode: InsertMode.insertOrReplace);
        batch.insertAll(db.revokedDelegations, validRevocations, mode: InsertMode.insertOrReplace);
      });

      final dir = await getApplicationDocumentsDirectory();
      await db.transaction(() async {
        for (final d in validDeleted) {
          final marker = await (db.select(db.hazardMarkers)..where((t) => t.id.equals(d.id.value))).getSingleOrNull();
          if (marker?.imageId != null && marker!.imageId!.isNotEmpty) {
            final file = File('${dir.path}/${marker.imageId}');
            if (await file.exists()) await file.delete();
          }
          
          final news = await (db.select(db.newsItems)..where((t) => t.id.equals(d.id.value))).getSingleOrNull();
          if (news?.imageId != null && news!.imageId!.isNotEmpty) {
            final file = File('${dir.path}/${news.imageId}');
            if (await file.exists()) await file.delete();
          }

          await (db.delete(db.hazardMarkers)..where((t) => t.id.equals(d.id.value))).go();
          await (db.delete(db.newsItems)..where((t) => t.id.equals(d.id.value))).go();
          await (db.delete(db.areas)..where((t) => t.id.equals(d.id.value))).go();
          await (db.delete(db.paths)..where((t) => t.id.equals(d.id.value))).go();
        }
        for (final d in validDelegations) {
          if (revokedKeys.contains(d.publicKey.value)) continue;
          await (db.update(db.hazardMarkers)..where((t) => t.senderId.equals(d.publicKey.value) & t.trustTier.isBiggerThanValue(2)))
              .write(const HazardMarkersCompanion(trustTier: Value(2)));
          await (db.update(db.newsItems)..where((t) => t.senderId.equals(d.publicKey.value) & t.trustTier.isBiggerThanValue(2)))
              .write(const NewsItemsCompanion(trustTier: Value(2)));
          await (db.update(db.areas)..where((t) => t.senderId.equals(d.publicKey.value) & t.trustTier.isBiggerThanValue(2)))
              .write(const AreasCompanion(trustTier: Value(2)));
          await (db.update(db.paths)..where((t) => t.senderId.equals(d.publicKey.value) & t.trustTier.isBiggerThanValue(2)))
              .write(const PathsCompanion(trustTier: Value(2)));
        }
        for (final r in validRevocations) {
          final fallbackTier = trustedKeys.contains(r.delegateePublicKey.value) ? 3 : 4;
          await (db.update(db.hazardMarkers)..where((t) => t.senderId.equals(r.delegateePublicKey.value) & t.trustTier.equals(2)))
              .write(HazardMarkersCompanion(trustTier: Value(fallbackTier)));
          await (db.update(db.newsItems)..where((t) => t.senderId.equals(r.delegateePublicKey.value) & t.trustTier.equals(2)))
              .write(NewsItemsCompanion(trustTier: Value(fallbackTier)));
          await (db.update(db.areas)..where((t) => t.senderId.equals(r.delegateePublicKey.value) & t.trustTier.equals(2)))
              .write(AreasCompanion(trustTier: Value(fallbackTier)));
          await (db.update(db.paths)..where((t) => t.senderId.equals(r.delegateePublicKey.value) & t.trustTier.equals(2)))
              .write(PathsCompanion(trustTier: Value(fallbackTier)));
        }
      });

      // Request missing images
      for (final m in validMarkers) {
        final imageId = m.imageId.value;
        if (imageId != null && imageId.isNotEmpty) {
          final file = File('${dir.path}/$imageId');
          if (!await file.exists()) {
            await broadcastText(jsonEncode({'type': 'request_image', 'imageId': imageId}));
          }
        }
      }
      for (final n in validNews) {
        final imageId = n.imageId.value;
        if (imageId != null && imageId.isNotEmpty) {
          final file = File('${dir.path}/$imageId');
          if (!await file.exists()) {
            await broadcastText(jsonEncode({'type': 'request_image', 'imageId': imageId}));
          }
        }
      }

      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Successfully synced ${validMarkers.length} markers, ${validNews.length} news, ${validProfiles.length} profiles, ${validAreas.length} areas, ${validPaths.length} paths, ${validDeleted.length} deletions, ${validDelegations.length} delegations, ${validRevocations.length} revocations.'
      );
      print("Successfully synced ${payload.markers.length} markers, ${payload.news.length} news, ${payload.profiles.length} profiles, ${payload.areas.length} areas, ${payload.paths.length} paths, ${payload.deletedItems.length} deletions, ${payload.delegations.length} delegations, ${payload.revokedDelegations.length} revocations.");
    } catch (e) {
      print("Error handling payload: $e");
      state = state.copyWith(syncMessage: 'Error syncing data.');
    } finally {
      state = state.copyWith(isSyncing: false);
    }
  }

  Future<void> triggerSync() async {
    await _sendManifest();
  }

  Future<void> requestMapRegion(OfflineRegion region) async {
    await broadcastText(jsonEncode({
      'type': 'request_map',
      'region': region.toJson(),
    }));
  }

  Future<void> broadcastText(String text) async {
    try {
      if (_host != null && state.hostState?.isActive == true) {
        await _host!.broadcastText(text);
      } else if (_client != null && state.clientState?.isActive == true) {
        await _client!.broadcastText(text);
      }
    } catch (e) {
      print("Error broadcasting text: $e");
    }
  }

  Future<void> broadcastFile(File file) async {
    try {
      if (_host != null && state.hostState?.isActive == true) {
        await _host!.broadcastFile(file);
      } else if (_client != null && state.clientState?.isActive == true) {
        await _client!.broadcastFile(file);
      }
    } catch (e) {
      print("Error broadcasting file: $e");
    }
  }
}
