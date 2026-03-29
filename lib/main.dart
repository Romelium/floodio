import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crypto/crypto_service.dart';
import 'database/tables.dart';
import 'providers/database_provider.dart';
import 'providers/hazard_marker_provider.dart';
import 'providers/news_item_provider.dart';
import 'providers/p2p_provider.dart';
import 'providers/trusted_sender_provider.dart';
import 'providers/user_profile_provider.dart';
import 'utils/permission_utils.dart';
import 'services/map_cache_service.dart';
import 'providers/map_downloader_provider.dart';
import 'providers/cached_tile_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FloodioApp()));
}

Future<(String, String)> _generateOfficialMarkerSignature(
  List<int> payloadToSign,
) async {
  final algorithm = Ed25519();
  final serverKeyPair = await algorithm.newKeyPairFromSeed(
    List<int>.filled(32, 1),
  );
  final serverPubKey = await serverKeyPair.extractPublicKey();
  final senderId = base64Encode(serverPubKey.bytes);

  final signatureObj = await algorithm.sign(
    payloadToSign,
    keyPair: serverKeyPair,
  );
  final signature = base64Encode(signatureObj.bytes);
  return (senderId, signature);
}

Future<(String, String)> _runGenerateOfficialMarkerSignature(
  List<int> payloadToSign,
) {
  return Isolate.run(() => _generateOfficialMarkerSignature(payloadToSign));
}

class FloodioApp extends ConsumerWidget {
  const FloodioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Floodio',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0277BD),
          secondary: const Color(0xFF00BFA5),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 2,
          shadowColor: Colors.black26,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const InitializerScreen(),
    );
  }
}

class InitializerScreen extends StatefulWidget {
  const InitializerScreen({super.key});

  @override
  State<InitializerScreen> createState() => _InitializerScreenState();
}

