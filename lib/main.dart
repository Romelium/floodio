import 'dart:convert';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';

import 'crypto/crypto_service.dart';
import 'database/tables.dart';
import 'providers/database_provider.dart';
import 'providers/hazard_marker_provider.dart';
import 'providers/news_item_provider.dart';
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
  int _currentIndex = 0;
  final MapController _mapController = MapController();

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

  IconData _getHazardIcon(String type) {
    switch (type.toLowerCase()) {
      case 'flood': return Icons.water;
      case 'fire': return Icons.local_fire_department;
      case 'roadblock': return Icons.remove_road;
      case 'medical': return Icons.medical_services;
      default: return Icons.warning;
    }
  }

  String _formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showAddHazardDialog(LatLng point) {
    String selectedType = 'Flood';
    final descController = TextEditingController(text: 'Water level rising');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
        title: const Text('Report Hazard'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: const InputDecoration(labelText: 'Hazard Type'),
                items: ['Flood', 'Fire', 'Roadblock', 'Medical', 'Other']
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => selectedType = val);
                  }
                },
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final cryptoService = ref.read(cryptoServiceProvider.notifier);
              final trustedSendersAsync = ref.read(trustedSendersControllerProvider);

              final id = DateTime.now().millisecondsSinceEpoch.toString();
                final type = selectedType;
              final description = descController.text;
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
                latitude: point.latitude,
                longitude: point.longitude,
                type: type,
                description: description,
                timestamp: timestamp,
                senderId: senderId,
                signature: signature,
                trustTier: trustTier,
              );
              await ref.read(hazardMarkersControllerProvider.notifier).addMarker(newMarker);
            },
            child: const Text('Report'),
          ),
        ],
        ),
      ),
    );
  }

  void _showAddNewsDialog() {
    final titleController = TextEditingController(text: 'Official Evacuation Notice');
    final contentController = TextEditingController(text: 'Move to higher ground immediately. Flood waters rising.');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Official Alert'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            TextField(
              controller: contentController,
              decoration: const InputDecoration(labelText: 'Content'),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final id = DateTime.now().millisecondsSinceEpoch.toString();
              final title = titleController.text;
              final content = contentController.text;
              final timestamp = DateTime.now().millisecondsSinceEpoch;

              final payloadToSign = utf8.encode('$id$title$timestamp');

              final (senderId, signature) = await _runGenerateOfficialMarkerSignature(payloadToSign);

              final trustedSendersAsync = ref.read(trustedSendersControllerProvider);
              final trustedKeys = trustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];

              final cryptoService = ref.read(cryptoServiceProvider.notifier);
              final trustTier = await cryptoService.verifyAndGetTrustTier(
                data: payloadToSign,
                signatureStr: signature,
                senderPublicKeyStr: senderId,
                trustedPublicKeys: trustedKeys,
              );

              final newNews = NewsItemEntity(
                id: id,
                title: title,
                content: content,
                timestamp: timestamp,
                senderId: senderId,
                signature: signature,
                trustTier: trustTier,
              );
              await ref.read(newsItemsControllerProvider.notifier).addNewsItem(newNews);
            },
            child: const Text('Broadcast'),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(AsyncValue<List<HazardMarkerEntity>> markersAsync) {
    final markers = markersAsync.value ?? [];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: const LatLng(37.7749, -122.4194),
        initialZoom: 13.0,
        onTap: (tapPosition, point) {
          _showAddHazardDialog(point);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.floodio',
        ),
        CircleLayer(
          circles: markers.where((m) => m.trustTier == 1).map((m) => CircleMarker(
            point: LatLng(m.latitude, m.longitude),
            radius: 500,
            useRadiusInMeter: true,
            color: Colors.blue.withOpacity(0.2),
            borderColor: Colors.blue,
            borderStrokeWidth: 2,
          )).toList(),
        ),
        MarkerLayer(
          markers: markers.map((m) => Marker(
            point: LatLng(m.latitude, m.longitude),
            width: 40,
            height: 40,
            alignment: Alignment.topCenter,
            rotate: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(m.type),
                    content: Text('${m.description}\n\nTier: ${_getTrustTierName(m.trustTier)}'),
                    actions: [
                      if (m.trustTier == 4)
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _markAsTrusted(m.senderId);
                          },
                          child: const Text('Trust Sender'),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: m.trustTier == 1 ? Colors.blue : m.trustTier == 3 ? Colors.green : Colors.grey,
                    width: 3,
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Icon(
                  _getHazardIcon(m.type),
                  color: m.trustTier == 1 ? Colors.blue : m.trustTier == 3 ? Colors.green : Colors.grey,
                  size: 20,
                ),
              ),
            ),
          )).toList(),
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Widget _buildFeed(AsyncValue<List<HazardMarkerEntity>> markersAsync, AsyncValue<List<NewsItemEntity>> newsAsync) {
    final markers = markersAsync.value ?? [];
    final news = newsAsync.value ?? [];

    final combined = <dynamic>[...markers, ...news];
    combined.sort((a, b) => (b.timestamp as int).compareTo(a.timestamp as int));

    if (combined.isEmpty) {
      if (markersAsync.isLoading || newsAsync.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (markersAsync.hasError) return Center(child: Text('Error: ${markersAsync.error}'));
      if (newsAsync.hasError) return Center(child: Text('Error: ${newsAsync.error}'));
      return const Center(child: Text('No data available.'));
    }

    return ListView.separated(
      itemCount: combined.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = combined[index];
        if (item is HazardMarkerEntity) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: item.trustTier == 1 ? Colors.blue.shade100 : item.trustTier == 3 ? Colors.green.shade100 : Colors.grey.shade200,
              child: Icon(
                _getHazardIcon(item.type),
                color: item.trustTier == 1 ? Colors.blue : item.trustTier == 3 ? Colors.green : Colors.grey,
              ),
            ),
            title: Text('Hazard: ${item.type}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(item.description),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(item.timestamp),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (item.trustTier == 4)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text('Long-press to trust sender', style: TextStyle(fontSize: 11, color: Colors.blue)),
                  ),
              ],
            ),
            isThreeLine: true,
            trailing: _buildTrustBadge(item.trustTier),
            onLongPress: item.trustTier == 4 ? () => _markAsTrusted(item.senderId) : null,
          );
        } else if (item is NewsItemEntity) {
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: item.trustTier == 1 ? Colors.blue.shade100 : item.trustTier == 3 ? Colors.green.shade100 : Colors.grey.shade200,
              child: Icon(
                Icons.article,
                color: item.trustTier == 1 ? Colors.blue : item.trustTier == 3 ? Colors.green : Colors.grey,
              ),
            ),
            title: Text('News: ${item.title}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(item.content),
                const SizedBox(height: 4),
                Text(
                  _formatTimestamp(item.timestamp),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (item.trustTier == 4)
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text('Long-press to trust sender', style: TextStyle(fontSize: 11, color: Colors.blue)),
                  ),
              ],
            ),
            isThreeLine: true,
            trailing: _buildTrustBadge(item.trustTier),
            onLongPress: item.trustTier == 4 ? () => _markAsTrusted(item.senderId) : null,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildTrustBadge(int tier) {
    final color = tier == 1 ? Colors.blue : tier == 3 ? Colors.green : Colors.grey;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.shade300),
          ),
          child: Text(
            _getTrustTierName(tier),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade700),
          ),
        ),
      ],
    );
  }

  void _markAsTrusted(String senderId) {
    ref.read(trustedSendersControllerProvider.notifier).addTrustedSender(
          senderId,
          'Trusted User',
        );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sender marked as trusted!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markersAsync = ref.watch(hazardMarkersControllerProvider);
    final newsAsync = ref.watch(newsItemsControllerProvider);
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
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildMap(markersAsync),
            _buildFeed(markersAsync, newsAsync),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Feed'),
          ],
        ),
        floatingActionButton: cryptoState.when(
          data: (_) => Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min, // Prevents the column from blocking the ListView touches
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_currentIndex == 0) ...[
                    FloatingActionButton.small(
                      heroTag: 'center_map',
                      onPressed: () {
                        _mapController.move(const LatLng(37.7749, -122.4194), 13.0);
                      },
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FloatingActionButton.extended(
                    heroTag: 'official',
                    onPressed: _showAddNewsDialog,
                    backgroundColor: Colors.blue,
                    icon: const Icon(Icons.campaign, color: Colors.white),
                    label: const Text('Official Alert', style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(height: 16),
                  FloatingActionButton.extended(
                    heroTag: 'user',
                    onPressed: () {
                      LatLng point = const LatLng(37.7749, -122.4194);
                      if (_currentIndex == 0) {
                        point = _mapController.camera.center;
                      }
                        try {
                          point = _mapController.camera.center;
                        } catch (_) {}
                      _showAddHazardDialog(point);
                    },
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text('Report Hazard'),
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
