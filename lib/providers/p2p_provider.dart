import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:drift/drift.dart';
import 'package:fixnum/fixnum.dart';
import 'package:floodio/services/background_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:geolocator/geolocator.dart';
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
const int _verifyBatchSize = 10;

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
  final String? lastSyncSummary;
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
    this.lastSyncSummary,
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
    String? lastSyncSummary,
    bool clearLastSyncSummary = false,
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
      lastSyncSummary: clearLastSyncSummary
          ? null
          : (lastSyncSummary ?? this.lastSyncSummary),
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
      'lastSyncSummary': lastSyncSummary,
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
      lastSyncSummary: map['lastSyncSummary'],
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
        other.lastSyncSummary == lastSyncSummary &&
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
      lastSyncSummary,
      hostState,
      clientState,
      Object.hashAll(discoveredDevices),
      Object.hashAll(connectedClients),
      Object.hashAll(receivedTexts),
      Object.hashAll(peerOfflineRegions),
    );
  }
}

Future<String> _encodePayloadInIsolate(pb.SyncPayload payload) {
  return Isolate.run(() => base64Encode(payload.writeToBuffer()));
}

Future<Map<String, dynamic>> _runVerifyPayloadInIsolate(
  Map<String, dynamic> args,
  void Function(double) onProgress,
  Future<void> Function(Map<String, dynamic>) onBatch,
) async {
  final receivePort = ReceivePort();
  args['sendPort'] = receivePort.sendPort;
  args['rootToken'] = RootIsolateToken.instance;

  final isolate = await Isolate.spawn(
    _verifyPayloadInIsolateWithProgress,
    args,
  );

  final completer = Completer<Map<String, dynamic>>();

  StreamSubscription? sub;
  sub = receivePort.listen((message) async {
    if (message is double) {
      onProgress(message);
    } else if (message is Map<String, dynamic>) {
      if (message['type'] == 'batch') {
        sub?.pause();
        try {
          await onBatch(message['data']);
        } catch (e, st) {
          terminalLog("[-] Error processing batch: $e\n$st");
        }
        sub?.resume();
      } else if (message['type'] == 'log') {
        terminalLog(message['message']);
      } else if (message['type'] == 'done') {
        completer.complete({});
        receivePort.close();
        isolate.kill();
      }
    } else if (message is Exception || message is Error) {
      completer.completeError(message);
      receivePort.close();
      isolate.kill();
    } else {
      completer.completeError(Exception(message.toString()));
      receivePort.close();
      isolate.kill();
    }
  });

  return completer.future;
}

Future<void> _verifyPayloadInIsolateWithProgress(
  Map<String, dynamic> args,
) async {
  final sendPort = args['sendPort'] as SendPort;
  try {
    final token = args['rootToken'] as RootIsolateToken?;
    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }
    await _verifyPayloadInIsolate(args, sendPort);
  } catch (e, st) {
    sendPort.send(Exception('$e\n$st'));
  }
}