class _InitializerScreenState extends State<InitializerScreen> {
  bool _isInitialized = false;
  bool _needsOnboarding = true;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name');
    if (name != null && name.isNotEmpty) {
      _needsOnboarding = false;
    }
    setState(() {
      _isInitialized = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_needsOnboarding) {
      return const OnboardingScreen();
    }
    return const HomeScreen();
  }
}

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    final contact = _contactController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required')),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    await prefs.setString('user_contact', contact);

    await ref.read(cryptoServiceProvider.future);
    final cryptoService = ref.read(cryptoServiceProvider.notifier);
    final publicKey = await cryptoService.getPublicKeyString();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final payloadToSign = utf8.encode('$publicKey$name$contact$timestamp');
    final signature = await cryptoService.signData(payloadToSign);

    final profile = UserProfileEntity(
      publicKey: publicKey,
      name: name,
      contactInfo: contact,
      timestamp: timestamp,
      signature: signature,
    );

    await ref.read(userProfilesControllerProvider.notifier).saveProfile(profile);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Floodio')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Personal Information',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'This information will be shared with nearby devices to help coordinate relief efforts.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'Contact Number / Info (Optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saveProfile,
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
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
          content: Text(
            'Please enable Location Services (GPS) for Bluetooth discovery.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    final now = DateTime.now();
    if (_lastTapTime == null ||
        now.difference(_lastTapTime!) > const Duration(milliseconds: 500)) {
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
                title: Text(
                  'Debug Menu',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
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
                    await db.delete(db.userProfiles).go();
                  });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('user_name');
                  await prefs.remove('user_contact');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All data cleared')),
                  );
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const InitializerScreen()),
                    (route) => false,
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
      case 1:
        return 'Official';
      case 3:
        return 'Trusted';
      case 4:
        return 'Crowdsourced';
      default:
        return 'Unknown';
    }
  }

  IconData _getHazardIcon(String type) {
    switch (type.toLowerCase()) {
      case 'flood':
        return Icons.water;
      case 'fire':
        return Icons.local_fire_department;
      case 'roadblock':
        return Icons.remove_road;
      case 'medical':
        return Icons.medical_services;
      default:
        return Icons.warning;
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Report Hazard'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: InputDecoration(
                  labelText: 'Hazard Type',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: ['Flood', 'Fire', 'Roadblock', 'Medical', 'Other']
                    .map(
                      (type) =>
                          DropdownMenuItem(value: type, child: Text(type)),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => selectedType = val);
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final cryptoService = ref.read(cryptoServiceProvider.notifier);
                final trustedSendersAsync = ref.read(
                  trustedSendersControllerProvider,
                );

                final id = DateTime.now().millisecondsSinceEpoch.toString();
                final type = selectedType;
                final description = descController.text;
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final senderId = await cryptoService.getPublicKeyString();

                final payloadToSign = utf8.encode('$id$type$timestamp');
                final signature = await cryptoService.signData(payloadToSign);

                final trustedKeys =
                    trustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];

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
                await ref
                    .read(hazardMarkersControllerProvider.notifier)
                    .addMarker(newMarker);
              },
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Report'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDownloadMapDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Offline Map'),
        content: const Text('Download the currently visible area for offline use? This may take a moment.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              final bounds = _mapController.camera.visibleBounds;
              final currentZoom = _mapController.camera.zoom.floor();
              final maxZoom = min(currentZoom + 2, 16);
              ref.read(mapDownloaderProvider.notifier).downloadRegion(
                bounds,
                currentZoom,
                maxZoom,
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              );
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  void _showAddNewsDialog() {
    final titleController = TextEditingController(
      text: 'Official Evacuation Notice',
    );
    final contentController = TextEditingController(
      text: 'Move to higher ground immediately. Flood waters rising.',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.campaign, color: Colors.blue),
            SizedBox(width: 8),
            Text('Official Alert'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              decoration: InputDecoration(
                labelText: 'Content',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              final id = DateTime.now().millisecondsSinceEpoch.toString();
              final title = titleController.text;
              final content = contentController.text;
              final timestamp = DateTime.now().millisecondsSinceEpoch;

              final payloadToSign = utf8.encode('$id$title$timestamp');

              final (senderId, signature) =
                  await _runGenerateOfficialMarkerSignature(payloadToSign);

              final trustedSendersAsync = ref.read(
                trustedSendersControllerProvider,
              );
              final trustedKeys =
                  trustedSendersAsync.value?.map((e) => e.publicKey).toList() ??
                  [];

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
              await ref
                  .read(newsItemsControllerProvider.notifier)
                  .addNewsItem(newNews);
            },
            icon: const Icon(Icons.broadcast_on_personal, size: 18),
            label: const Text('Broadcast'),
          ),
        ],
      ),
    );
  }

  UserProfileEntity? _getProfile(String publicKey, List<UserProfileEntity> profiles) {
    try {
      return profiles.firstWhere((p) => p.publicKey == publicKey);
    } catch (_) {
      return null;
    }
  }

  Widget _buildMap(AsyncValue<List<HazardMarkerEntity>> markersAsync, List<UserProfileEntity> profiles) {
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
          tileProvider: CachedTileProvider(ref.read(mapCacheServiceProvider)),
        ),
        CircleLayer(
          circles: markers
              .where((m) => m.trustTier == 1)
              .map(
                (m) => CircleMarker(
                  point: LatLng(m.latitude, m.longitude),
                  radius: 500,
                  useRadiusInMeter: true,
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderColor: Colors.blue,
                  borderStrokeWidth: 2,
                ),
              )
              .toList(),
        ),
        MarkerLayer(
          markers: markers
              .map(
                (m) => Marker(
                  point: LatLng(m.latitude, m.longitude),
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Row(
                            children: [
                              Icon(
                                _getHazardIcon(m.type),
                                color: m.trustTier == 1
                                    ? Colors.blue
                                    : m.trustTier == 3
                                    ? Colors.green
                                    : Colors.grey.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(m.type),
                            ],
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTrustBadge(m.trustTier),
                              const SizedBox(height: 16),
                              Text(
                                m.description,
                                style: const TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Reported: ${_formatTimestamp(m.timestamp)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final profile = _getProfile(m.senderId, profiles);
                                  if (profile != null) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Divider(),
                                        Text('Reported by: ${profile.name}'),
                                        if (profile.contactInfo.isNotEmpty)
                                          Text('Contact: ${profile.contactInfo}'),
                                      ],
                                    );
                                  } else {
                                    return const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Divider(),
                                        Text('Reported by: Unknown User'),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                          actions: [
                            if (m.trustTier == 4)
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _markAsTrusted(m.senderId);
                                },
                                icon: const Icon(Icons.verified_user, size: 18),
                                label: const Text('Trust Sender'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.green,
                                ),
                              ),
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.location_on,
                          color: m.trustTier == 1
                              ? Colors.blue
                              : m.trustTier == 3
                              ? Colors.green
                              : Colors.grey.shade700,
                          size: 40,
                        ),
                        Positioned(
                          top: 6,
                          child: Icon(
                            _getHazardIcon(m.type),
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Widget _buildFeed(
    AsyncValue<List<HazardMarkerEntity>> markersAsync,
    AsyncValue<List<NewsItemEntity>> newsAsync,
    List<UserProfileEntity> profiles,
  ) {
    final markers = markersAsync.value ?? [];
    final news = newsAsync.value ?? [];

    final combined = <dynamic>[...markers, ...news];
    combined.sort((a, b) => (b.timestamp as int).compareTo(a.timestamp as int));

    if (combined.isEmpty) {
      if (markersAsync.isLoading || newsAsync.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (markersAsync.hasError)
        return Center(child: Text('Error: ${markersAsync.error}'));
      if (newsAsync.hasError)
        return Center(child: Text('Error: ${newsAsync.error}'));
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No data available.',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Sync with nearby devices or create a report.',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 80),
      itemCount: combined.length,
      itemBuilder: (context, index) {
        final item = combined[index];
        if (item is HazardMarkerEntity) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: item.trustTier == 1
                            ? Colors.blue.shade100
                            : item.trustTier == 3
                            ? Colors.green.shade100
                            : Colors.grey.shade200,
                        child: Icon(
                          _getHazardIcon(item.type),
                          color: item.trustTier == 1
                              ? Colors.blue
                              : item.trustTier == 3
                              ? Colors.green
                              : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hazard: ${item.type}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              _formatTimestamp(item.timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildTrustBadge(item.trustTier),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.description,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  Builder(
                    builder: (context) {
                      final profile = _getProfile(item.senderId, profiles);
                      if (profile != null) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'By: ${profile.name}${profile.contactInfo.isNotEmpty ? ' (${profile.contactInfo})' : ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'By: Unknown User',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                          ),
                        );
                      }
                    },
                  ),
                  if (item.trustTier == 4) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: () => _markAsTrusted(item.senderId),
                        icon: const Icon(Icons.verified_user, size: 16),
                        label: const Text('Trust Sender'),
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.green.shade700,
                          backgroundColor: Colors.green.shade50,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        } else if (item is NewsItemEntity) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: item.trustTier == 1
                            ? Colors.blue.shade100
                            : item.trustTier == 3
                            ? Colors.green.shade100
                            : Colors.grey.shade200,
                        child: Icon(
                          Icons.campaign,
                          color: item.trustTier == 1
                              ? Colors.blue
                              : item.trustTier == 3
                              ? Colors.green
                              : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              _formatTimestamp(item.timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildTrustBadge(item.trustTier),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.content,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                  Builder(
                    builder: (context) {
                      final profile = _getProfile(item.senderId, profiles);
                      if (profile != null) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'By: ${profile.name}${profile.contactInfo.isNotEmpty ? ' (${profile.contactInfo})' : ''}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                          ),
                        );
                      } else {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'By: Unknown User',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontStyle: FontStyle.italic),
                          ),
                        );
                      }
                    },
                  ),
                  if (item.trustTier == 4) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: () => _markAsTrusted(item.senderId),
                        icon: const Icon(Icons.verified_user, size: 16),
                        label: const Text('Trust Sender'),
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.green.shade700,
                          backgroundColor: Colors.green.shade50,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildTrustBadge(int tier) {
    final color = tier == 1
        ? Colors.blue
        : tier == 3
        ? Colors.green
        : Colors.grey;
    final icon = tier == 1
        ? Icons.verified
        : tier == 3
        ? Icons.thumb_up
        : Icons.people;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            _getTrustTierName(tier),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color.shade700,
            ),
          ),
        ],
      ),
    );
  }

  void _markAsTrusted(String senderId) {
    ref
        .read(trustedSendersControllerProvider.notifier)
        .addTrustedSender(senderId, 'Trusted User');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sender marked as trusted!')));
  }

  @override
  Widget build(BuildContext context) {
    final markersAsync = ref.watch(hazardMarkersControllerProvider);
    final newsAsync = ref.watch(newsItemsControllerProvider);
    final profilesAsync = ref.watch(userProfilesControllerProvider);
    final cryptoState = ref.watch(cryptoServiceProvider);
    final downloadProgress = ref.watch(mapDownloaderProvider);
    final profiles = profilesAsync.value ?? [];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Floodio PoC'),
          bottom: downloadProgress.isDownloading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4.0),
                  child: LinearProgressIndicator(value: downloadProgress.percentage),
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Download Offline Map',
              onPressed: _showDownloadMapDialog,
            ),
            Consumer(
              builder: (context, ref, child) {
                final p2pState = ref.watch(p2pServiceProvider);
                final isConnected =
                    p2pState.hostState?.isActive == true ||
                    p2pState.clientState?.isActive == true;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 8.0,
                  ),
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: isConnected
                          ? Colors.green.shade100
                          : Colors.blue.shade50,
                      foregroundColor: isConnected
                          ? Colors.green.shade800
                          : Colors.blue.shade800,
                    ),
                    icon: isConnected
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.green,
                            ),
                          )
                        : const Icon(Icons.sync, size: 18),
                    label: Text(isConnected ? 'Connected' : 'Sync'),
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const SyncBottomSheet(),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildMap(markersAsync, profiles),
            _buildFeed(markersAsync, newsAsync, profiles),
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
            mainAxisSize: MainAxisSize
                .min, // Prevents the column from blocking the ListView touches
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
                label: const Text(
                  'Official Alert',
                  style: TextStyle(color: Colors.white),
                ),
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

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            left: 20.0,
            right: 20.0,
            top: 20.0,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Device-to-Device Sync',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Status Card
                Card(
                  color: (p2pState.isSyncing || p2pState.isConnecting)
                      ? Colors.blue.shade50
                      : Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: (p2pState.isSyncing || p2pState.isConnecting)
                          ? Colors.blue.shade200
                          : Colors.grey.shade200,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        if (p2pState.isSyncing || p2pState.isConnecting)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        else
                          Icon(
                            Icons.sync_alt,
                            color: Colors.blue.shade700,
                            size: 28,
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sync Status',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                p2pState.syncMessage ??
                                    'Ready to sync. Choose an option below.',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      (p2pState.isSyncing ||
                                          p2pState.isConnecting)
                                      ? Colors.blue.shade900
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Auto-Sync Section
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: p2pState.isAutoSyncing
                          ? Colors.blue.shade300
                          : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    color: p2pState.isAutoSyncing
                        ? Colors.blue.shade50
                        : Colors.white,
                  ),
                  child: SwitchListTile(
                    title: Text(
                      'Mesh Auto-Sync',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: p2pState.isAutoSyncing
                            ? Colors.blue.shade800
                            : Colors.black87,
                      ),
                    ),
                    subtitle: Text(
                      'Automatically discover and sync with nearby devices in the background.',
                      style: TextStyle(
                        color: p2pState.isAutoSyncing
                            ? Colors.blue.shade700
                            : Colors.grey.shade600,
                      ),
                    ),
                    value: p2pState.isAutoSyncing,
                    activeThumbColor: Colors.blue,
                    onChanged: (val) => p2pNotifier.toggleAutoSync(),
                  ),
                ),
                const SizedBox(height: 16),

                // Manual Controls
                Text(
                  'Manual Controls',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),

                // Host Section
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text(
                          'Share Data (Host)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Create a local network for others to join',
                        ),
                        value: p2pState.isHosting,
                        onChanged:
                            (p2pState.isScanning || p2pState.isAutoSyncing)
                            ? null
                            : (val) {
                                if (val)
                                  p2pNotifier.startHosting();
                                else
                                  p2pNotifier.stopHosting();
                              },
                      ),
                      if (p2pState.hostState?.isActive == true)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            bottom: 16.0,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.wifi_tethering,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Hosting on: ${p2pState.hostState?.ssid ?? 'Unknown'}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (p2pState.hostState?.isActive == true &&
                          p2pState.connectedClients.isNotEmpty) ...[
                        const Divider(height: 1),
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Connected Clients',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        ...p2pState.connectedClients.map(
                          (client) => ListTile(
                            key: ValueKey(client.id),
                            leading: const CircleAvatar(
                              backgroundColor: Colors.green,
                              child: Icon(Icons.check, color: Colors.white),
                            ),
                            title: Text(
                              client.username.isEmpty
                                  ? 'Unknown Client'
                                  : client.username,
                            ),
                            subtitle: Text(
                              client.id,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
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
                        title: const Text(
                          'Receive Data (Scan)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Look for nearby devices sharing data',
                        ),
                        value:
                            p2pState.isScanning ||
                            p2pState.clientState?.isActive == true,
                        onChanged:
                            (p2pState.isHosting || p2pState.isAutoSyncing)
                            ? null
                            : (val) {
                                if (val)
                                  p2pNotifier.startScanning();
                                else
                                  p2pNotifier.disconnect();
                              },
                      ),
                      if (p2pState.clientState?.isActive == true)
                        Padding(
                          padding: const EdgeInsets.only(
                            left: 16.0,
                            right: 16.0,
                            bottom: 16.0,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.wifi,
                                color: Colors.green,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Connected to: ${p2pState.clientState?.hostSsid ?? 'Unknown'}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      if (p2pState.isScanning &&
                          p2pState.discoveredDevices.isNotEmpty &&
                          p2pState.clientState?.isActive != true) ...[
                        const Divider(height: 1),
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Nearby Devices',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        ...p2pState.discoveredDevices.map(
                          (device) => ListTile(
                            key: ValueKey(device.deviceAddress),
                            leading: const CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Icon(
                                Icons.smartphone,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              device.deviceName.isEmpty
                                  ? 'Unknown Device'
                                  : device.deviceName,
                            ),
                            subtitle: Text(
                              device.deviceAddress,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: FilledButton(
                              onPressed: p2pState.isConnecting
                                  ? null
                                  : () => p2pNotifier.connectToDevice(device),
                              child: p2pState.isConnecting
                                  ? const Text('Connecting...')
                                  : const Text('Connect'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      if (p2pState.isScanning &&
                          p2pState.discoveredDevices.isEmpty &&
                          p2pState.clientState?.isActive != true)
                        const Padding(
                          padding: EdgeInsets.all(24.0),
                          child: Center(
                            child: Column(
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text(
                                  'Searching for nearby devices...',
                                  style: TextStyle(color: Colors.grey),
                                ),
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
      ),
    );
  }
}
