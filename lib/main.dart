import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'crypto/crypto_service.dart';
import 'database/tables.dart';
import 'providers/database_provider.dart';
import 'providers/hazard_marker_provider.dart';
import 'providers/p2p_provider.dart';
import 'providers/trusted_sender_provider.dart';
import 'utils/permission_utils.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FloodioApp()));
}

Future<(String, String)> _generateOfficialMarkerSignature(List<int> payloadToSign) async {
  final algorithm = Ed25519();
  final serverKeyPair = await algorithm.newKeyPairFromSeed(List<int>.filled(32, 1));
  final serverPubKey = await serverKeyPair.extractPublicKey();
  final senderId = base64Encode(serverPubKey.bytes);

  final signatureObj = await algorithm.sign(payloadToSign, keyPair: serverKeyPair);
  final signature = base64Encode(signatureObj.bytes);
  return (senderId, signature);
}

Future<(String, String)> _runGenerateOfficialMarkerSignature(List<int> payloadToSign) {
  return Isolate.run(() => _generateOfficialMarkerSignature(payloadToSign));
}

class FloodioApp extends ConsumerWidget {
  const FloodioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Floodio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    _initPermissions();
  }

  Future<void> _initPermissions() async {
    final granted = await requestAppPermissions();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Permissions are required for offline syncing.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => openAppSettings(),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    final locationEnabled = await checkLocationServices();
    if (!locationEnabled && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable Location Services (GPS) for Bluetooth discovery.'),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    if (_lastTapTime == null || now.difference(_lastTapTime!) > const Duration(milliseconds: 500)) {
      _tapCount = 1;
    } else {
      _tapCount++;
    }
    _lastTapTime = now;

    if (_tapCount == 3) {
      _tapCount = 0;
      _showDebugMenu();
    }
  }

  void _showDebugMenu() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Debug Menu', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text('Clear All Data'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final db = ref.read(databaseProvider);
                  await db.transaction(() async {
                    await db.delete(db.hazardMarkers).go();
                    await db.delete(db.newsItems).go();
                    await db.delete(db.syncPayloads).go();
                    await db.delete(db.seenMessageIds).go();
                    await db.delete(db.trustedSenders).go();
                  });
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All data cleared')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final markersAsync = ref.watch(hazardMarkersControllerProvider);
    final cryptoState = ref.watch(cryptoServiceProvider);
    final trustedSendersAsync = ref.watch(trustedSendersControllerProvider);

    return Listener(
      onPointerDown: _handlePointerDown,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Floodio PoC'),
        ),
        drawer: Drawer(
          child: Consumer(
            builder: (context, ref, child) {
              final p2pState = ref.watch(p2pServiceProvider);
              final p2pNotifier = ref.read(p2pServiceProvider.notifier);

              return ListView(
                padding: EdgeInsets.zero,
                children: [
                  const DrawerHeader(
                    decoration: BoxDecoration(color: Colors.blue),
                    child: Text('P2P Sync', style: TextStyle(color: Colors.white, fontSize: 24)),
                  ),
                  ListTile(
                    title: const Text('Host Network'),
                    trailing: Switch(
                      value: p2pState.isHosting,
                      onChanged: (val) {
                        if (val) {
                          p2pNotifier.startHosting();
                        } else {
                          p2pNotifier.stopHosting();
                        }
                      },
                    ),
                  ),
                  if (p2pState.hostState != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text('SSID: ${p2pState.hostState!.ssid}\nActive: ${p2pState.hostState!.isActive}'),
                    ),
                  const Divider(),
                  ListTile(
                    title: const Text('Scan for Networks'),
                    trailing: Switch(
                      value: p2pState.isScanning,
                      onChanged: (val) {
                        if (val) {
                          p2pNotifier.startScanning();
                        } else {
                          p2pNotifier.stopScanning();
                        }
                      },
                    ),
                  ),
                  if (p2pState.clientState != null && p2pState.clientState!.isActive)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Connected to: ${p2pState.clientState!.hostSsid}'),
                          ElevatedButton(
                            onPressed: () => p2pNotifier.disconnect(),
                            child: const Text('Disconnect'),
                          ),
                        ],
                      ),
                    ),
                  if (p2pState.discoveredDevices.isNotEmpty)
                    ...p2pState.discoveredDevices.map((device) => ListTile(
                          title: Text(device.deviceName),
                          subtitle: Text(device.deviceAddress),
                          trailing: ElevatedButton(
                            onPressed: () => p2pNotifier.connectToDevice(device),
                            child: const Text('Connect'),
                          ),
                        )),
                  const Divider(),
                  ListTile(
                    title: const Text('Send Ping'),
                    onTap: () {
                      p2pNotifier.broadcastText('Ping from ${DateTime.now().toIso8601String()}');
                    },
                  ),
                  if (p2pState.receivedTexts.isNotEmpty) ...[
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text('Received Messages:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    ...p2pState.receivedTexts.map((text) => ListTile(title: Text(text))),
                  ],
                ],
              );
            },
          ),
        ),
        body: switch (markersAsync) {
          AsyncData(:final value) => value.isEmpty
              ? const Center(child: Text('No hazard markers found.'))
              : ListView.builder(
                  itemCount: value.length,
                  itemBuilder: (context, index) {
                    final marker = value[index];
                    return ListTile(
                      leading: Icon(
                        Icons.warning,
                        color: marker.trustTier == 1
                            ? Colors.blue
                            : marker.trustTier == 3
                                ? Colors.green
                                : Colors.grey,
                      ),
                      title: Text(marker.type),
                      subtitle: Text(marker.description),
                      trailing: Text('Tier: ${marker.trustTier}'),
                      onLongPress: () {
                        ref.read(trustedSendersControllerProvider.notifier).addTrustedSender(
                              marker.senderId,
                              'Trusted User',
                            );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Sender marked as trusted!')),
                        );
                      },
                    );
                  },
                ),
          AsyncError(:final error) => Center(child: Text('Error: $error')),
          _ => const Center(child: CircularProgressIndicator()),
        },
        floatingActionButton: cryptoState.when(
          data: (_) => Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min, // Prevents the column from blocking the ListView touches
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton(
                    heroTag: 'official',
                    onPressed: () async {
                      final cryptoService = ref.read(cryptoServiceProvider.notifier);

                      final id = DateTime.now().millisecondsSinceEpoch.toString();
                      final type = 'Official Evacuation';
                      final description = 'Move to higher ground immediately.';
                      final timestamp = DateTime.now().millisecondsSinceEpoch;

                      final payloadToSign = utf8.encode('$id$type$timestamp');

                      final (senderId, signature) = await _runGenerateOfficialMarkerSignature(payloadToSign);

                      final trustedKeys = trustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];

                      final trustTier = await cryptoService.verifyAndGetTrustTier(
                        data: payloadToSign,
                        signatureStr: signature,
                        senderPublicKeyStr: senderId,
                        trustedPublicKeys: trustedKeys,
                      );

                      final newMarker = HazardMarkerEntity(
                        id: id,
                        latitude: 37.7749,
                        longitude: -122.4194,
                        type: type,
                        description: description,
                        timestamp: timestamp,
                        senderId: senderId,
                        signature: signature,
                        trustTier: trustTier,
                      );
                      await ref.read(hazardMarkersControllerProvider.notifier).addMarker(newMarker);
                    },
                    backgroundColor: Colors.blue,
                    child: const Icon(Icons.security, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  FloatingActionButton(
                    heroTag: 'user',
                    onPressed: () async {
                      final cryptoService = ref.read(cryptoServiceProvider.notifier);

                      final id = DateTime.now().millisecondsSinceEpoch.toString();
                      final type = 'Flood';
                      final description = 'Water level rising rapidly';
                      final timestamp = DateTime.now().millisecondsSinceEpoch;
                      final senderId = await cryptoService.getPublicKeyString();

                      final payloadToSign = utf8.encode('$id$type$timestamp');
                      final signature = await cryptoService.signData(payloadToSign);

                      final trustedKeys = trustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];

                      final trustTier = await cryptoService.verifyAndGetTrustTier(
                        data: payloadToSign,
                        signatureStr: signature,
                        senderPublicKeyStr: senderId,
                        trustedPublicKeys: trustedKeys,
                      );

                      final newMarker = HazardMarkerEntity(
                        id: id,
                        latitude: 37.7749,
                        longitude: -122.4194,
                        type: type,
                        description: description,
                        timestamp: timestamp,
                        senderId: senderId,
                        signature: signature,
                        trustTier: trustTier,
                      );
                      await ref.read(hazardMarkersControllerProvider.notifier).addMarker(newMarker);
                    },
                    child: const Icon(Icons.add),
                  ),
                ],
              ),
          loading: () => const FloatingActionButton(
            onPressed: null,
            child: CircularProgressIndicator(),
          ),
          error: (e, st) => const FloatingActionButton(
            onPressed: null,
            child: Icon(Icons.error),
          ),
        ),
      ),
    );
  }
}
