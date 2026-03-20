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

  String _getTrustTierName(int tier) {
    switch (tier) {
      case 1: return 'Official';
      case 3: return 'Trusted';
      case 4: return 'Crowdsourced';
      default: return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final markersAsync = ref.watch(hazardMarkersControllerProvider);
    final cryptoState = ref.watch(cryptoServiceProvider);
    final trustedSendersAsync = ref.watch(trustedSendersControllerProvider);

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Floodio PoC'),
          actions: [
            Consumer(
              builder: (context, ref, child) {
                final p2pState = ref.watch(p2pServiceProvider);
                final isConnected = p2pState.hostState?.isActive == true || p2pState.clientState?.isActive == true;
                
                return IconButton(
                  icon: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.sync),
                      if (isConnected)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => const SyncBottomSheet(),
                    );
                  },
                );
              },
            ),
          ],
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
                      subtitle: Text('${marker.description}\n${DateTime.fromMillisecondsSinceEpoch(marker.timestamp).toLocal().toString().split('.')[0]}'),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Tier: ${marker.trustTier}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(_getTrustTierName(marker.trustTier), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
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

class SyncBottomSheet extends ConsumerWidget {
  const SyncBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p2pState = ref.watch(p2pServiceProvider);
    final p2pNotifier = ref.read(p2pServiceProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16.0,
          right: 16.0,
          top: 16.0,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Device-to-Device Sync', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
  
              // Status Card
              Card(
                color: (p2pState.isSyncing || p2pState.isConnecting) ? Colors.blue.shade50 : Colors.grey.shade50,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: (p2pState.isSyncing || p2pState.isConnecting) ? Colors.blue.shade200 : Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          if (p2pState.isSyncing || p2pState.isConnecting)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            Icon(
                              Icons.info_outline,
                              color: Colors.grey.shade700,
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p2pState.syncMessage ?? 'Ready to sync. Choose an option below.',
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: (p2pState.isSyncing || p2pState.isConnecting) ? Colors.blue.shade900 : Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
  
              // Auto-Sync Section
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue.shade300),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.blue.shade50,
                ),
                child: SwitchListTile(
                  title: const Text('Auto-Discovery (Mesh Mode)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  subtitle: const Text('Automatically alternate between hosting and scanning to find peers.'),
                  value: p2pState.isAutoSyncing,
                  onChanged: (val) => p2pNotifier.toggleAutoSync(),
                ),
              ),
              const SizedBox(height: 12),
  
              // Host Section
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Share Data (Host)', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Create a local network for others to join'),
                      value: p2pState.isHosting,
                      onChanged: (p2pState.isScanning || p2pState.isAutoSyncing) ? null : (val) {
                        if (val) p2pNotifier.startHosting();
                        else p2pNotifier.stopHosting();
                      },
                    ),
                    if (p2pState.hostState?.isActive == true)
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                        child: Row(
                          children: [
                            const Icon(Icons.wifi_tethering, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Hosting on: ${p2pState.hostState?.ssid ?? 'Unknown'}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500))),
                          ],
                        ),
                      ),
                    if (p2pState.hostState?.isActive == true && p2pState.connectedClients.isNotEmpty) ...[
                      const Divider(height: 1),
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('Connected Clients', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ...p2pState.connectedClients.map((client) => ListTile(
                        key: ValueKey(client.id),
                        leading: const CircleAvatar(
                          backgroundColor: Colors.green,
                          child: Icon(Icons.check, color: Colors.white),
                        ),
                        title: Text(client.username.isEmpty ? 'Unknown Client' : client.username),
                        subtitle: Text(client.id, style: const TextStyle(fontSize: 12)),
                      )),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
  
              const SizedBox(height: 12),
  
              // Client Section
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Receive Data (Scan)', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Look for nearby devices sharing data'),
                      value: p2pState.isScanning || p2pState.clientState?.isActive == true,
                      onChanged: (p2pState.isHosting || p2pState.isAutoSyncing) ? null : (val) {
                        if (val) p2pNotifier.startScanning();
                        else p2pNotifier.disconnect();
                      },
                    ),
                    if (p2pState.clientState?.isActive == true)
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0),
                        child: Row(
                          children: [
                            const Icon(Icons.wifi, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Connected to: ${p2pState.clientState?.hostSsid ?? 'Unknown'}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500))),
                          ],
                        ),
                      ),
  
                    if (p2pState.isScanning && p2pState.discoveredDevices.isNotEmpty && p2pState.clientState?.isActive != true) ...[
                      const Divider(height: 1),
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('Nearby Devices', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      ),
                      ...p2pState.discoveredDevices.map((device) => ListTile(
                        key: ValueKey(device.deviceAddress),
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blue,
                          child: Icon(Icons.smartphone, color: Colors.white),
                        ),
                        title: Text(device.deviceName.isEmpty ? 'Unknown Device' : device.deviceName),
                        subtitle: Text(device.deviceAddress, style: const TextStyle(fontSize: 12)),
                        trailing: FilledButton(
                          onPressed: p2pState.isConnecting ? null : () => p2pNotifier.connectToDevice(device),
                          child: p2pState.isConnecting 
                              ? const Text('Connecting...')
                              : const Text('Connect'),
                        ),
                      )),
                      const SizedBox(height: 8),
                    ],
  
                    if (p2pState.isScanning && p2pState.discoveredDevices.isEmpty && p2pState.clientState?.isActive != true)
                      const Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Center(
                          child: Column(
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Searching for nearby devices...', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
