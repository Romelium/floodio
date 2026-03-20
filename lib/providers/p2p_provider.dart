import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../crypto/crypto_service.dart';
import '../database/database.dart';
import '../protos/models.pb.dart' as pb;
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
  final HotspotHostState? hostState;
  final HotspotClientState? clientState;
  final List<BleDiscoveredDevice> discoveredDevices;
  final List<P2pClientInfo> connectedClients;
  final List<String> receivedTexts;

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
  });

  P2pState copyWith({
    bool? isHosting,
    bool? isScanning,
    bool? isSyncing,
    bool? isConnecting,
    bool? isAutoSyncing,
    String? syncMessage,
    HotspotHostState? hostState,
    bool clearHostState = false,
    HotspotClientState? clientState,
    bool clearClientState = false,
    List<BleDiscoveredDevice>? discoveredDevices,
    List<P2pClientInfo>? connectedClients,
    List<String>? receivedTexts,
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
  Timer? _autoSyncTimer;
  bool _disposed = false;

  bool _lastRoleWasHost = false;
  int _idleTicks = 0;

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
      // Randomize cycle between 12 and 25 seconds to prevent perfect sync loops
      final nextCycleSeconds = 12 + Random().nextInt(14);
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
      state = state.copyWith(hostState: hotspotState);
    });

    _hostClientListSub = _host!.streamClientList().listen((clients) {
      final previousCount = state.connectedClients.length;
      state = state.copyWith(connectedClients: clients);
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
      state = state.copyWith(clientState: hotspotState);
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

    final client = _client;
    if (client == null || _disposed) return;

    try {
      state = state.copyWith(syncMessage: 'Scanning for nearby devices...');
      final sub = await client.startScan((devices) {
        state = state.copyWith(discoveredDevices: devices);
        if (state.isAutoSyncing && devices.isNotEmpty && state.clientState?.isActive != true && !state.isConnecting) {
          connectToDevice(devices.first);
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

  Future<void> connectToDevice(BleDiscoveredDevice device) async {
    if (_client == null || state.isConnecting) return;
    state = state.copyWith(isConnecting: true, syncMessage: 'Connecting to ${device.deviceName}...');
    await stopScanning();

    final client = _client;
    if (client == null || _disposed) {
      state = state.copyWith(isConnecting: false);
      return;
    }

    try {
      await client.connectWithDevice(device, timeout: const Duration(seconds: 15));
      if (!state.isConnecting || _disposed) {
        // Disconnect was called while we were waiting for connection
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

  Future<void> _sendManifest() async {
    _idleTicks = 0;
    try {
    final db = ref.read(databaseProvider);

    final seenIds = await db.select(db.seenMessageIds).get();
    
    final bloomFilter = BloomFilter(32768, 5);
    for (final seen in seenIds) {
      bloomFilter.add(seen.messageId);
    }

    final manifest = {
      'type': 'manifest',
      'bloomFilter': bloomFilter.bits,
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
      final bloomBits = (json['bloomFilter'] as List<dynamic>?)?.map((e) => (e as num).toInt()).toList() ?? [];
      final peerBloomFilter = BloomFilter.fromList(bloomBits, 32768, 5);

      final db = ref.read(databaseProvider);

      final allHazards = await db.select(db.hazardMarkers).get();
      final allNews = await db.select(db.newsItems).get();

      final newHazards = allHazards.where((h) => !peerBloomFilter.mightContain(h.id)).take(200).toList();
      final newNews = allNews.where((n) => !peerBloomFilter.mightContain(n.id)).take(200).toList();

      if (newHazards.isEmpty && newNews.isEmpty) {
        state = state.copyWith(syncMessage: 'Up to date.');
        return;
      }

      state = state.copyWith(syncMessage: 'Sending ${newHazards.length} markers and ${newNews.length} news...');

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

      if (payload.markers.isEmpty && payload.news.isEmpty) {
        state = state.copyWith(syncMessage: 'Empty payload received.');
        return;
      }

      state = state.copyWith(syncMessage: 'Verifying signatures...');

      final db = ref.read(databaseProvider);
      await ref.read(cryptoServiceProvider.future); // Ensure crypto is initialized
      final crypto = ref.read(cryptoServiceProvider.notifier);

      final trustedSenders = await db.select(db.trustedSenders).get();
      final trustedKeys = trustedSenders.map((e) => e.publicKey).toList();

      final validMarkers = <HazardMarkersCompanion>[];
      final seenIds = <SeenMessageIdsCompanion>[];
      for (final m in payload.markers) {
        final payloadToSign = utf8.encode('${m.id}${m.type}${m.timestamp}');
        final trustTier = await crypto.verifyAndGetTrustTier(
          data: payloadToSign,
          signatureStr: m.signature,
          senderPublicKeyStr: m.senderId,
          trustedPublicKeys: trustedKeys,
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
        final payloadToSign = utf8.encode('${n.id}${n.title}${n.timestamp}');
        final trustTier = await crypto.verifyAndGetTrustTier(
          data: payloadToSign,
          signatureStr: n.signature,
          senderPublicKeyStr: n.senderId,
          trustedPublicKeys: trustedKeys,
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
          ));
          seenIds.add(SeenMessageIdsCompanion.insert(
            messageId: n.id,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ));
        } else {
          print("Invalid signature for news ${n.id}, dropping.");
        }
      }

      state = state.copyWith(syncMessage: 'Saving to database...');

      await db.transaction(() async {
        for (final m in validMarkers) {
          await db.into(db.hazardMarkers).insert(m, mode: InsertMode.insertOrReplace);
        }
        for (final n in validNews) {
          await db.into(db.newsItems).insert(n, mode: InsertMode.insertOrReplace);
        }
        for (final s in seenIds) {
          await db.into(db.seenMessageIds).insert(s, mode: InsertMode.insertOrReplace);
        }
      });

      state = state.copyWith(
        syncMessage: 'Successfully synced ${validMarkers.length} markers and ${validNews.length} news items.'
      );
      print("Successfully synced ${payload.markers.length} markers and ${payload.news.length} news items.");
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
}