Future<void> _verifyPayloadInIsolate(
  Map<String, dynamic> args, [
  SendPort? sendPort,
]) async {
  final isolateStopwatch = Stopwatch()..start();

  void log(String msg) {
    if (sendPort != null) {
      sendPort.send({'type': 'log', 'message': msg});
    } else {
      print(msg);
    }
  }

  final payload = args['payload'] as pb.SyncPayload;
  final trustedKeys = (args['trustedKeys'] as List<String>).toSet();
  final adminTrustedKeys = (args['adminTrustedKeys'] as List<String>).toSet();
  final untrustedKeys = (args['untrustedKeys'] as List<String>).toSet();
  final revokedKeys = (args['revokedKeys'] as List<String>).toSet();
  final serverPubKeyBytes = args['serverPubKeyBytes'] as List<int>;
  final deletedIds = args['deletedIds'] as Set<String>;

  final markerTimestamps = args['markerTimestamps'] as Map<String, int>;
  final newsTimestamps = args['newsTimestamps'] as Map<String, int>;
  final profileTimestamps = args['profileTimestamps'] as Map<String, int>;
  final areaTimestamps = args['areaTimestamps'] as Map<String, int>;
  final pathTimestamps = args['pathTimestamps'] as Map<String, int>;
  final delegationTimestamps = args['delegationTimestamps'] as Map<String, int>;
  final revocationTimestamps = args['revocationTimestamps'] as Map<String, int>;

  final validMarkers = <pb.HazardMarker>[];
  final validNews = <pb.NewsItem>[];
  final validProfiles = <pb.UserProfile>[];
  final validAreas = <pb.AreaMarker>[];
  final validPaths = <pb.PathMarker>[];
  final validDelegations = <pb.TrustDelegation>[];
  final validRevocations = <pb.RevokedDelegation>[];

  final markerTrustTiers = <String, int>{};
  final newsTrustTiers = <String, int>{};
  final areaTrustTiers = <String, int>{};
  final pathTrustTiers = <String, int>{};

  final totalItems =
      payload.delegations.length +
      payload.revokedDelegations.length +
      payload.markers.length +
      payload.news.length +
      payload.profiles.length +
      payload.areas.length +
      payload.paths.length;

  int processed = 0;
  int lastReportedPercent = -1;

  void reportProgress() {
    if (sendPort != null && totalItems > 0) {
      final percent = ((processed / totalItems) * 100).toInt();
      if (percent > lastReportedPercent) {
        lastReportedPercent = percent;
        sendPort.send(processed / totalItems);
      }
    }
  }

  void sendBatchIfNeeded({bool force = false}) {
    final totalValid =
        validMarkers.length +
        validNews.length +
        validProfiles.length +
        validAreas.length +
        validPaths.length +
        validDelegations.length +
        validRevocations.length;
    if (totalValid >= _verifyBatchSize || (force && totalValid > 0)) {
      if (sendPort != null) {
        sendPort.send({
          'type': 'batch',
          'data': {
            'validMarkers': List<pb.HazardMarker>.from(validMarkers),
            'validNews': List<pb.NewsItem>.from(validNews),
            'validProfiles': List<pb.UserProfile>.from(validProfiles),
            'validAreas': List<pb.AreaMarker>.from(validAreas),
            'validPaths': List<pb.PathMarker>.from(validPaths),
            'validDelegations': List<pb.TrustDelegation>.from(validDelegations),
            'validRevocations': List<pb.RevokedDelegation>.from(
              validRevocations,
            ),
            'markerTrustTiers': Map<String, int>.from(markerTrustTiers),
            'newsTrustTiers': Map<String, int>.from(newsTrustTiers),
            'areaTrustTiers': Map<String, int>.from(areaTrustTiers),
            'pathTrustTiers': Map<String, int>.from(pathTrustTiers),
          },
        });
      }
      validMarkers.clear();
      validNews.clear();
      validProfiles.clear();
      validAreas.clear();
      validPaths.clear();
      validDelegations.clear();
      validRevocations.clear();
      markerTrustTiers.clear();
      newsTrustTiers.clear();
      areaTrustTiers.clear();
      pathTrustTiers.clear();
    }
  }

  // Process delegations
  for (var i = 0; i < payload.delegations.length; i += _verifyBatchSize) {
    final chunk = payload.delegations.skip(i).take(_verifyBatchSize);
    final results = await Future.wait(
      chunk.map((d) async {
        final itemSw = Stopwatch()..start();
        final existingTs = delegationTimestamps[d.delegateePublicKey] ?? 0;
        if (d.timestamp.toInt() <= existingTs) return null;
        final isValid = await verifyDelegationLogic(
          d.delegateePublicKey,
          d.timestamp.toInt(),
          d.signature,
          d.delegatorPublicKey,
          serverPubKeyBytes,
        );
        log(
          "[+] Verified delegation ${d.delegateePublicKey} in ${itemSw.elapsedMilliseconds}ms",
        );
        if (isValid) return d;
        return null;
      }),
    );
    for (final d in results) {
      processed++;
      if (d != null) {
        validDelegations.add(d);
        adminTrustedKeys.add(d.delegateePublicKey);
      }
    }
    reportProgress();
    sendBatchIfNeeded();
  }
  log("[*] Delegations processed in ${isolateStopwatch.elapsedMilliseconds}ms");
  isolateStopwatch.reset();

  // Process revocations
  for (
    var i = 0;
    i < payload.revokedDelegations.length;
    i += _verifyBatchSize
  ) {
    final chunk = payload.revokedDelegations.skip(i).take(_verifyBatchSize);
    final results = await Future.wait(
      chunk.map((r) async {
        final itemSw = Stopwatch()..start();
        final existingTs = revocationTimestamps[r.delegateePublicKey] ?? 0;
        if (r.timestamp.toInt() <= existingTs) return null;
        final isValid = await verifyRevocationLogic(
          r.delegateePublicKey,
          r.timestamp.toInt(),
          r.signature,
          r.delegatorPublicKey,
          serverPubKeyBytes,
        );
        log(
          "[+] Verified revocation ${r.delegateePublicKey} in ${itemSw.elapsedMilliseconds}ms",
        );
        if (isValid) return r;
        return null;
      }),
    );
    for (final r in results) {
      processed++;
      if (r != null) {
        validRevocations.add(r);
        revokedKeys.add(r.delegateePublicKey);
      }
    }
    reportProgress();
    sendBatchIfNeeded();
  }
  log("[*] Revocations processed in ${isolateStopwatch.elapsedMilliseconds}ms");
  isolateStopwatch.reset();

  // Process markers
  for (var i = 0; i < payload.markers.length; i += _verifyBatchSize) {
    final chunk = payload.markers.skip(i).take(_verifyBatchSize);
    final results = await Future.wait(
      chunk.map((m) async {
        final itemSw = Stopwatch()..start();
        if (deletedIds.contains(m.id)) return null;
        final existingTs = markerTimestamps[m.id] ?? 0;
        if (m.timestamp.toInt() <= existingTs) return null;

        final imageIdStr = m.imageId.isEmpty ? "" : m.imageId;
        final expiresAtStr = m.expiresAt == 0 ? "" : m.expiresAt.toString();
        final isCriticalStr = m.isCritical ? "1" : "0";
        final payloadToSign = utf8.encode(
          '${m.id}${m.latitude}${m.longitude}${m.type}${m.description}${m.timestamp}$imageIdStr$expiresAtStr$isCriticalStr',
        );
        final trustTier = await verifyDataLogic(
          payloadToSign,
          m.signature,
          m.senderId,
          serverPubKeyBytes,
          trustedKeys,
          adminTrustedKeys,
          untrustedKeys,
        );
        log(
          "[+] Verified Ed25519 signature for marker ${m.id} in ${itemSw.elapsedMilliseconds}ms",
        );
        if (trustTier != 5) return MapEntry(m, trustTier);
        return null;
      }),
    );
    for (final res in results) {
      processed++;
      if (res != null) {
        validMarkers.add(res.key);
        markerTrustTiers[res.key.id] = res.value;
      }
    }
    reportProgress();
    sendBatchIfNeeded();
  }
  log("[*] Markers processed in ${isolateStopwatch.elapsedMilliseconds}ms");
  isolateStopwatch.reset();

  // Process news
  for (var i = 0; i < payload.news.length; i += _verifyBatchSize) {
    final chunk = payload.news.skip(i).take(_verifyBatchSize);
    final results = await Future.wait(
      chunk.map((n) async {
        final itemSw = Stopwatch()..start();
        if (deletedIds.contains(n.id)) return null;
        final existingTs = newsTimestamps[n.id] ?? 0;
        if (n.timestamp.toInt() <= existingTs) return null;

        final imageIdStr = n.imageId.isEmpty ? "" : n.imageId;
        final expiresAtStr = n.expiresAt == 0 ? "" : n.expiresAt.toString();
        final isCriticalStr = n.isCritical ? "1" : "0";
        final payloadToSign = utf8.encode(
          '${n.id}${n.title}${n.content}${n.timestamp}$imageIdStr$expiresAtStr$isCriticalStr',
        );
        final trustTier = await verifyDataLogic(
          payloadToSign,
          n.signature,
          n.senderId,
          serverPubKeyBytes,
          trustedKeys,
          adminTrustedKeys,
          untrustedKeys,
        );
        log(
          "[+] Verified Ed25519 signature for news ${n.id} in ${itemSw.elapsedMilliseconds}ms",
        );
        if (trustTier != 5) return MapEntry(n, trustTier);
        return null;
      }),
    );
    for (final res in results) {
      processed++;
      if (res != null) {
        validNews.add(res.key);
        newsTrustTiers[res.key.id] = res.value;
      }
    }
    reportProgress();
    sendBatchIfNeeded();
  }
  log("[*] News processed in ${isolateStopwatch.elapsedMilliseconds}ms");
  isolateStopwatch.reset();

  // Process profiles
  for (var i = 0; i < payload.profiles.length; i += _verifyBatchSize) {
    final chunk = payload.profiles.skip(i).take(_verifyBatchSize);
    final results = await Future.wait(
      chunk.map((p) async {
        final itemSw = Stopwatch()..start();
        final existingTs = profileTimestamps[p.publicKey] ?? 0;
        if (p.timestamp.toInt() <= existingTs) return null;

        final payloadToSign = utf8.encode(
          '${p.publicKey}${p.name}${p.contactInfo}${p.timestamp}',
        );
        final trustTier = await verifyDataLogic(
          payloadToSign,
          p.signature,
          p.publicKey,
          serverPubKeyBytes,
          trustedKeys,
          adminTrustedKeys,
          untrustedKeys,
        );
        log(
          "[+] Verified Ed25519 signature for profile ${p.publicKey} in ${itemSw.elapsedMilliseconds}ms",
        );
        if (trustTier != 5) return p;
        return null;
      }),
    );
    for (final p in results) {
      processed++;
      if (p != null) validProfiles.add(p);
    }
    reportProgress();
    sendBatchIfNeeded();
  }
  log("[*] Profiles processed in ${isolateStopwatch.elapsedMilliseconds}ms");
  isolateStopwatch.reset();

  // Process areas
  for (var i = 0; i < payload.areas.length; i += _verifyBatchSize) {
    final chunk = payload.areas.skip(i).take(_verifyBatchSize);
    final results = await Future.wait(
      chunk.map((a) async {
        final itemSw = Stopwatch()..start();
        if (deletedIds.contains(a.id)) return null;
        final existingTs = areaTimestamps[a.id] ?? 0;
        if (a.timestamp.toInt() <= existingTs) return null;

        final expiresAtStr = a.expiresAt == 0 ? "" : a.expiresAt.toString();
        final isCriticalStr = a.isCritical ? "1" : "0";
        final coordsStr = a.coordinates
            .map((c) => '${c.latitude},${c.longitude}')
            .join('|');
        final payloadToSign = utf8.encode(
          '${a.id}$coordsStr${a.type}${a.description}${a.timestamp}$expiresAtStr$isCriticalStr',
        );
        final trustTier = await verifyDataLogic(
          payloadToSign,
          a.signature,
          a.senderId,
          serverPubKeyBytes,
          trustedKeys,
          adminTrustedKeys,
          untrustedKeys,
        );
        log(
          "[+] Verified Ed25519 signature for area ${a.id} in ${itemSw.elapsedMilliseconds}ms",
        );
        if (trustTier != 5) return MapEntry(a, trustTier);
        return null;
      }),
    );
    for (final res in results) {
      processed++;
      if (res != null) {
        validAreas.add(res.key);
        areaTrustTiers[res.key.id] = res.value;
      }
    }
    reportProgress();
    sendBatchIfNeeded();
  }
  log("[*] Areas processed in ${isolateStopwatch.elapsedMilliseconds}ms");
  isolateStopwatch.reset();

  // Process paths
  for (var i = 0; i < payload.paths.length; i += _verifyBatchSize) {
    final chunk = payload.paths.skip(i).take(_verifyBatchSize);
    final results = await Future.wait(
      chunk.map((p) async {
        final itemSw = Stopwatch()..start();
        if (deletedIds.contains(p.id)) return null;
        final existingTs = pathTimestamps[p.id] ?? 0;
        if (p.timestamp.toInt() <= existingTs) return null;

        final expiresAtStr = p.expiresAt == 0 ? "" : p.expiresAt.toString();
        final isCriticalStr = p.isCritical ? "1" : "0";
        final coordsStr = p.coordinates
            .map((c) => '${c.latitude},${c.longitude}')
            .join('|');
        final payloadToSign = utf8.encode(
          '${p.id}$coordsStr${p.type}${p.description}${p.timestamp}$expiresAtStr$isCriticalStr',
        );
        final trustTier = await verifyDataLogic(
          payloadToSign,
          p.signature,
          p.senderId,
          serverPubKeyBytes,
          trustedKeys,
          adminTrustedKeys,
          untrustedKeys,
        );
        log(
          "[+] Verified Ed25519 signature for path ${p.id} in ${itemSw.elapsedMilliseconds}ms",
        );
        if (trustTier != 5) return MapEntry(p, trustTier);
        return null;
      }),
    );
    for (final res in results) {
      processed++;
      if (res != null) {
        validPaths.add(res.key);
        pathTrustTiers[res.key.id] = res.value;
      }
    }
    reportProgress();
    sendBatchIfNeeded();
  }
  log("[*] Paths processed in ${isolateStopwatch.elapsedMilliseconds}ms");
  isolateStopwatch.reset();

  sendBatchIfNeeded(force: true);
  if (sendPort != null) {
    sendPort.send({'type': 'done'});
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
        terminalLog("[*] Set Bluetooth Name to: $prefix: $safeName");
      }
    } catch (e) {
      terminalLog("[-] Failed to set BT name: $e");
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
      terminalLog("[-] Failed to restore BT name: $e");
    }
  }

  Future<void> _incrementHeroStat(String key, int amount) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final current = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, current + amount);

    if (isBackgroundIsolate) {
      bgServiceInstance?.invoke('reloadHeroStats');
    } else {
      try {
        FlutterBackgroundService().invoke('reloadHeroStats');
      } catch (_) {}
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
    terminalLog("[*] Initializing P2P Host and Client...");
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
      terminalLog(
        "[+] Host state updated: isActive=${hotspotState.isActive}, ssid=${hotspotState.ssid}",
      );
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
      terminalLog("[+] Host client list updated. Count: ${clients.length}");
      if (clients.length > previousCount) {
        _incrementHeroStat('hero_peers_synced', clients.length - previousCount);
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
      terminalLog(
        "[+] Client state updated: isActive=${hotspotState.isActive}, hostSsid=${hotspotState.hostSsid}",
      );
      state = state.copyWith(
        clientState: AppClientState(
          isActive: hotspotState.isActive,
          hostSsid: hotspotState.hostSsid,
          hostGatewayIpAddress: hotspotState.hostGatewayIpAddress,
          hostIpAddress: hotspotState.hostIpAddress,
        ),
      );
      if (!wasActive && hotspotState.isActive) {
        _incrementHeroStat('hero_peers_synced', 1);
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
    terminalLog(
      "[*] Toggling Auto-Sync. Current state: ${state.isAutoSyncing}",
    );
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
    terminalLog("[*] Running Auto-Sync cycle. Idle ticks: $_idleTicks");

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
        terminalLog(
          "[-] Idle timeout reached while connected. Forcing role switch to find new peers.",
        );
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
        terminalLog("[*] Auto-Sync: Switching to Scanner role...");
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
        terminalLog("[*] Auto-Sync: Switching to Broadcaster role...");
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

      int batteryMultiplier = 1;
      try {
        final battery = Battery();
        final isPowerSave = await battery.isInBatterySaveMode;
        final level = await battery.batteryLevel;
        if (isPowerSave) {
          batteryMultiplier = 4;
        } else if (level < 20) {
          batteryMultiplier = 3;
        } else if (level < 50) {
          batteryMultiplier = 2;
        }
      } catch (_) {}

      // Large jitter to prevent perfect sync loops between two devices.
      int nextCycleSeconds =
          (baseInterval * batteryMultiplier) + Random().nextInt(20);

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
    terminalLog("[*] Starting Host mode...");
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
        terminalLog("[*] Removing existing group before creating new one...");
        await _host.removeGroup();
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        terminalLog("[-] Error removing existing group before hosting: $e");
      }

      await _host.createGroup(advertise: true);
      if (!state.isHosting || _disposed) {
        await _host.removeGroup();
      } else {
        _hostTextSub?.cancel();
        _hostTextSub = _host.streamReceivedTexts().listen(_handleReceivedText);
      }
    } catch (e) {
      terminalLog("[-] Failed to create group: $e");
      state = state.copyWith(
        syncMessage: 'Failed to start host: $e',
        clearSyncProgress: true,
      );
      await stopHosting();
    }
  }

  Future<void> stopHosting() async {
    _hostTextSub?.cancel();
    terminalLog("[-] Stopping Host mode...");
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
    terminalLog("[*] Starting Scanner mode...");
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
      } catch (e) {
        terminalLog("[-] Timeout waiting for Bluetooth to turn on: $e");
      }

      await FlutterBluePlus.startScan(
        withServices: [Guid(_floodioServiceUuid)],
        timeout: const Duration(seconds: 30),
      );

      _scanSub = FlutterBluePlus.onScanResults.listen((results) {
        terminalLog("[+] BLE Scan results: ${results.length} devices found.");
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
          terminalLog(
            "[+] Auto-Sync: Found device, attempting connection to ${appDevices.first.deviceAddress}",
          );
          connectToDeviceByAddress(appDevices.first.deviceAddress);
        }
      });

      if (!state.isScanning || _disposed) {
        await stopScanning();
      }
    } catch (e) {
      terminalLog("[-] Failed to start scan: $e");
      state = state.copyWith(
        isScanning: false,
        syncMessage: 'Scan failed: $e',
        clearSyncProgress: true,
      );
    }
  }

  Future<void> connectToDeviceByAddress(String address) async {
    if (!_isInitialized || state.isConnecting) return;
    terminalLog("[*] Attempting to connect to BLE device: $address");
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
      terminalLog("[-] Connection failed: $e");
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
    terminalLog("[-] Stopping BLE scan...");
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      terminalLog("[-] Error stopping FlutterBluePlus scan: $e");
    }
    if (_isInitialized) {
      await _client.stopScan();
    }
    state = state.copyWith(isScanning: false);
  }

  Future<void> disconnect() async {
    terminalLog("[-] Disconnecting client...");
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
    terminalLog("[+] Received text message. Length: ${text.length}");
    try {
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) {
        if (json['type'] == 'manifest') {
          terminalLog("[*] Message type: manifest");
          await _handleManifest(json);
          return;
        } else if (json['type'] == 'payload') {
          terminalLog("[*] Message type: payload");
          await processPayload(json['data']);
          return;
        } else if (json['type'] == 'request_map') {
          terminalLog("[*] Message type: request_map");
          await _handleRequestMap(json);
          return;
        } else if (json['type'] == 'request_image') {
          terminalLog("[*] Message type: request_image");
          await _handleRequestImage(json['imageId']);
          return;
        } else if (json['type'] == 'up_to_date') {
          terminalLog("[+] Message type: up_to_date");
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
      terminalLog("[-] Failed to decode JSON or handle text: $e");
    }

    state = state.copyWith(receivedTexts: [...state.receivedTexts, text]);
  }

  Future<void> _handleRequestImage(String imageId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$imageId');
      if (await file.exists()) {
        terminalLog("[+] Fulfilling image request for $imageId");
        await broadcastFile(file);
      }
    } catch (e) {
      terminalLog("[-] Error handling request_image: $e");
    }
  }

  void _handleReceivedFiles(
    List<ReceivableFileInfo> files,
    dynamic p2pInstance,
  ) async {
    bool isDownloadingAny = false;
    for (final file in files) {
      if (file.state == ReceivableFileState.idle) {
        terminalLog("[*] Starting download for file: ${file.info.name}");
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
        terminalLog("[+] Download completed for file: ${file.info.name}");
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
                } catch (e, st) {
                  terminalLog(
                    "[-] Failed to parse region from map filename: $e",
                  );
                  terminalLog("[-] Stacktrace: $st");
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
              terminalLog("[-] Error unpacking map: $e");
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
        terminalLog("[-] Failed to download file ${file.info.name}");
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
    terminalLog("[*] Generating and sending manifest...");
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

      terminalLog(
        "[+] Manifest generated. Bloom size: $bloomSize. Broadcasting...",
      );
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
      terminalLog("[-] Error sending manifest: $e");
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Error sending sync data.',
        clearSyncProgress: true,
      );
    }
  }

  Future<void> _handleManifest(Map<String, dynamic> json) async {
    _idleTicks = 0;
    terminalLog("[*] Handling received manifest...");
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
        terminalLog("[+] No new data to send. Sending up_to_date.");
        await broadcastText(jsonEncode({'type': 'up_to_date'}));
        state = state.copyWith(
          isSyncing: false,
          lastSyncTime: DateTime.now(),
          syncMessage: 'Up to date.',
          clearSyncProgress: true,
        );
        return;
      }

      final summary =
          'Sent ${newHazards.length} markers, ${newNews.length} news, ${newProfiles.length} profiles, ${newAreas.length} areas, ${newPaths.length} paths, ${newDeleted.length} deletions, ${newDelegations.length} delegations, ${newRevocations.length} revocations.';
      terminalLog(
        "[+] Preparing payload with ${newHazards.length} markers, ${newNews.length} news...",
      );
      state = state.copyWith(
        syncMessage:
            'Sending ${newHazards.length} markers, ${newNews.length} news, ${newProfiles.length} profiles, ${newAreas.length} areas, ${newPaths.length} paths, ${newDeleted.length} deletions, ${newDelegations.length} delegations, ${newRevocations.length} revocations...',
        lastSyncSummary: summary,
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

      final encoded = await Isolate.run(
        () => base64Encode(payload.writeToBuffer()),
      );
      await broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));
      state = state.copyWith(
        syncMessage: 'Data sent successfully.',
        clearSyncProgress: true,
      );
    } catch (e) {
      terminalLog("[-] Error handling manifest: $e");
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
    terminalLog("[*] Packing and broadcasting map region...");
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
        lastSyncSummary: 'Sent offline map region.',
        clearSyncProgress: true,
      );
    } catch (e) {
      terminalLog("[-] Error sending map: $e");
      state = state.copyWith(
        isSyncing: false,
        syncMessage: 'Error sending map.',
        clearSyncProgress: true,
      );
    }
  }

  Future<void> processPayloadFromFile(String filePath) async {
    final stopwatch = Stopwatch()..start();
    _idleTicks = 0;
    terminalLog("[*] Processing payload from file: $filePath");
    state = state.copyWith(
      isSyncing: true,
      syncMessage: 'Receiving cloud data...',
      clearSyncProgress: true,
    );
    bool success = false;
    try {
      final file = File(filePath);
      final data = await file.readAsBytes();
      await file.delete(); // Clean up

      state = state.copyWith(
        syncMessage: 'Decoding payload...',
        clearSyncProgress: true,
      );
      _incrementHeroStat('hero_data_carried', data.length);

      final payload = await Isolate.run(() => pb.SyncPayload.fromBuffer(data));
      terminalLog("[+] Payload decoded in ${stopwatch.elapsedMilliseconds}ms");

      stopwatch.reset();
      await _processDecodedPayload(payload, isFromCloud: true);
      success = true;
    } catch (e) {
      terminalLog("[-] Error handling payload from file: $e");
      state = state.copyWith(
        syncMessage: 'Error syncing data.',
        clearSyncProgress: true,
      );
    } finally {
      state = state.copyWith(isSyncing: false, clearSyncProgress: true);
      if (isBackgroundIsolate) {
        bgServiceInstance?.invoke('processPayloadComplete', {
          'success': success,
        });
      }
      terminalLog(
        "[+] processPayloadFromFile completed in ${stopwatch.elapsedMilliseconds}ms",
      );
    }
  }

  Future<void> processPayload(String base64Data) async {
    final stopwatch = Stopwatch()..start();
    _idleTicks = 0;
    terminalLog("[*] Processing base64 payload...");
    state = state.copyWith(
      isSyncing: true,
      syncMessage: 'Receiving data...',
      clearSyncProgress: true,
    );
    try {
      state = state.copyWith(
        syncMessage: 'Decoding payload...',
        clearSyncProgress: true,
      );
      final data = await Isolate.run(() => base64Decode(base64Data));
      _incrementHeroStat('hero_data_carried', data.length);

      final payload = await Isolate.run(() => pb.SyncPayload.fromBuffer(data));
      terminalLog("[+] Payload decoded in ${stopwatch.elapsedMilliseconds}ms");

      stopwatch.reset();
      await _processDecodedPayload(payload, isFromCloud: false);
    } catch (e) {
      terminalLog("[-] Error handling payload: $e");
      state = state.copyWith(
        syncMessage: 'Error syncing data.',
        clearSyncProgress: true,
      );
    } finally {
      state = state.copyWith(isSyncing: false, clearSyncProgress: true);
      terminalLog(
        "[+] processPayload completed in ${stopwatch.elapsedMilliseconds}ms",
      );
    }
  }

  Future<void> _processDecodedPayload(
    pb.SyncPayload payload, {
    required bool isFromCloud,
  }) async {
    final processStopwatch = Stopwatch()..start();

    // Deduplicate payload items to prevent redundant signature verification
    final uniqueMarkers = <String, pb.HazardMarker>{};
    for (final m in payload.markers) {
      final existing = uniqueMarkers[m.id];
      if (existing == null || m.timestamp > existing.timestamp) {
        uniqueMarkers[m.id] = m;
      }
    }
    payload.markers.clear();
    payload.markers.addAll(uniqueMarkers.values);

    final uniqueNews = <String, pb.NewsItem>{};
    for (final n in payload.news) {
      final existing = uniqueNews[n.id];
      if (existing == null || n.timestamp > existing.timestamp) {
        uniqueNews[n.id] = n;
      }
    }
    payload.news.clear();
    payload.news.addAll(uniqueNews.values);

    final uniqueProfiles = <String, pb.UserProfile>{};
    for (final p in payload.profiles) {
      final existing = uniqueProfiles[p.publicKey];
      if (existing == null || p.timestamp > existing.timestamp) {
        uniqueProfiles[p.publicKey] = p;
      }
    }
    payload.profiles.clear();
    payload.profiles.addAll(uniqueProfiles.values);

    final uniqueAreas = <String, pb.AreaMarker>{};
    for (final a in payload.areas) {
      final existing = uniqueAreas[a.id];
      if (existing == null || a.timestamp > existing.timestamp) {
        uniqueAreas[a.id] = a;
      }
    }
    payload.areas.clear();
    payload.areas.addAll(uniqueAreas.values);

    final uniquePaths = <String, pb.PathMarker>{};
    for (final p in payload.paths) {
      final existing = uniquePaths[p.id];
      if (existing == null || p.timestamp > existing.timestamp) {
        uniquePaths[p.id] = p;
      }
    }
    payload.paths.clear();
    payload.paths.addAll(uniquePaths.values);

    final uniqueDelegations = <String, pb.TrustDelegation>{};
    for (final d in payload.delegations) {
      final existing = uniqueDelegations[d.delegateePublicKey];
      if (existing == null || d.timestamp > existing.timestamp) {
        uniqueDelegations[d.delegateePublicKey] = d;
      }
    }
    payload.delegations.clear();
    payload.delegations.addAll(uniqueDelegations.values);

    final uniqueRevocations = <String, pb.RevokedDelegation>{};
    for (final r in payload.revokedDelegations) {
      final existing = uniqueRevocations[r.delegateePublicKey];
      if (existing == null || r.timestamp > existing.timestamp) {
        uniqueRevocations[r.delegateePublicKey] = r;
      }
    }
    payload.revokedDelegations.clear();
    payload.revokedDelegations.addAll(uniqueRevocations.values);

    final uniqueDeleted = <String, pb.DeletedItem>{};
    for (final d in payload.deletedItems) {
      final existing = uniqueDeleted[d.id];
      if (existing == null || d.timestamp > existing.timestamp) {
        uniqueDeleted[d.id] = d;
      }
    }
    payload.deletedItems.clear();
    payload.deletedItems.addAll(uniqueDeleted.values);

    if (payload.markers.isEmpty &&
        payload.news.isEmpty &&
        payload.profiles.isEmpty &&
        payload.deletedItems.isEmpty &&
        payload.areas.isEmpty &&
        payload.paths.isEmpty &&
        payload.delegations.isEmpty &&
        payload.revokedDelegations.isEmpty) {
      terminalLog("[-] Decoded payload is empty.");
      state = state.copyWith(
        syncMessage: 'Empty payload received.',
        clearSyncProgress: true,
      );
      return;
    }

    terminalLog("[*] Decoded payload contains items. Verifying signatures...");
    state = state.copyWith(
      syncMessage: 'Preparing to verify signatures...',
      clearSyncProgress: true,
    );

    final db = ref.read(databaseProvider);
    await ref.read(cryptoServiceProvider.future);
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

    // Fetch existing timestamps for LWW CRDT resolution (optimized with chunked isIn)
    final markerTimestamps = <String, int>{};
    final payloadMarkerIds = payload.markers.map((m) => m.id).toList();
    for (var i = 0; i < payloadMarkerIds.length; i += 900) {
      final chunk = payloadMarkerIds.skip(i).take(900).toList();
      final existing =
          await (db.selectOnly(db.hazardMarkers)
                ..addColumns([db.hazardMarkers.id, db.hazardMarkers.timestamp])
                ..where(db.hazardMarkers.id.isIn(chunk)))
              .get();
      for (final m in existing) {
        markerTimestamps[m.read(db.hazardMarkers.id)!] = m.read(
          db.hazardMarkers.timestamp,
        )!;
      }
    }

    final newsTimestamps = <String, int>{};
    final payloadNewsIds = payload.news.map((n) => n.id).toList();
    for (var i = 0; i < payloadNewsIds.length; i += 900) {
      final chunk = payloadNewsIds.skip(i).take(900).toList();
      final existing =
          await (db.selectOnly(db.newsItems)
                ..addColumns([db.newsItems.id, db.newsItems.timestamp])
                ..where(db.newsItems.id.isIn(chunk)))
              .get();
      for (final n in existing) {
        newsTimestamps[n.read(db.newsItems.id)!] = n.read(
          db.newsItems.timestamp,
        )!;
      }
    }

    final profileTimestamps = <String, int>{};
    final payloadProfileKeys = payload.profiles
        .map((p) => p.publicKey)
        .toList();
    for (var i = 0; i < payloadProfileKeys.length; i += 900) {
      final chunk = payloadProfileKeys.skip(i).take(900).toList();
      final existing =
          await (db.selectOnly(db.userProfiles)
                ..addColumns([
                  db.userProfiles.publicKey,
                  db.userProfiles.timestamp,
                ])
                ..where(db.userProfiles.publicKey.isIn(chunk)))
              .get();
      for (final p in existing) {
        profileTimestamps[p.read(db.userProfiles.publicKey)!] = p.read(
          db.userProfiles.timestamp,
        )!;
      }
    }

    final areaTimestamps = <String, int>{};
    final payloadAreaIds = payload.areas.map((a) => a.id).toList();
    for (var i = 0; i < payloadAreaIds.length; i += 900) {
      final chunk = payloadAreaIds.skip(i).take(900).toList();
      final existing =
          await (db.selectOnly(db.areas)
                ..addColumns([db.areas.id, db.areas.timestamp])
                ..where(db.areas.id.isIn(chunk)))
              .get();
      for (final a in existing) {
        areaTimestamps[a.read(db.areas.id)!] = a.read(db.areas.timestamp)!;
      }
    }

    final pathTimestamps = <String, int>{};
    final payloadPathIds = payload.paths.map((p) => p.id).toList();
    for (var i = 0; i < payloadPathIds.length; i += 900) {
      final chunk = payloadPathIds.skip(i).take(900).toList();
      final existing =
          await (db.selectOnly(db.paths)
                ..addColumns([db.paths.id, db.paths.timestamp])
                ..where(db.paths.id.isIn(chunk)))
              .get();
      for (final p in existing) {
        pathTimestamps[p.read(db.paths.id)!] = p.read(db.paths.timestamp)!;
      }
    }

    final existingDeletedIds = deletedIds.toSet();
    final validDeleted = <DeletedItemsCompanion>[];
    final seenIds = <SeenMessageIdsCompanion>[];

    for (final d in payload.deletedItems) {
      deletedIds.add(d.id);
      if (!existingDeletedIds.contains(d.id)) {
        validDeleted.add(
          DeletedItemsCompanion.insert(
            id: d.id,
            timestamp: d.timestamp.toInt(),
            uploadedToCloud: Value(isFromCloud),
          ),
        );
        seenIds.add(
          SeenMessageIdsCompanion.insert(
            messageId: 'del_${d.id}_${d.timestamp}',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            uploadedToCloud: Value(isFromCloud),
          ),
        );
      }
    }

    // Insert deleted items immediately
    if (validDeleted.isNotEmpty || seenIds.isNotEmpty) {
      await db.batch((batch) {
        batch.insertAll(
          db.deletedItems,
          validDeleted,
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          db.seenMessageIds,
          seenIds,
          mode: InsertMode.insertOrReplace,
        );
      });
    }

    terminalLog(
      "[+] DB queries for existing timestamps took ${processStopwatch.elapsedMilliseconds}ms",
    );
    processStopwatch.reset();

    state = state.copyWith(
      syncMessage: 'Verifying signatures in background...',
      syncProgress: 0.0,
    );

    final myPubKeyStr = await crypto.getPublicKeyString();
    final effectiveTrustedKeys = [...trustedKeys, myPubKeyStr];
    final effectiveAdminKeys = adminTrustedKeys
        .where((k) => !revokedKeys.contains(k))
        .toList();

    final args = {
      'payload': payload,
      'trustedKeys': effectiveTrustedKeys,
      'adminTrustedKeys': effectiveAdminKeys,
      'untrustedKeys': untrustedKeys,
      'revokedKeys': revokedKeys,
      'serverPubKeyBytes': crypto.serverPublicKeyBytes,
      'deletedIds': deletedIds,
      'markerTimestamps': markerTimestamps,
      'newsTimestamps': newsTimestamps,
      'profileTimestamps': profileTimestamps,
      'areaTimestamps': areaTimestamps,
      'pathTimestamps': pathTimestamps,
      'delegationTimestamps': delegationTimestamps,
      'revocationTimestamps': revocationTimestamps,
    };

    // Accumulate all valid items to forward later
    final allValidMarkersPb = <pb.HazardMarker>[];
    final allValidNewsPb = <pb.NewsItem>[];
    final allValidProfilesPb = <pb.UserProfile>[];
    final allValidAreasPb = <pb.AreaMarker>[];
    final allValidPathsPb = <pb.PathMarker>[];
    final allValidDelegationsPb = <pb.TrustDelegation>[];
    final allValidRevocationsPb = <pb.RevokedDelegation>[];

    await _runVerifyPayloadInIsolate(
      args,
      (progress) {
        state = state.copyWith(
          syncMessage: 'Verifying signatures...',
          syncProgress: progress,
        );
      },
      (batchData) async {
        // Process batch
        final batchStopwatch = Stopwatch()..start();
        final validMarkersPb =
            batchData['validMarkers'] as List<pb.HazardMarker>;
        final validNewsPb = batchData['validNews'] as List<pb.NewsItem>;
        final validProfilesPb =
            batchData['validProfiles'] as List<pb.UserProfile>;
        final validAreasPb = batchData['validAreas'] as List<pb.AreaMarker>;
        final validPathsPb = batchData['validPaths'] as List<pb.PathMarker>;
        final validDelegationsPb =
            batchData['validDelegations'] as List<pb.TrustDelegation>;
        final validRevocationsPb =
            batchData['validRevocations'] as List<pb.RevokedDelegation>;

        final markerTrustTiers =
            batchData['markerTrustTiers'] as Map<String, int>;
        final newsTrustTiers = batchData['newsTrustTiers'] as Map<String, int>;
        final areaTrustTiers = batchData['areaTrustTiers'] as Map<String, int>;
        final pathTrustTiers = batchData['pathTrustTiers'] as Map<String, int>;

        allValidMarkersPb.addAll(validMarkersPb);
        allValidNewsPb.addAll(validNewsPb);
        allValidProfilesPb.addAll(validProfilesPb);
        allValidAreasPb.addAll(validAreasPb);
        allValidPathsPb.addAll(validPathsPb);
        allValidDelegationsPb.addAll(validDelegationsPb);
        allValidRevocationsPb.addAll(validRevocationsPb);

        final batchSeenIds = <SeenMessageIdsCompanion>[];
        final validDelegations = <AdminTrustedSendersCompanion>[];
        for (final d in validDelegationsPb) {
          validDelegations.add(
            AdminTrustedSendersCompanion.insert(
              publicKey: d.delegateePublicKey,
              delegatorPublicKey: d.delegatorPublicKey,
              timestamp: d.timestamp.toInt(),
              signature: d.signature,
            ),
          );
          batchSeenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: 'delg_${d.delegateePublicKey}_${d.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              uploadedToCloud: Value(isFromCloud),
            ),
          );
        }

        final validRevocations = <RevokedDelegationsCompanion>[];
        for (final r in validRevocationsPb) {
          validRevocations.add(
            RevokedDelegationsCompanion.insert(
              delegateePublicKey: r.delegateePublicKey,
              delegatorPublicKey: r.delegatorPublicKey,
              timestamp: r.timestamp.toInt(),
              signature: r.signature,
            ),
          );
          batchSeenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: 'rev_${r.delegateePublicKey}_${r.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              uploadedToCloud: Value(isFromCloud),
            ),
          );
        }

        final validMarkers = <HazardMarkersCompanion>[];
        for (final m in validMarkersPb) {
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
              trustTier: markerTrustTiers[m.id]!,
              imageId: Value(m.imageId.isEmpty ? null : m.imageId),
              expiresAt: Value(m.expiresAt == 0 ? null : m.expiresAt.toInt()),
              isCritical: Value(m.isCritical),
            ),
          );
          batchSeenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${m.id}_${m.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              uploadedToCloud: Value(isFromCloud),
            ),
          );
        }

        final validNews = <NewsItemsCompanion>[];
        for (final n in validNewsPb) {
          validNews.add(
            NewsItemsCompanion.insert(
              id: n.id,
              title: n.title,
              content: n.content,
              timestamp: n.timestamp.toInt(),
              senderId: n.senderId,
              signature: Value(n.signature),
              trustTier: newsTrustTiers[n.id]!,
              expiresAt: Value(n.expiresAt == 0 ? null : n.expiresAt.toInt()),
              imageId: Value(n.imageId.isEmpty ? null : n.imageId),
              isCritical: Value(n.isCritical),
            ),
          );
          batchSeenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${n.id}_${n.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              uploadedToCloud: Value(isFromCloud),
            ),
          );
        }

        final validProfiles = <UserProfilesCompanion>[];
        for (final p in validProfilesPb) {
          validProfiles.add(
            UserProfilesCompanion.insert(
              publicKey: p.publicKey,
              name: p.name,
              contactInfo: p.contactInfo,
              timestamp: p.timestamp.toInt(),
              signature: p.signature,
            ),
          );
          batchSeenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${p.publicKey}_${p.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              uploadedToCloud: Value(isFromCloud),
            ),
          );
        }

        final validAreas = <AreasCompanion>[];
        for (final a in validAreasPb) {
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
              trustTier: areaTrustTiers[a.id]!,
              expiresAt: Value(a.expiresAt == 0 ? null : a.expiresAt.toInt()),
              isCritical: Value(a.isCritical),
            ),
          );
          batchSeenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${a.id}_${a.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              uploadedToCloud: Value(isFromCloud),
            ),
          );
        }

        final validPaths = <PathsCompanion>[];
        for (final p in validPathsPb) {
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
              trustTier: pathTrustTiers[p.id]!,
              expiresAt: Value(p.expiresAt == 0 ? null : p.expiresAt.toInt()),
              isCritical: Value(p.isCritical),
            ),
          );
          batchSeenIds.add(
            SeenMessageIdsCompanion.insert(
              messageId: '${p.id}_${p.timestamp}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
              uploadedToCloud: Value(isFromCloud),
            ),
          );
        }

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
          batch.insertAll(
            db.areas,
            validAreas,
            mode: InsertMode.insertOrReplace,
          );
          batch.insertAll(
            db.paths,
            validPaths,
            mode: InsertMode.insertOrReplace,
          );
          batch.insertAll(
            db.seenMessageIds,
            batchSeenIds,
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

        // Update trust tiers for delegations/revocations in this batch
        await db.transaction(() async {
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
            final fallbackTier =
                trustedKeys.contains(r.delegateePublicKey.value) ? 3 : 4;
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
        terminalLog(
          "[+] Batch processed and saved to DB in ${batchStopwatch.elapsedMilliseconds}ms",
        );
      },
    );

    terminalLog(
      "[+] Isolate verification completed in ${processStopwatch.elapsedMilliseconds}ms",
    );
    processStopwatch.reset();

    state = state.copyWith(
      syncMessage: 'Cleaning up old records...',
      clearSyncProgress: true,
    );

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
        await (db.delete(db.areas)..where((t) => t.id.equals(d.id.value))).go();
        await (db.delete(db.paths)..where((t) => t.id.equals(d.id.value))).go();
      }
    });

    state = state.copyWith(
      syncMessage: 'Requesting missing images...',
      clearSyncProgress: true,
    );

    // Request missing images
    for (final m in allValidMarkersPb) {
      final imageId = m.imageId;
      if (imageId.isNotEmpty) {
        final file = File('${dir.path}/$imageId');
        if (!await file.exists()) {
          bool downloaded = false;
          try {
            final bytes = await Supabase.instance.client.storage
                .from('images')
                .download(imageId)
                .timeout(const Duration(seconds: 15));
            await file.writeAsBytes(bytes);
            downloaded = true;
          } catch (e) {
            terminalLog("[-] Failed to download image $imageId from cloud: $e");
          }

          if (!downloaded && !isFromCloud) {
            await broadcastText(
              jsonEncode({'type': 'request_image', 'imageId': imageId}),
            );
          }
        }
      }
    }
    for (final n in allValidNewsPb) {
      final imageId = n.imageId;
      if (imageId.isNotEmpty) {
        final file = File('${dir.path}/$imageId');
        if (!await file.exists()) {
          bool downloaded = false;
          try {
            final bytes = await Supabase.instance.client.storage
                .from('images')
                .download(imageId)
                .timeout(const Duration(seconds: 15));
            await file.writeAsBytes(bytes);
            downloaded = true;
          } catch (e) {
            terminalLog("[-] Failed to download image $imageId from cloud: $e");
          }

          if (!downloaded && !isFromCloud) {
            await broadcastText(
              jsonEncode({'type': 'request_image', 'imageId': imageId}),
            );
          }
        }
      }
    }

    terminalLog(
      "[+] Cleanup and image requests took ${processStopwatch.elapsedMilliseconds}ms",
    );
    processStopwatch.reset();

    state = state.copyWith(
      syncMessage: 'Forwarding data to peers...',
      clearSyncProgress: true,
    );

    // Forward newly received and validated data to other connected peers
    final forwardPayload = pb.SyncPayload();
    bool hasNewData = false;

    for (final m in allValidMarkersPb) {
      hasNewData = true;
      forwardPayload.markers.add(m);
    }

    for (final n in allValidNewsPb) {
      hasNewData = true;
      forwardPayload.news.add(n);
    }

    for (final p in allValidProfilesPb) {
      hasNewData = true;
      forwardPayload.profiles.add(p);
    }

    for (final a in allValidAreasPb) {
      hasNewData = true;
      forwardPayload.areas.add(a);
    }

    for (final p in allValidPathsPb) {
      hasNewData = true;
      forwardPayload.paths.add(p);
    }

    for (final d in validDeleted) {
      hasNewData = true;
      forwardPayload.deletedItems.add(
        pb.DeletedItem(id: d.id.value, timestamp: Int64(d.timestamp.value)),
      );
    }

    for (final d in allValidDelegationsPb) {
      hasNewData = true;
      forwardPayload.delegations.add(d);
    }

    for (final r in allValidRevocationsPb) {
      hasNewData = true;
      forwardPayload.revokedDelegations.add(r);
    }

    if (hasNewData) {
      if (isFromCloud) {
        // If we got new data from the cloud, and we are connected to peers, forward it to them.
        if ((state.isHosting && state.connectedClients.isNotEmpty) ||
            state.clientState?.isActive == true) {
          final encoded = await _encodePayloadInIsolate(forwardPayload);
          await broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));
          int relayedCount =
              forwardPayload.markers.length +
              forwardPayload.news.length +
              forwardPayload.areas.length +
              forwardPayload.paths.length;
          _incrementHeroStat('hero_reports_relayed', relayedCount);
          _incrementHeroStat('hero_data_carried', encoded.length);
        }
      } else {
        // Prevent Echo Storm: Only forward the payload if we are a Host with MULTIPLE clients.
        if (state.isHosting && state.connectedClients.length > 1) {
          final encoded = await _encodePayloadInIsolate(forwardPayload);
          await broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));

          int relayedCount =
              forwardPayload.markers.length +
              forwardPayload.news.length +
              forwardPayload.areas.length +
              forwardPayload.paths.length;
          _incrementHeroStat('hero_reports_relayed', relayedCount);
          _incrementHeroStat('hero_data_carried', encoded.length);
        } else {
          await broadcastText(jsonEncode({'type': 'up_to_date'}));
        }
      }
    } else {
      if (!isFromCloud) {
        await broadcastText(jsonEncode({'type': 'up_to_date'}));
      }
    }

    final summary =
        'Received ${payload.markers.length} markers, ${payload.news.length} news, ${payload.profiles.length} profiles, ${payload.areas.length} areas, ${payload.paths.length} paths, ${payload.deletedItems.length} deletions, ${payload.delegations.length} delegations, ${payload.revokedDelegations.length} revocations.';
    state = state.copyWith(
      isSyncing: false,
      lastSyncTime: DateTime.now(),
      syncMessage: 'Successfully synced data.',
      lastSyncSummary: summary,
      clearSyncProgress: true,
    );
    terminalLog(
      "[+] Forwarding data took ${processStopwatch.elapsedMilliseconds}ms",
    );
    terminalLog(
      "[+] Successfully synced ${payload.markers.length} markers, ${payload.news.length} news, ${payload.profiles.length} profiles, ${payload.areas.length} areas, ${payload.paths.length} paths, ${payload.deletedItems.length} deletions, ${payload.delegations.length} delegations, ${payload.revokedDelegations.length} revocations.",
    );
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
      terminalLog("[-] Error broadcasting text: $e");
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
      terminalLog("[-] Error broadcasting file: $e");
    }
  }

  void mockDiscoveredDevice() {
    final newDevice = AppDiscoveredDevice(
      deviceAddress:
          '00:11:22:33:44:${Random().nextInt(99).toString().padLeft(2, '0')}',
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

    Position? loc;
    try {
      loc = await Geolocator.getLastKnownPosition();
    } catch (e) {
      terminalLog("[-] Error getting location for mock hazard: $e");
    }
    final lat = loc?.latitude ?? 10.7326718;
    final lng = loc?.longitude ?? 122.5482846;

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

  Future<void> mockReceivedCriticalHazard() async {
    final db = ref.read(databaseProvider);
    await ref.read(cryptoServiceProvider.future);
    final crypto = ref.read(cryptoServiceProvider.notifier);
    final myPubKey = await crypto.getPublicKeyString();

    final id = 'mock_critical_${DateTime.now().millisecondsSinceEpoch}';
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    Position? loc;
    try {
      loc = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    final lat = loc?.latitude ?? 10.730185;
    final lng = loc?.longitude ?? 122.559115;

    final newMarker = HazardMarkersCompanion.insert(
      id: id,
      latitude: lat + (Random().nextDouble() - 0.5) * 0.02,
      longitude: lng + (Random().nextDouble() - 0.5) * 0.02,
      type: 'Evacuation Zone',
      description: 'Mocked CRITICAL evacuation order from debug menu',
      timestamp: timestamp,
      senderId: myPubKey,
      signature: const Value('mock_signature'),
      trustTier: 1, // Tier 1
      isCritical: const Value(true), // Critical
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
