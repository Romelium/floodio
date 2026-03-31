import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:floodio/database/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crypto/crypto_service.dart';
import 'database/connection.dart';
import 'database/tables.dart';
import 'providers/admin_trusted_sender_provider.dart';
import 'providers/area_provider.dart';
import 'providers/cached_tile_provider.dart';
import 'providers/database_provider.dart';
import 'providers/feed_provider.dart';
import 'providers/hazard_marker_provider.dart';
import 'providers/location_provider.dart';
import 'providers/map_downloader_provider.dart';
import 'providers/news_item_provider.dart';
import 'providers/offline_regions_provider.dart';
import 'providers/p2p_provider.dart';
import 'providers/revoked_delegation_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/trusted_sender_provider.dart';
import 'providers/ui_p2p_provider.dart';
import 'providers/untrusted_sender_provider.dart';
import 'providers/user_profile_provider.dart';
import 'services/background_service.dart';
import 'services/cloud_sync_service.dart';
import 'services/map_cache_service.dart';
import 'services/mock_gov_api_service.dart';
import 'utils/permission_utils.dart';

class LocalImageDisplay extends StatefulWidget {
  final String imageId;
  const LocalImageDisplay({super.key, required this.imageId});

  @override
  State<LocalImageDisplay> createState() => _LocalImageDisplayState();
}

class _LocalImageDisplayState extends State<LocalImageDisplay> {
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${widget.imageId}');
    if (await file.exists()) {
      if (mounted) {
        setState(() {
          _imageFile = file;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_imageFile == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                  backgroundColor: Colors.black,
                  iconTheme: const IconThemeData(color: Colors.white),
                ),
                body: Center(
                  child: InteractiveViewer(child: Image.file(_imageFile!)),
                ),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            _imageFile!,
            height: 150,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connection = await getSharedConnection();
  final db = AppDatabase(connection);

  // Initialize settings before app start
  final container = ProviderContainer();
  await container.read(appSettingsProvider.notifier).init();
  final initialSettings = container.read(appSettingsProvider);

  await db.cleanupOldData();
  await initializeBackgroundService();
  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWith((ref) {
          ref.onDispose(db.close);
          return db;
        }),
        appSettingsProvider.overrideWithValue(initialSettings),
      ],
      child: const FloodioApp(),
    ),
  );
}

class FloodioApp extends ConsumerWidget {
  const FloodioApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Floodio Mesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A237E), // Deep Rescue Blue
          primary: const Color(0xFF1A237E),
          secondary: const Color(0xFFFF6D00), // Safety Orange
          surface: Colors.white,
          error: const Color(0xFFD32F2F),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A237E),
          ),
          titleLarge: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          bodyMedium: TextStyle(fontSize: 15, height: 1.4),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF1A237E),
          foregroundColor: Colors.white,
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    await prefs.reload();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required')));
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

    await ref
        .read(userProfilesControllerProvider.notifier)
        .saveProfile(profile);

    if (mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
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

class DownloadMapDialog extends ConsumerStatefulWidget {
  final LatLngBounds bounds;
  final int currentZoom;

  const DownloadMapDialog({
    super.key,
    required this.bounds,
    required this.currentZoom,
  });

  @override
  ConsumerState<DownloadMapDialog> createState() => _DownloadMapDialogState();
}

class _DownloadMapDialogState extends ConsumerState<DownloadMapDialog> {
  late int _maxZoom;

  @override
  void initState() {
    super.initState();
    _maxZoom = max(widget.currentZoom, min(widget.currentZoom + 2, 18));
  }

  @override
  Widget build(BuildContext context) {
    final downloader = ref.read(mapDownloaderProvider.notifier);
    final tileCount = downloader.estimateTileCount(
      widget.bounds,
      widget.currentZoom,
      _maxZoom,
    );
    final estimatedSizeMB =
        (tileCount * 0.015); // rough estimate: 15KB per tile

    return AlertDialog(
      title: const Text('Download Offline Map'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Download the currently visible area for offline use.'),
          const SizedBox(height: 16),
          Text('Current Zoom: ${widget.currentZoom}'),
          Row(
            children: [
              const Text('Max Zoom: '),
              Expanded(
                child: widget.currentZoom >= 18
                    ? const SizedBox.shrink()
                    : Slider(
                        value: _maxZoom.toDouble(),
                        min: widget.currentZoom.toDouble(),
                        max: max(18.0, widget.currentZoom.toDouble()),
                        divisions: max(1, 18 - widget.currentZoom),
                        label: _maxZoom.toString(),
                        onChanged: (val) {
                          setState(() {
                            _maxZoom = val.toInt();
                          });
                        },
                      ),
              ),
              Text(_maxZoom.toString()),
            ],
          ),
          const SizedBox(height: 8),
          Text('Estimated Tiles: $tileCount'),
          Text('Estimated Size: ~${estimatedSizeMB.toStringAsFixed(1)} MB'),
          if (tileCount > 10000)
            const Padding(
              padding: EdgeInsets.only(top: 8.0),
              child: Text(
                'Warning: Large download. This may take a long time and consume significant storage.',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: tileCount > 50000
              ? null
              : () {
                  Navigator.pop(context);
                  downloader.downloadRegion(
                    widget.bounds,
                    widget.currentZoom,
                    _maxZoom,
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  );
                },
          child: const Text('Download'),
        ),
      ],
    );
  }
}

class MeshStatusChip extends ConsumerWidget {
  const MeshStatusChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p2pState = ref.watch(uiP2pServiceProvider);
    final isConnected =
        p2pState.hostState?.isActive == true ||
        p2pState.clientState?.isActive == true;
    final isSyncing = p2pState.isSyncing || p2pState.isConnecting;

    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => const SyncBottomSheet(),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isConnected
              ? Colors.green.shade700
              : (p2pState.isAutoSyncing
                    ? Colors.orange.shade800
                    : Colors.white24),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSyncing)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              Icon(
                isConnected ? Icons.hub : Icons.hub_outlined,
                size: 14,
                color: Colors.white,
              ),
            const SizedBox(width: 6),
            Text(
              isConnected
                  ? 'MESH ACTIVE'
                  : (p2pState.isAutoSyncing ? 'SEARCHING' : 'OFFLINE'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tapCount = 0;
  DateTime? _lastTapTime;
  int _currentIndex = 0;
  final MapController _mapController = MapController();
  bool _isDrawingArea = false;
  String? _editingAreaId;
  final List<LatLng> _currentAreaPoints = [];
  bool _hasCenteredOnLocation = false;
  bool _showOfflineRegions = true;

  final ScrollController _feedScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initPermissions();
    _feedScrollController.addListener(() {
      if (_feedScrollController.position.pixels >=
          _feedScrollController.position.maxScrollExtent - 200) {
        ref.read(feedLimitProvider.notifier).loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cloudSyncServiceProvider);
    });
  }

  @override
  void dispose() {
    _feedScrollController.dispose();
    super.dispose();
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
    } else if (granted) {
      await requestBatteryOptimizationExemption();
      final service = FlutterBackgroundService();
      if (!(await service.isRunning())) {
        await service.startService();
      }
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
                    await db.delete(db.deletedItems).go();
                    await db.delete(db.seenMessageIds).go();
                    await db.delete(db.trustedSenders).go();
                    await db.delete(db.untrustedSenders).go();
                    await db.delete(db.userProfiles).go();
                    await db.delete(db.areas).go();
                    await db.delete(db.adminTrustedSenders).go();
                    await db.delete(db.revokedDelegations).go();
                  });
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('user_name');
                  await prefs.remove('user_contact');
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All data cleared')),
                  );
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const InitializerScreen(),
                    ),
                    (route) => false,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.api, color: Colors.blue),
                title: const Text('Fetch Mock Gov API Data'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref
                      .read(mockGovApiServiceProvider.notifier)
                      .fetchAndInjectMockData();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mock Gov API data injected')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.purple,
                ),
                title: const Text('Make Me Admin-Trusted (Tier 2)'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final myPubKey = await ref
                      .read(cryptoServiceProvider.notifier)
                      .getPublicKeyString();
                  await ref
                      .read(mockGovApiServiceProvider.notifier)
                      .delegateAdminTrust(myPubKey);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('You are now an Admin-Trusted Volunteer!'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_moderator, color: Colors.red),
                title: const Text('Revoke My Admin Trust'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final myPubKey = await ref
                      .read(cryptoServiceProvider.notifier)
                      .getPublicKeyString();
                  await ref
                      .read(mockGovApiServiceProvider.notifier)
                      .revokeAdminTrust(myPubKey);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Your Admin Trust has been revoked!'),
                    ),
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
        return 'OFFICIAL';
      case 2:
        return 'VERIFIED';
      case 3:
        return 'TRUSTED';
      case 4:
        return 'UNVERIFIED';
      default:
        return 'Unknown';
    }
  }

  IconData _getHazardIcon(String type) {
    switch (type.toLowerCase()) {
      case 'flood':
      case 'flooded area':
        return Icons.water;
      case 'fire':
      case 'fire zone':
        return Icons.local_fire_department;
      case 'roadblock':
        return Icons.remove_road;
      case 'medical':
        return Icons.medical_services;
      case 'evacuation zone':
        return Icons.directions_run;
      case 'safe zone':
        return Icons.health_and_safety;
      default:
        return Icons.warning;
    }
  }

  void _blockSender(String senderId) {
    ref
        .read(untrustedSendersControllerProvider.notifier)
        .addUntrustedSender(senderId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sender blocked. Their reports have been removed.'),
      ),
    );
  }

  void _resolveMarker(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Hazard?'),
        content: const Text(
          'Marking this hazard as resolved will remove it from the map for you and nearby users upon sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(hazardMarkersControllerProvider.notifier)
                  .deleteMarker(id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hazard marked as resolved.')),
              );
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  void _resolveArea(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Area?'),
        content: const Text(
          'Marking this area as resolved will remove it from the map for you and nearby users upon sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              ref.read(areasControllerProvider.notifier).deleteArea(id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Area marked as resolved.')),
              );
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  void _dismissNews(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dismiss News?'),
        content: const Text(
          'This will remove the news item from your feed and for nearby users upon sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(context);
              ref.read(newsItemsControllerProvider.notifier).deleteNewsItem(id);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('News dismissed.')));
            },
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showAddHazardDialog(LatLng point) {
    String selectedType = 'Flood';
    final descController = TextEditingController(text: 'Water level rising');
    XFile? selectedImage;
    int? selectedTtlHours = 24;

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
          content: SingleChildScrollView(
            child: Column(
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
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            type.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
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
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: selectedTtlHours,
                  decoration: InputDecoration(
                    labelText: 'Expires In',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Hour')),
                    DropdownMenuItem(value: 12, child: Text('12 Hours')),
                    DropdownMenuItem(value: 24, child: Text('24 Hours')),
                    DropdownMenuItem(value: 72, child: Text('3 Days')),
                    DropdownMenuItem(value: 168, child: Text('7 Days')),
                    DropdownMenuItem(value: null, child: Text('No Expiration')),
                  ],
                  onChanged: (val) => setState(() => selectedTtlHours = val),
                ),
                const SizedBox(height: 16),
                if (selectedImage != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(selectedImage!.path),
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => selectedImage = null),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text(
                      'Remove Image',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final image = await picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 60,
                        maxWidth: 1024,
                        maxHeight: 1024,
                      );
                      if (image != null) {
                        final size = await File(image.path).length();
                        if (size > 1024 * 1024) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Image is too large (limit 1MB). Please try again.')),
                            );
                          }
                        } else {
                          setState(() => selectedImage = image);
                        }
                      }
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Attach Photo'),
                  ),
              ],
            ),
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
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;
                final senderId = await cryptoService.getPublicKeyString();

                String? imageId;
                if (selectedImage != null) {
                  imageId = 'img_$id.jpg';
                  final dir = await getApplicationDocumentsDirectory();
                  final savedImage = File('${dir.path}/$imageId');
                  await File(selectedImage!.path).copy(savedImage.path);

                  ref
                      .read(p2pServiceProvider.notifier)
                      .broadcastFile(savedImage);
                }

                final payloadToSign = utf8.encode(
                  '$id$type$timestamp${imageId ?? ""}${expiresAt ?? ""}',
                );
                final signature = await cryptoService.signData(payloadToSign);
                final untrustedSendersAsync = ref.read(
                  untrustedSendersControllerProvider,
                );
                final revokedSendersAsync = ref.read(
                  revokedDelegationsControllerProvider,
                );
                final revokedKeys =
                    revokedSendersAsync.value
                        ?.map((e) => e.delegateePublicKey)
                        .toList() ??
                    [];
                final adminTrustedSendersAsync = ref.read(
                  adminTrustedSendersControllerProvider,
                );
                final adminTrustedKeys =
                    adminTrustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];

                final trustedKeys =
                    trustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];
                final untrustedKeys =
                    untrustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];

                final trustTier = await cryptoService.verifyAndGetTrustTier(
                  data: payloadToSign,
                  signatureStr: signature,
                  senderPublicKeyStr: senderId,
                  trustedPublicKeys: trustedKeys,
                  adminTrustedPublicKeys: adminTrustedKeys,
                  untrustedPublicKeys: untrustedKeys,
                  revokedPublicKeys: revokedKeys,
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
                  imageId: imageId,
                  expiresAt: expiresAt,
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

  void _showAddAreaDialog({AreaEntity? existingArea}) {
    final validTypes = [
      'Flooded Area',
      'Evacuation Zone',
      'Safe Zone',
      'Fire Zone',
      'Other',
    ];
    String selectedType = validTypes.contains(existingArea?.type)
        ? existingArea!.type
        : 'Flooded Area';
    final descController = TextEditingController(
      text: existingArea?.description ?? '',
    );
    int? selectedTtlHours = 24;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.format_shapes, color: Colors.purple),
              const SizedBox(width: 8),
              Text(existingArea != null ? 'Edit Area' : 'Report Area'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: InputDecoration(
                  labelText: 'Area Type',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items:
                    [
                          'Flooded Area',
                          'Evacuation Zone',
                          'Safe Zone',
                          'Fire Zone',
                          'Other',
                        ]
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
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                initialValue: selectedTtlHours,
                decoration: InputDecoration(
                  labelText: 'Expires In',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 Hour')),
                  DropdownMenuItem(value: 12, child: Text('12 Hours')),
                  DropdownMenuItem(value: 24, child: Text('24 Hours')),
                  DropdownMenuItem(value: 72, child: Text('3 Days')),
                  DropdownMenuItem(value: 168, child: Text('7 Days')),
                  DropdownMenuItem(value: null, child: Text('No Expiration')),
                ],
                onChanged: (val) => setState(() => selectedTtlHours = val),
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

                final id =
                    existingArea?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString();
                final type = selectedType;
                final description = descController.text;
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;
                final senderId =
                    existingArea?.senderId ??
                    await cryptoService.getPublicKeyString();

                final payloadToSign = utf8.encode(
                  '$id$type$timestamp${expiresAt ?? ""}',
                );
                final signature = await cryptoService.signData(payloadToSign);
                final untrustedSendersAsync = ref.read(
                  untrustedSendersControllerProvider,
                );
                final revokedSendersAsync = ref.read(
                  revokedDelegationsControllerProvider,
                );
                final revokedKeys =
                    revokedSendersAsync.value
                        ?.map((e) => e.delegateePublicKey)
                        .toList() ??
                    [];
                final adminTrustedSendersAsync = ref.read(
                  adminTrustedSendersControllerProvider,
                );
                final adminTrustedKeys =
                    adminTrustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];

                final trustedKeys =
                    trustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];
                final untrustedKeys =
                    untrustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];

                final trustTier = await cryptoService.verifyAndGetTrustTier(
                  data: payloadToSign,
                  signatureStr: signature,
                  senderPublicKeyStr: senderId,
                  trustedPublicKeys: trustedKeys,
                  adminTrustedPublicKeys: adminTrustedKeys,
                  untrustedPublicKeys: untrustedKeys,
                  revokedPublicKeys: revokedKeys,
                );

                final coords = _currentAreaPoints
                    .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                    .toList();

                final newArea = AreaEntity(
                  id: id,
                  coordinates: coords,
                  type: type,
                  description: description,
                  timestamp: timestamp,
                  senderId: senderId,
                  signature: signature,
                  trustTier: trustTier,
                  expiresAt: expiresAt,
                );
                await ref
                    .read(areasControllerProvider.notifier)
                    .addArea(newArea);

                this.setState(() {
                  _isDrawingArea = false;
                  _editingAreaId = null;
                  _currentAreaPoints.clear();
                });
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
    try {
      final bounds = _mapController.camera.visibleBounds;
      final currentZoom = _mapController.camera.zoom.floor();

      showDialog(
        context: context,
        builder: (context) =>
            DownloadMapDialog(bounds: bounds, currentZoom: currentZoom),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please wait for the map to load first.')),
      );
    }
  }

  Future<void> _shareApk() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('APK sharing is only available on Android.'),
        ),
      );
      return;
    }

    try {
      const platform = MethodChannel('com.example.floodio/apk');
      final String? apkPath = await platform.invokeMethod('getApkPath');

      if (apkPath != null) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/floodio.apk');

        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        await File(apkPath).copy(tempFile.path);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tempFile.path)],
            text: 'Install Floodio to stay connected during emergencies!',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share APK: $e')));
      }
    }
  }

  void _showAddNewsDialog() {
    final titleController = TextEditingController(
      text: 'Official Evacuation Notice',
    );
    final contentController = TextEditingController(
      text: 'Move to higher ground immediately. Flood waters rising.',
    );
    int? selectedTtlHours = 24;
    XFile? selectedImage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.campaign, color: Colors.blue),
              SizedBox(width: 8),
              Text('Official Alert'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
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
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: selectedTtlHours,
                  decoration: InputDecoration(
                    labelText: 'Expires In',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Hour')),
                    DropdownMenuItem(value: 12, child: Text('12 Hours')),
                    DropdownMenuItem(value: 24, child: Text('24 Hours')),
                    DropdownMenuItem(value: 72, child: Text('3 Days')),
                    DropdownMenuItem(value: 168, child: Text('7 Days')),
                    DropdownMenuItem(value: null, child: Text('No Expiration')),
                  ],
                  onChanged: (val) => setState(() => selectedTtlHours = val),
                ),
                const SizedBox(height: 16),
                if (selectedImage != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(selectedImage!.path),
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => selectedImage = null),
                    icon: const Icon(Icons.delete, color: Colors.red),
                    label: const Text(
                      'Remove Image',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ] else
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final image = await picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 60,
                        maxWidth: 1024,
                        maxHeight: 1024,
                      );
                      if (image != null) {
                        final size = await File(image.path).length();
                        if (size > 1024 * 1024) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Image is too large (limit 1MB). Please try again.')),
                            );
                          }
                        } else {
                          setState(() => selectedImage = image);
                        }
                      }
                    },
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Attach Photo'),
                  ),
              ],
            ),
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
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;

                String? imageId;
                if (selectedImage != null) {
                  imageId = 'img_$id.jpg';
                  final dir = await getApplicationDocumentsDirectory();
                  final savedImage = File('${dir.path}/$imageId');
                  await File(selectedImage!.path).copy(savedImage.path);

                  ref
                      .read(p2pServiceProvider.notifier)
                      .broadcastFile(savedImage);
                }

                final payloadToSign = utf8.encode(
                  '$id$title$timestamp${imageId ?? ""}${expiresAt ?? ""}',
                );

                final (senderId, signature) =
                    await runGenerateOfficialMarkerSignature(payloadToSign);

                final trustedSendersAsync = ref.read(
                  trustedSendersControllerProvider,
                );
                final untrustedSendersAsync = ref.read(
                  untrustedSendersControllerProvider,
                );
                final revokedSendersAsync = ref.read(
                  revokedDelegationsControllerProvider,
                );
                final revokedKeys =
                    revokedSendersAsync.value
                        ?.map((e) => e.delegateePublicKey)
                        .toList() ??
                    [];
                final adminTrustedSendersAsync = ref.read(
                  adminTrustedSendersControllerProvider,
                );
                final adminTrustedKeys =
                    adminTrustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];
                final trustedKeys =
                    trustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];
                final untrustedKeys =
                    untrustedSendersAsync.value
                        ?.map((e) => e.publicKey)
                        .toList() ??
                    [];

                final cryptoService = ref.read(cryptoServiceProvider.notifier);
                final trustTier = await cryptoService.verifyAndGetTrustTier(
                  data: payloadToSign,
                  signatureStr: signature,
                  senderPublicKeyStr: senderId,
                  trustedPublicKeys: trustedKeys,
                  adminTrustedPublicKeys: adminTrustedKeys,
                  untrustedPublicKeys: untrustedKeys,
                  revokedPublicKeys: revokedKeys,
                );

                final newNews = NewsItemEntity(
                  id: id,
                  title: title,
                  content: content,
                  timestamp: timestamp,
                  senderId: senderId,
                  signature: signature,
                  trustTier: trustTier,
                  expiresAt: expiresAt,
                  imageId: imageId,
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
      ),
    );
  }

  UserProfileEntity? _getProfile(
    String publicKey,
    List<UserProfileEntity> profiles,
  ) {
    try {
      return profiles.firstWhere((p) => p.publicKey == publicKey);
    } catch (_) {
      return null;
    }
  }

  Widget _buildMap(
    AsyncValue<List<HazardMarkerEntity>> markersAsync,
    AsyncValue<List<AreaEntity>> areasAsync,
    List<UserProfileEntity> profiles,
    List<OfflineRegion> offlineRegions,
    Position? currentPosition,
  ) {
    final markers = markersAsync.value ?? [];
    final areas = areasAsync.value ?? [];
    final settings = ref.watch(appSettingsProvider);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: currentPosition != null
            ? LatLng(currentPosition.latitude, currentPosition.longitude)
            : const LatLng(37.7749, -122.4194),
        initialZoom: 13.0,
        onTap: (tapPosition, point) {
          if (_isDrawingArea) {
            setState(() {
              _currentAreaPoints.add(point);
            });
          } else {
            _showAddHazardDialog(point);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: settings.mapStyle.url,
          userAgentPackageName: 'com.example.floodio',
          tileProvider: CachedTileProvider(ref.read(mapCacheServiceProvider)),
        ),
        PolygonLayer(
          polygons: [
            if (_showOfflineRegions)
              ...offlineRegions.map(
                (r) => Polygon(
                  points: [
                    LatLng(r.bounds.north, r.bounds.west),
                    LatLng(r.bounds.north, r.bounds.east),
                    LatLng(r.bounds.south, r.bounds.east),
                    LatLng(r.bounds.south, r.bounds.west),
                  ],
                  color: Colors.teal.withValues(alpha: 0.15),
                  borderColor: Colors.teal,
                  borderStrokeWidth: 2,
                ),
              ),
            ...areas.map((a) {
              final points = a.coordinates
                  .map((c) => LatLng(c['lat']!, c['lng']!))
                  .toList();
              final color =
                  a.type.toLowerCase().contains('safe') ||
                      a.type.toLowerCase().contains('evacuation')
                  ? Colors.green
                  : Colors.red;
              return Polygon(
                points: points,
                color: color.withValues(alpha: 0.3),
                borderColor: color,
                borderStrokeWidth: 2,
              );
            }),
            if (_isDrawingArea && _currentAreaPoints.isNotEmpty)
              Polygon(
                points: _currentAreaPoints,
                color: Colors.blue.withValues(alpha: 0.3),
                borderColor: Colors.blue,
                borderStrokeWidth: 2,
              ),
          ],
        ),
        CircleLayer(
          circles: markers
              .where((m) => m.trustTier == 1 || m.trustTier == 2)
              .map(
                (m) => CircleMarker(
                  point: LatLng(m.latitude, m.longitude),
                  radius: m.trustTier == 1 ? 500 : 300,
                  useRadiusInMeter: true,
                  color: (m.trustTier == 1 ? Colors.blue : Colors.purple)
                      .withValues(alpha: 0.2),
                  borderColor: m.trustTier == 1 ? Colors.blue : Colors.purple,
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
                  alignment: Alignment.bottomCenter,
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
                                    : m.trustTier == 2
                                    ? Colors.purple
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
                              if (m.imageId != null && m.imageId!.isNotEmpty)
                                LocalImageDisplay(imageId: m.imageId!),
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
                                  final profile = _getProfile(
                                    m.senderId,
                                    profiles,
                                  );
                                  if (profile != null) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Divider(),
                                        Text('Reported by: ${profile.name}'),
                                        if (profile.contactInfo.isNotEmpty)
                                          Text(
                                            'Contact: ${profile.contactInfo}',
                                          ),
                                      ],
                                    );
                                  } else {
                                    return const Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                _resolveMarker(m.id);
                              },
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: const Text('Resolve'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.green,
                              ),
                            ),
                            if (m.trustTier == 4 || m.trustTier == 3)
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _blockSender(m.senderId);
                                },
                                icon: const Icon(Icons.block, size: 18),
                                label: const Text('Block'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                              ),
                            if (m.trustTier == 4)
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _markAsTrusted(m.senderId);
                                },
                                icon: const Icon(Icons.verified_user, size: 18),
                                label: const Text('Trust'),
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
                              : m.trustTier == 2
                              ? Colors.purple
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
        if (currentPosition != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(
                  currentPosition.latitude,
                  currentPosition.longitude,
                ),
                width: 24,
                height: 24,
                alignment: Alignment.center,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Widget _buildEmptyFeedState(bool isLoading) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
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
            'Try adjusting your filters or sync with nearby devices.',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildFeed(List<UserProfileEntity> profiles) {
    final combined = ref.watch(combinedFeedProvider);
    final filter = ref.watch(feedFilterControllerProvider);
    final filterNotifier = ref.read(feedFilterControllerProvider.notifier);

    final isLoading =
        ref.watch(filteredHazardMarkersProvider).isLoading ||
        ref.watch(filteredNewsItemsProvider).isLoading ||
        ref.watch(filteredAreasProvider).isLoading;

    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search reports...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (val) => filterNotifier.updateSearchQuery(val),
          ),
        ),
        _buildFilterBar(filter, filterNotifier),
        Expanded(
          child: combined.isEmpty
              ? _buildEmptyFeedState(isLoading)
              : ListView.builder(
                  controller: _feedScrollController,
                  padding: const EdgeInsets.only(top: 8, bottom: 80),
                  itemCount:
                      combined.length +
                      (combined.length >= ref.watch(feedLimitProvider) ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == combined.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final item = combined[index];
                    if (item is HazardMarkerEntity) {
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _getTierColor(
                              item.trustTier,
                            ).withValues(alpha: 0.5),
                            width: item.trustTier == 1 ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() => _currentIndex = 0);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              try {
                                _mapController.move(
                                  LatLng(item.latitude, item.longitude),
                                  15.0,
                                );
                              } catch (e) {
                                debugPrint('Map not ready yet: $e');
                              }
                            });
                          },
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
                                          : item.trustTier == 2
                                          ? Colors.purple.shade100
                                          : item.trustTier == 3
                                          ? Colors.green.shade100
                                          : Colors.grey.shade200,
                                      child: Icon(
                                        _getHazardIcon(item.type),
                                        color: item.trustTier == 1
                                            ? Colors.blue
                                            : item.trustTier == 2
                                            ? Colors.purple
                                            : item.trustTier == 3
                                            ? Colors.green
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                if (item.imageId != null &&
                                    item.imageId!.isNotEmpty)
                                  LocalImageDisplay(imageId: item.imageId!),
                                Builder(
                                  builder: (context) {
                                    final profile = _getProfile(
                                      item.senderId,
                                      profiles,
                                    );
                                    if (profile != null) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Text(
                                          'By: ${profile.name}${profile.contactInfo.isNotEmpty ? ' (${profile.contactInfo})' : ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      );
                                    } else {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Text(
                                          'By: Unknown User',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _resolveMarker(item.id),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 16,
                                      ),
                                      label: const Text('Resolve'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.green,
                                      ),
                                    ),
                                    if (item.trustTier == 4 ||
                                        item.trustTier == 3)
                                      TextButton.icon(
                                        onPressed: () =>
                                            _blockSender(item.senderId),
                                        icon: const Icon(Icons.block, size: 16),
                                        label: const Text('Block'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red,
                                        ),
                                      ),
                                    if (item.trustTier == 4)
                                      FilledButton.tonalIcon(
                                        onPressed: () =>
                                            _markAsTrusted(item.senderId),
                                        icon: const Icon(
                                          Icons.verified_user,
                                          size: 16,
                                        ),
                                        label: const Text('Trust'),
                                        style: FilledButton.styleFrom(
                                          foregroundColor:
                                              Colors.green.shade700,
                                          backgroundColor: Colors.green.shade50,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    } else if (item is NewsItemEntity) {
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        color: item.trustTier == 1
                            ? const Color(0xFFFFF3E0)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _getTierColor(item.trustTier),
                            width: item.trustTier == 1 ? 2 : 1,
                          ),
                        ),
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
                                        : item.trustTier == 2
                                        ? Colors.purple.shade100
                                        : item.trustTier == 3
                                        ? Colors.green.shade100
                                        : Colors.grey.shade200,
                                    child: Icon(
                                      Icons.campaign,
                                      color: item.trustTier == 1
                                          ? Colors.blue
                                          : item.trustTier == 2
                                          ? Colors.purple
                                          : item.trustTier == 3
                                          ? Colors.green
                                          : Colors.grey.shade700,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                              if (item.imageId != null &&
                                  item.imageId!.isNotEmpty)
                                LocalImageDisplay(imageId: item.imageId!),
                              Builder(
                                builder: (context) {
                                  final profile = _getProfile(
                                    item.senderId,
                                    profiles,
                                  );
                                  if (profile != null) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        'By: ${profile.name}${profile.contactInfo.isNotEmpty ? ' (${profile.contactInfo})' : ''}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    );
                                  } else {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text(
                                        'By: Unknown User',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _dismissNews(item.id),
                                    icon: const Icon(Icons.clear, size: 16),
                                    label: const Text('Dismiss'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.grey,
                                    ),
                                  ),
                                  if (item.trustTier == 4 ||
                                      item.trustTier == 3)
                                    TextButton.icon(
                                      onPressed: () =>
                                          _blockSender(item.senderId),
                                      icon: const Icon(Icons.block, size: 16),
                                      label: const Text('Block'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
                                  if (item.trustTier == 4)
                                    FilledButton.tonalIcon(
                                      onPressed: () =>
                                          _markAsTrusted(item.senderId),
                                      icon: const Icon(
                                        Icons.verified_user,
                                        size: 16,
                                      ),
                                      label: const Text('Trust'),
                                      style: FilledButton.styleFrom(
                                        foregroundColor: Colors.green.shade700,
                                        backgroundColor: Colors.green.shade50,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    } else if (item is AreaEntity) {
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _getTierColor(
                              item.trustTier,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            setState(() => _currentIndex = 0);
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              try {
                                if (item.coordinates.isNotEmpty) {
                                  _mapController.move(
                                    LatLng(
                                      item.coordinates.first['lat']!,
                                      item.coordinates.first['lng']!,
                                    ),
                                    14.0,
                                  );
                                }
                              } catch (e) {
                                debugPrint('Map not ready yet: $e');
                              }
                            });
                          },
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
                                          : item.trustTier == 2
                                          ? Colors.purple.shade100
                                          : item.trustTier == 3
                                          ? Colors.green.shade100
                                          : Colors.grey.shade200,
                                      child: Icon(
                                        Icons.format_shapes,
                                        color: item.trustTier == 1
                                            ? Colors.blue
                                            : item.trustTier == 2
                                            ? Colors.purple
                                            : item.trustTier == 3
                                            ? Colors.green
                                            : Colors.grey.shade700,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Area: ${item.type}',
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
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                Builder(
                                  builder: (context) {
                                    final profile = _getProfile(
                                      item.senderId,
                                      profiles,
                                    );
                                    if (profile != null) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Text(
                                          'By: ${profile.name}${profile.contactInfo.isNotEmpty ? ' (${profile.contactInfo})' : ''}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      );
                                    } else {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Text(
                                          'By: Unknown User',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => _resolveArea(item.id),
                                      icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 16,
                                      ),
                                      label: const Text('Resolve'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.green,
                                      ),
                                    ),
                                    if (item.trustTier == 4 ||
                                        item.trustTier == 3)
                                      TextButton.icon(
                                        onPressed: () =>
                                            _blockSender(item.senderId),
                                        icon: const Icon(Icons.block, size: 16),
                                        label: const Text('Block'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.red,
                                        ),
                                      ),
                                    if (item.trustTier == 4)
                                      FilledButton.tonalIcon(
                                        onPressed: () =>
                                            _markAsTrusted(item.senderId),
                                        icon: const Icon(
                                          Icons.verified_user,
                                          size: 16,
                                        ),
                                        label: const Text('Trust'),
                                        style: FilledButton.styleFrom(
                                          foregroundColor:
                                              Colors.green.shade700,
                                          backgroundColor: Colors.green.shade50,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(FeedFilter filter, dynamic filterNotifier) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: ['All', 'News', 'Hazards', 'Areas']
                  .map(
                    (type) => Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(type),
                        selected: filter.typeFilter == type,
                        onSelected: (selected) =>
                            filterNotifier.updateTypeFilter(type),
                        selectedColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('All Trust Levels'),
                  selected: filter.trustFilter == null,
                  onSelected: (selected) =>
                      filterNotifier.updateTrustFilter(null),
                ),
                const SizedBox(width: 8),
                ...[1, 2, 3, 4].map(
                  (tier) => Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(_getTrustTierName(tier)),
                      selected: filter.trustFilter == tier,
                      onSelected: (selected) => filterNotifier
                          .updateTrustFilter(selected ? tier : null),
                      selectedColor: _getTierColor(tier).withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getTierColor(int tier) {
    switch (tier) {
      case 1:
        return Colors.blue.shade800;
      case 2:
        return Colors.purple.shade700;
      case 3:
        return Colors.green.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  Widget _buildTrustBadge(int tier) {
    final color = _getTierColor(tier);
    final icon = tier == 1
        ? Icons.verified
        : tier == 2
        ? Icons.admin_panel_settings
        : tier == 3
        ? Icons.thumb_up
        : Icons.people;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            _getTrustTierName(tier),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
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
    final areasAsync = ref.watch(areasControllerProvider);
    final profilesAsync = ref.watch(userProfilesControllerProvider);
    final cryptoState = ref.watch(cryptoServiceProvider);
    final offlineRegionsAsync = ref.watch(offlineRegionsProvider);
    final downloadProgress = ref.watch(mapDownloaderProvider);
    final locationAsync = ref.watch(locationControllerProvider);

    final profiles = profilesAsync.value ?? [];
    final offlineRegions = offlineRegionsAsync.value ?? [];
    final currentPosition = locationAsync.value;

    if (currentPosition != null && !_hasCenteredOnLocation) {
      _hasCenteredOnLocation = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(
            LatLng(currentPosition.latitude, currentPosition.longitude),
            15.0,
          );
        } catch (e) {
          debugPrint('Map not ready yet: $e');
        }
      });
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'FLOODIO',
                style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 12),
              if (downloadProgress.isDownloading)
                Text(
                  'Downloading map: ${(downloadProgress.percentage * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                  ),
                ),
            ],
          ),
          bottom: downloadProgress.isDownloading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4.0),
                  child: LinearProgressIndicator(
                    value: downloadProgress.percentage,
                  ),
                )
              : null,
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share App (APK)',
              onPressed: _shareApk,
            ),
            if (downloadProgress.isDownloading)
              IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: 'Cancel Download',
                onPressed: () {
                  ref.read(mapDownloaderProvider.notifier).cancelDownload();
                },
              )
            else
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download Offline Map',
                onPressed: _showDownloadMapDialog,
              ),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: MeshStatusChip(),
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: [
            _buildMap(
              markersAsync,
              areasAsync,
              profiles,
              offlineRegions,
              currentPosition,
            ),
            _buildFeed(profiles),
            ProfileTab(
              onEditAreaShape: (area) {
                setState(() {
                  _isDrawingArea = true;
                  _editingAreaId = area.id;
                  _currentAreaPoints.clear();
                  _currentAreaPoints.addAll(
                    area.coordinates.map((c) => LatLng(c['lat']!, c['lng']!)),
                  );
                  _currentIndex = 0;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Edit the area shape on the map.'),
                  ),
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
            BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Feed'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
        floatingActionButton: _currentIndex == 2
            ? null
            : cryptoState.when(
                data: (_) {
                  if (_isDrawingArea) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FloatingActionButton.extended(
                          heroTag: 'cancel_area',
                          onPressed: () {
                            setState(() {
                              _isDrawingArea = false;
                              _editingAreaId = null;
                              _currentAreaPoints.clear();
                            });
                          },
                          backgroundColor: Colors.red,
                          icon: const Icon(Icons.close, color: Colors.white),
                          label: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16),
                        if (_currentAreaPoints.isNotEmpty)
                          FloatingActionButton.extended(
                            heroTag: 'undo_area',
                            onPressed: () {
                              setState(() {
                                _currentAreaPoints.removeLast();
                              });
                            },
                            backgroundColor: Colors.orange,
                            icon: const Icon(Icons.undo, color: Colors.white),
                            label: const Text(
                              'Undo',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        const SizedBox(width: 16),
                        if (_currentAreaPoints.length >= 3)
                          FloatingActionButton.extended(
                            heroTag: 'done_area',
                            onPressed: () async {
                              AreaEntity? existingArea;
                              if (_editingAreaId != null) {
                                final areas =
                                    ref.read(areasControllerProvider).value ??
                                    [];
                                try {
                                  existingArea = areas.firstWhere(
                                    (a) => a.id == _editingAreaId,
                                  );
                                } catch (_) {}
                              }
                              _showAddAreaDialog(existingArea: existingArea);
                            },
                            backgroundColor: Colors.green,
                            icon: const Icon(Icons.check, color: Colors.white),
                            label: const Text(
                              'Done',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                      ],
                    );
                  }

                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_currentIndex == 0) ...[
                        FloatingActionButton.small(
                          heroTag: 'layers',
                          onPressed: () {
                            setState(() {
                              _showOfflineRegions = !_showOfflineRegions;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _showOfflineRegions
                                      ? 'Showing offline regions'
                                      : 'Hiding offline regions',
                                ),
                              ),
                            );
                          },
                          child: const Icon(Icons.layers),
                        ),
                        const SizedBox(height: 16),
                        FloatingActionButton.small(
                          heroTag: 'center_map',
                          onPressed: () async {
                            try {
                              final pos = await ref
                                  .read(locationControllerProvider.notifier)
                                  .getCurrentPosition();
                              if (pos != null) {
                                _mapController.move(
                                  LatLng(pos.latitude, pos.longitude),
                                  15.0,
                                );
                              } else {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Location not available'),
                                    ),
                                  );
                                }
                              }
                            } catch (e) {
                              debugPrint('Map not ready yet: $e');
                            }
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
                        heroTag: 'area',
                        onPressed: () async {
                          setState(() {
                            _isDrawingArea = true;
                            _editingAreaId = null;
                            _currentAreaPoints.clear();
                            _currentIndex = 0; // Switch to map tab
                          });

                          final pos = await ref
                              .read(locationControllerProvider.notifier)
                              .getCurrentPosition();
                          if (pos != null) {
                            try {
                              _mapController.move(
                                LatLng(pos.latitude, pos.longitude),
                                15.0,
                              );
                            } catch (_) {}
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Tap on the map to draw an area polygon.',
                                ),
                              ),
                            );
                          }
                        },
                        backgroundColor: Colors.purple,
                        icon: const Icon(
                          Icons.format_shapes,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Report Area',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FloatingActionButton.extended(
                        heroTag: 'user',
                        onPressed: () async {
                          LatLng point;
                          final pos = await ref
                              .read(locationControllerProvider.notifier)
                              .getCurrentPosition();
                          if (pos != null) {
                            point = LatLng(pos.latitude, pos.longitude);
                          } else {
                            try {
                              point = _mapController.camera.center;
                            } catch (_) {
                              point = const LatLng(37.7749, -122.4194);
                            }
                          }
                          _showAddHazardDialog(point);
                        },
                        icon: const Icon(Icons.add_location_alt),
                        label: const Text('Report Hazard'),
                      ),
                    ],
                  );
                },
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

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Map Preferences',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.layers),
            title: const Text('Map Style'),
            subtitle: Text('Current: ${settings.mapStyle.label}'),
            trailing: DropdownButton<MapStyle>(
              value: settings.mapStyle,
              onChanged: (val) =>
                  val != null ? notifier.setMapStyle(val) : null,
              items: MapStyle.values
                  .map(
                    (style) => DropdownMenuItem(
                      value: style,
                      child: Text(style.label),
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Sync Preferences',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Mesh Auto-Sync Frequency'),
            subtitle: const Text(
              'How often the device searches for peers in the background.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                Slider(
                  value: settings.syncIntervalSeconds.toDouble(),
                  min: 15,
                  max: 300,
                  divisions: 19,
                  label: _formatInterval(settings.syncIntervalSeconds),
                  onChanged: (val) => notifier.setSyncInterval(val.toInt()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('15s', style: TextStyle(fontSize: 12)),
                    Text(
                      'Current: ${_formatInterval(settings.syncIntervalSeconds)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Text('5m', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Note: Faster sync intervals consume more battery. 30s-60s is recommended during active emergencies.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('App Version'),
            trailing: const Text('0.1.0 (PoC)'),
          ),
        ],
      ),
    );
  }

  String _formatInterval(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    if (secs == 0) return '${mins}m';
    return '${mins}m ${secs}s';
  }
}

class ProfileTab extends ConsumerStatefulWidget {
  final Function(AreaEntity) onEditAreaShape;
  const ProfileTab({super.key, required this.onEditAreaShape});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  String? _myPublicKey;
  String _myName = '';
  String _myContact = '';
  int _mapCacheSize = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadMapCacheSize();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final name = prefs.getString('user_name') ?? 'Unknown';
    final contact = prefs.getString('user_contact') ?? '';

    await ref.read(cryptoServiceProvider.future);
    final cryptoService = ref.read(cryptoServiceProvider.notifier);
    final pubKey = await cryptoService.getPublicKeyString();

    if (mounted) {
      setState(() {
        _myName = name;
        _myContact = contact;
        _myPublicKey = pubKey;
      });
    }
  }

  Future<void> _loadMapCacheSize() async {
    final mapCache = ref.read(mapCacheServiceProvider);
    final size = await mapCache.getCacheSize();
    if (mounted) {
      setState(() {
        _mapCacheSize = size;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  void _removeTrustedSender(String publicKey) {
    ref
        .read(trustedSendersControllerProvider.notifier)
        .removeTrustedSender(publicKey);
  }

  void _deleteMarker(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Report?'),
        content: const Text(
          'Are you sure you want to delete this hazard report?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(hazardMarkersControllerProvider.notifier)
                  .deleteMarker(id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteNews(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete News?'),
        content: const Text('Are you sure you want to delete this news item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              ref.read(newsItemsControllerProvider.notifier).deleteNewsItem(id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteArea(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Area?'),
        content: const Text(
          'Are you sure you want to delete this area report?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              ref.read(areasControllerProvider.notifier).deleteArea(id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _editProfile() {
    final nameController = TextEditingController(text: _myName);
    final contactController = TextEditingController(text: _myContact);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: contactController,
                decoration: const InputDecoration(labelText: 'Contact Info'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              final newContact = contactController.text.trim();
              if (newName.isEmpty) return;

              Navigator.pop(dialogContext);

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('user_name', newName);
              await prefs.setString('user_contact', newContact);

              final cryptoService = ref.read(cryptoServiceProvider.notifier);
              final publicKey = await cryptoService.getPublicKeyString();
              final timestamp = DateTime.now().millisecondsSinceEpoch;

              final payloadToSign = utf8.encode(
                '$publicKey$newName$newContact$timestamp',
              );
              final signature = await cryptoService.signData(payloadToSign);

              final profile = UserProfileEntity(
                publicKey: publicKey,
                name: newName,
                contactInfo: newContact,
                timestamp: timestamp,
                signature: signature,
              );

              await ref
                  .read(userProfilesControllerProvider.notifier)
                  .saveProfile(profile);

              if (mounted) {
                setState(() {
                  _myName = newName;
                  _myContact = newContact;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Profile updated')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _editMarker(HazardMarkerEntity marker) {
    String selectedType = marker.type;
    final descController = TextEditingController(text: marker.description);
    int? selectedTtlHours = 24; // Default to extending by 24h

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setState) => AlertDialog(
          title: const Text('Edit Hazard'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue:
                      [
                        'Flood',
                        'Fire',
                        'Roadblock',
                        'Medical',
                        'Other',
                      ].contains(selectedType)
                      ? selectedType
                      : 'Other',
                  decoration: const InputDecoration(labelText: 'Hazard Type'),
                  items: ['Flood', 'Fire', 'Roadblock', 'Medical', 'Other']
                      .map(
                        (type) =>
                            DropdownMenuItem(value: type, child: Text(type)),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: selectedTtlHours,
                  decoration: const InputDecoration(
                    labelText: 'Extend Expiration By',
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Hour')),
                    DropdownMenuItem(value: 12, child: Text('12 Hours')),
                    DropdownMenuItem(value: 24, child: Text('24 Hours')),
                    DropdownMenuItem(value: 72, child: Text('3 Days')),
                    DropdownMenuItem(value: 168, child: Text('7 Days')),
                    DropdownMenuItem(value: null, child: Text('No Expiration')),
                  ],
                  onChanged: (val) => setState(() => selectedTtlHours = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(innerContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(innerContext);
                final cryptoService = ref.read(cryptoServiceProvider.notifier);
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final newId = marker.id; // Keep same ID for LWW CRDT
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;

                final payloadToSign = utf8.encode(
                  '$newId$selectedType$timestamp${marker.imageId ?? ""}${expiresAt ?? ""}',
                );
                final signature = await cryptoService.signData(payloadToSign);

                final updatedMarker = HazardMarkerEntity(
                  id: newId,
                  latitude: marker.latitude,
                  longitude: marker.longitude,
                  type: selectedType,
                  description: descController.text,
                  timestamp: timestamp,
                  senderId: marker.senderId,
                  signature: signature,
                  trustTier: marker.trustTier,
                  imageId: marker.imageId,
                  expiresAt: expiresAt,
                );

                await ref
                    .read(hazardMarkersControllerProvider.notifier)
                    .addMarker(updatedMarker);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Hazard updated')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editNews(NewsItemEntity news) {
    final titleController = TextEditingController(text: news.title);
    final contentController = TextEditingController(text: news.content);
    int? selectedTtlHours = 24;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setState) => AlertDialog(
          title: const Text('Edit News'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(labelText: 'Content'),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: selectedTtlHours,
                  decoration: const InputDecoration(
                    labelText: 'Extend Expiration By',
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Hour')),
                    DropdownMenuItem(value: 12, child: Text('12 Hours')),
                    DropdownMenuItem(value: 24, child: Text('24 Hours')),
                    DropdownMenuItem(value: 72, child: Text('3 Days')),
                    DropdownMenuItem(value: 168, child: Text('7 Days')),
                    DropdownMenuItem(value: null, child: Text('No Expiration')),
                  ],
                  onChanged: (val) => setState(() => selectedTtlHours = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(innerContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(innerContext);
                final cryptoService = ref.read(cryptoServiceProvider.notifier);
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final newId = news.id; // Keep same ID for LWW CRDT
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;

                final payloadToSign = utf8.encode(
                  '$newId${titleController.text}$timestamp${news.imageId ?? ""}${expiresAt ?? ""}',
                );
                final signature = await cryptoService.signData(payloadToSign);

                final updatedNews = NewsItemEntity(
                  id: newId,
                  title: titleController.text,
                  content: contentController.text,
                  timestamp: timestamp,
                  senderId: news.senderId,
                  signature: signature,
                  trustTier: news.trustTier,
                  expiresAt: expiresAt,
                  imageId: news.imageId,
                );

                await ref
                    .read(newsItemsControllerProvider.notifier)
                    .addNewsItem(updatedNews);
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('News updated')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editArea(AreaEntity area) {
    String selectedType = area.type;
    final descController = TextEditingController(text: area.description);
    int? selectedTtlHours = 24;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setState) => AlertDialog(
          title: const Text('Edit Area'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue:
                      [
                        'Flooded Area',
                        'Evacuation Zone',
                        'Safe Zone',
                        'Fire Zone',
                        'Other',
                      ].contains(selectedType)
                      ? selectedType
                      : 'Other',
                  decoration: const InputDecoration(labelText: 'Area Type'),
                  items:
                      [
                            'Flooded Area',
                            'Evacuation Zone',
                            'Safe Zone',
                            'Fire Zone',
                            'Other',
                          ]
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedType = val);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: selectedTtlHours,
                  decoration: const InputDecoration(
                    labelText: 'Extend Expiration By',
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 Hour')),
                    DropdownMenuItem(value: 12, child: Text('12 Hours')),
                    DropdownMenuItem(value: 24, child: Text('24 Hours')),
                    DropdownMenuItem(value: 72, child: Text('3 Days')),
                    DropdownMenuItem(value: 168, child: Text('7 Days')),
                    DropdownMenuItem(value: null, child: Text('No Expiration')),
                  ],
                  onChanged: (val) => setState(() => selectedTtlHours = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(innerContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(innerContext);
                final cryptoService = ref.read(cryptoServiceProvider.notifier);
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final newId = area.id; // Keep same ID for LWW CRDT
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;

                final payloadToSign = utf8.encode(
                  '$newId$selectedType$timestamp${expiresAt ?? ""}',
                );
                final signature = await cryptoService.signData(payloadToSign);

                final updatedArea = AreaEntity(
                  id: newId,
                  coordinates: area.coordinates,
                  type: selectedType,
                  description: descController.text,
                  timestamp: timestamp,
                  senderId: area.senderId,
                  signature: signature,
                  trustTier: area.trustTier,
                  expiresAt: expiresAt,
                );

                await ref
                    .read(areasControllerProvider.notifier)
                    .addArea(updatedArea);
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Area updated')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trustedSendersAsync = ref.watch(trustedSendersControllerProvider);
    final untrustedSendersAsync = ref.watch(untrustedSendersControllerProvider);
    final markersAsync = ref.watch(hazardMarkersControllerProvider);
    final newsAsync = ref.watch(newsItemsControllerProvider);
    final areasAsync = ref.watch(areasControllerProvider);
    final offlineRegionsAsync = ref.watch(offlineRegionsProvider);

    final trustedSenders = trustedSendersAsync.value ?? [];
    final offlineRegions = offlineRegionsAsync.value ?? [];
    final untrustedSenders = untrustedSendersAsync.value ?? [];
    final myMarkers = (markersAsync.value ?? [])
        .where((m) => m.senderId == _myPublicKey)
        .toList();
    final myNews = (newsAsync.value ?? [])
        .where((n) => n.senderId == _myPublicKey)
        .toList();
    final myAreas = (areasAsync.value ?? [])
        .where((a) => a.senderId == _myPublicKey)
        .toList();

    final myReports = <dynamic>[...myMarkers, ...myNews, ...myAreas];
    myReports.sort(
      (a, b) => (b.timestamp as int).compareTo(a.timestamp as int),
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Card
                Card(
                  elevation: 0,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          child: Text(
                            _myName.isNotEmpty ? _myName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _myName,
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 20),
                                    onPressed: _editProfile,
                                    tooltip: 'Edit Profile',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.settings, size: 20),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const SettingsScreen(),
                                      ),
                                    ),
                                    tooltip: 'Settings',
                                  ),
                                ],
                              ),
                              if (_myContact.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.phone,
                                      size: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _myContact,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  if (_myPublicKey != null) {
                                    Clipboard.setData(
                                      ClipboardData(text: _myPublicKey!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Public Key copied to clipboard',
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.key,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _myPublicKey != null
                                          ? '${_myPublicKey!.substring(0, 12)}...'
                                          : 'Loading key...',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.copy,
                                      size: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Trusted Senders
                Row(
                  children: [
                    const Icon(Icons.verified_user, color: Colors.green),
                    const SizedBox(width: 8),
                    const Text(
                      'Trusted Senders',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Chip(
                      label: Text('${trustedSenders.length}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (trustedSenders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You have not trusted any senders yet. Trust senders from the feed to prioritize their reports.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: trustedSenders.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final sender = trustedSenders[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: const Icon(
                              Icons.person,
                              color: Colors.green,
                            ),
                          ),
                          title: Text(
                            sender.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Key: ${sender.publicKey.substring(0, 12)}...',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                            ),
                            tooltip: 'Remove Trust',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Remove Trusted Sender?'),
                                  content: Text(
                                    'Are you sure you want to remove ${sender.name} from your trusted senders? Their future reports will be marked as Crowdsourced.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      onPressed: () {
                                        Navigator.pop(context);
                                        _removeTrustedSender(sender.publicKey);
                                      },
                                      child: const Text('Remove'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 32),

                // Blocked Senders
                Row(
                  children: [
                    const Icon(Icons.block, color: Colors.red),
                    const SizedBox(width: 8),
                    const Text(
                      'Blocked Senders',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Chip(
                      label: Text('${untrustedSenders.length}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (untrustedSenders.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You have not blocked any senders.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: untrustedSenders.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final sender = untrustedSenders[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.red.shade100,
                            child: const Icon(
                              Icons.person_off,
                              color: Colors.red,
                            ),
                          ),
                          title: Text(
                            'Key: ${sender.publicKey.substring(0, 12)}...',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.restore, color: Colors.blue),
                            tooltip: 'Unblock',
                            onPressed: () {
                              ref
                                  .read(
                                    untrustedSendersControllerProvider.notifier,
                                  )
                                  .removeUntrustedSender(sender.publicKey);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 32),

                // Map Storage
                Row(
                  children: [
                    const Icon(Icons.map, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Text(
                      'Offline Maps',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.orangeAccent,
                          child: Icon(Icons.storage, color: Colors.white),
                        ),
                        title: const Text('Storage Used'),
                        subtitle: Text(_formatBytes(_mapCacheSize)),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          tooltip: 'Clear All Offline Maps',
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Clear All Offline Maps?'),
                                content: const Text(
                                  'This will delete all downloaded map tiles.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    onPressed: () async {
                                      Navigator.pop(dialogContext);
                                      await ref
                                          .read(mapCacheServiceProvider)
                                          .clearCache();
                                      await ref
                                          .read(offlineRegionsProvider.notifier)
                                          .clearRegions();
                                      _loadMapCacheSize();
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('Offline maps cleared'),
                                        ),
                                      );
                                    },
                                    child: const Text('Clear All'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (offlineRegions.isNotEmpty) ...[
                        const Divider(height: 1),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: offlineRegions.length,
                          separatorBuilder: (context, index) =>
                              const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final region = offlineRegions[index];
                            return ListTile(
                              leading: const Icon(
                                Icons.map_outlined,
                                color: Colors.orange,
                              ),
                              title: Text(
                                'Region ${index + 1} (Zoom ${region.minZoom}-${region.maxZoom})',
                              ),
                              subtitle: Text(
                                'Bounds: ${region.bounds.north.toStringAsFixed(2)}, ${region.bounds.west.toStringAsFixed(2)} to ${region.bounds.south.toStringAsFixed(2)}, ${region.bounds.east.toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  color: Colors.red,
                                ),
                                tooltip: 'Delete Region',
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Delete Region?'),
                                      content: const Text(
                                        'This will delete the map tiles for this region. Overlapping regions may lose some tiles.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.red,
                                          ),
                                          onPressed: () async {
                                            Navigator.pop(dialogContext);
                                            await ref
                                                .read(
                                                  offlineRegionsProvider
                                                      .notifier,
                                                )
                                                .removeRegion(region);
                                            await ref
                                                .read(mapCacheServiceProvider)
                                                .deleteRegionTiles(region);
                                            _loadMapCacheSize();
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text('Region deleted'),
                                              ),
                                            );
                                          },
                                          child: const Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // My Reports
                Row(
                  children: [
                    const Icon(Icons.my_library_books, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      'My Reports',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Chip(
                      label: Text('${myReports.length}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (myReports.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.grey),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You have not made any reports yet.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: myReports.length,
                    itemBuilder: (context, index) {
                      final item = myReports[index];
                      if (item is HazardMarkerEntity) {
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: const Icon(
                                Icons.warning,
                                color: Colors.orange,
                              ),
                            ),
                            title: Text(
                              'Hazard: ${item.type}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  item.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.imageId != null &&
                                    item.imageId!.isNotEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.image,
                                          size: 12,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Image attached',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    item.timestamp,
                                  ).toString().substring(0, 16),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _editMarker(item),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteMarker(item.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else if (item is NewsItemEntity) {
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: const Icon(
                                Icons.campaign,
                                color: Colors.blue,
                              ),
                            ),
                            title: Text(
                              'News: ${item.title}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  item.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.imageId != null &&
                                    item.imageId!.isNotEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.image,
                                          size: 12,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Image attached',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    item.timestamp,
                                  ).toString().substring(0, 16),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _editNews(item),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteNews(item.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else if (item is AreaEntity) {
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.purple.shade100,
                              child: const Icon(
                                Icons.format_shapes,
                                color: Colors.purple,
                              ),
                            ),
                            title: Text(
                              'Area: ${item.type}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  item.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateTime.fromMillisecondsSinceEpoch(
                                    item.timestamp,
                                  ).toString().substring(0, 16),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_location_alt,
                                    color: Colors.purple,
                                  ),
                                  tooltip: 'Edit Shape',
                                  onPressed: () =>
                                      widget.onEditAreaShape(item),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _editArea(item),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deleteArea(item.id),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class SyncBottomSheet extends ConsumerWidget {
  const SyncBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p2pState = ref.watch(uiP2pServiceProvider);
    final p2pNotifier = ref.read(uiP2pServiceProvider.notifier);
    final myRegionsAsync = ref.watch(offlineRegionsProvider);
    final myRegions = myRegionsAsync.value ?? [];

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
                      ? const Color(0xFFE8EAF6)
                      : Colors.white,
                  elevation: 0,
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
                            Icons.radar,
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
                              if (p2pState.isSyncing ||
                                  p2pState.isConnecting) ...[
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    backgroundColor: Colors.blue.shade100,
                                    color: Colors.blue.shade600,
                                    minHeight: 6,
                                  ),
                                ),
                              ],
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

                // Cloud Sync Section
                Consumer(
                  builder: (context, ref, child) {
                    final cloudSyncState = ref.watch(cloudSyncServiceProvider);
                    final cloudSyncNotifier = ref.read(
                      cloudSyncServiceProvider.notifier,
                    );

                    String lastSyncText = 'Never';
                    if (cloudSyncState.lastSyncTime != null) {
                      final dt = cloudSyncState.lastSyncTime!.toLocal();
                      lastSyncText =
                          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                    }

                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(
                              Icons.cloud_sync,
                              color: Colors.blue,
                            ),
                            title: const Text(
                              'Cloud Gateway Sync',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Last synced: $lastSyncText\nSyncs local data with the cloud when internet is available.',
                            ),
                            trailing: cloudSyncState.isSyncing
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : FilledButton.tonal(
                                    onPressed: () async {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Checking internet and syncing with cloud...',
                                          ),
                                        ),
                                      );
                                      final success = await cloudSyncNotifier
                                          .syncWithCloud();
                                      if (context.mounted) {
                                        if (success) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Cloud sync complete.',
                                              ),
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Cloud sync failed. No internet?',
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text('Sync Now'),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Peer Offline Maps Section
                if (p2pState.peerOfflineRegions.isNotEmpty) ...[
                  Text(
                    'Peer Offline Maps',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: p2pState.peerOfflineRegions.map((region) {
                        final alreadyHave = myRegions.any(
                          (r) =>
                              (r.bounds.north - region.bounds.north).abs() <
                                  0.0001 &&
                              (r.bounds.south - region.bounds.south).abs() <
                                  0.0001 &&
                              (r.bounds.east - region.bounds.east).abs() <
                                  0.0001 &&
                              (r.bounds.west - region.bounds.west).abs() <
                                  0.0001 &&
                              r.minZoom == region.minZoom &&
                              r.maxZoom == region.maxZoom,
                        );

                        return ListTile(
                          leading: const Icon(Icons.map, color: Colors.orange),
                          title: Text(
                            'Map Region (Zoom ${region.minZoom}-${region.maxZoom})',
                          ),
                          subtitle: Text(
                            'Bounds: ${region.bounds.north.toStringAsFixed(2)}, ${region.bounds.west.toStringAsFixed(2)} to ${region.bounds.south.toStringAsFixed(2)}, ${region.bounds.east.toStringAsFixed(2)}',
                          ),
                          trailing: alreadyHave
                              ? const Tooltip(
                                  message: 'Already downloaded',
                                  child: Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.download),
                                  tooltip: 'Request from peer',
                                  onPressed: p2pState.isSyncing
                                      ? null
                                      : () {
                                          p2pNotifier.requestMapRegion(region);
                                          Navigator.pop(context);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Requested map region from peer...',
                                              ),
                                            ),
                                          );
                                        },
                                ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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
                                if (val) {
                                  p2pNotifier.startHosting();
                                } else {
                                  p2pNotifier.stopHosting();
                                }
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
                                if (val) {
                                  p2pNotifier.startScanning();
                                } else {
                                  p2pNotifier.disconnect();
                                }
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
