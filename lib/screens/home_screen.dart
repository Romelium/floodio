import 'dart:convert';
import 'dart:io';

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

import '../crypto/crypto_service.dart';
import '../database/tables.dart';
import '../providers/admin_trusted_sender_provider.dart';
import '../providers/area_provider.dart';
import '../providers/cached_tile_provider.dart';
import '../providers/database_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/hazard_marker_provider.dart';
import '../providers/location_provider.dart';
import '../providers/map_downloader_provider.dart';
import '../providers/news_item_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../providers/p2p_provider.dart';
import '../providers/path_provider.dart';
import '../providers/revoked_delegation_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/trusted_sender_provider.dart';
import '../providers/untrusted_sender_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/map_cache_service.dart';
import '../services/mock_gov_api_service.dart';
import '../utils/permission_utils.dart';
import '../utils/ui_helpers.dart';
import '../widgets/download_map_dialog.dart';
import '../widgets/local_image_display.dart';
import '../widgets/mesh_status_chip.dart';
import 'initializer_screen.dart';
import 'profile_tab.dart';

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
  bool _isDrawingArea = false;
  String? _editingAreaId;
  final List<LatLng> _currentAreaPoints = [];
  bool _isDrawingPath = false;
  String? _editingPathId;
  final List<LatLng> _currentPathPoints = [];
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

  void _resolvePath(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resolve Path?'),
        content: const Text(
          'Marking this path as resolved will remove it from the map for you and nearby users upon sync.',
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
              ref.read(pathsControllerProvider.notifier).deletePath(id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Path marked as resolved.')),
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

  void _showAddHazardDialog(LatLng point) {
    String selectedType = 'Flood';
    final descController = TextEditingController(text: 'Water level rising');
    XFile? selectedImage;
    int? selectedTtlHours = 24;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
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
                      setInnerState(() => selectedType = val);
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
                  onChanged: (val) => setInnerState(() => selectedTtlHours = val),
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
                    onPressed: () => setInnerState(() => selectedImage = null),
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
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Image is too large (limit 1MB). Please try again.')),
                          );
                        } else {
                          setInnerState(() => selectedImage = image);
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
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
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
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
                    setInnerState(() => selectedType = val);
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
                onChanged: (val) => setInnerState(() => selectedTtlHours = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
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

                if (!mounted) return;
                setState(() {
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

  void _showAddPathDialog({PathEntity? existingPath}) {
    final validTypes = [
      'Evacuation Route',
      'Safe Path',
      'Blocked Road',
      'Other',
    ];
    String selectedType = validTypes.contains(existingPath?.type)
        ? existingPath!.type
        : 'Evacuation Route';
    final descController = TextEditingController(
      text: existingPath?.description ?? '',
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
              const Icon(Icons.route, color: Colors.teal),
              const SizedBox(width: 8),
              Text(existingPath != null ? 'Edit Path' : 'Report Path'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: InputDecoration(
                  labelText: 'Path Type',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: validTypes
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
                    existingPath?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString();
                final type = selectedType;
                final description = descController.text;
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;
                final senderId =
                    existingPath?.senderId ??
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

                final coords = _currentPathPoints
                    .map((p) => {'lat': p.latitude, 'lng': p.longitude})
                    .toList();

                final newPath = PathEntity(
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
                    .read(pathsControllerProvider.notifier)
                    .addPath(newPath);

                if (!mounted) return;
                setState(() {
                  _isDrawingPath = false;
                  _editingPathId = null;
                  _currentPathPoints.clear();
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
        builder: (dialogContext) =>
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
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
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
                  onChanged: (val) => setInnerState(() => selectedTtlHours = val),
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
                    onPressed: () => setInnerState(() => selectedImage = null),
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
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Image is too large (limit 1MB). Please try again.')),
                          );
                        } else {
                          setInnerState(() => selectedImage = image);
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
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

  Widget _buildMap(
    AsyncValue<List<HazardMarkerEntity>> markersAsync,
    AsyncValue<List<AreaEntity>> areasAsync,
    List<UserProfileEntity> profiles,
    List<OfflineRegion> offlineRegions,
    Position? currentPosition,
  ) {
    final markers = markersAsync.value ?? [];
    final areas = areasAsync.value ?? [];
    final pathsAsync = ref.watch(pathsControllerProvider);
    final paths = pathsAsync.value ?? [];
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
          } else if (_isDrawingPath) {
            setState(() {
              _currentPathPoints.add(point);
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
        PolylineLayer(
          polylines: [
            ...paths.map((p) {
              final points = p.coordinates
                  .map((c) => LatLng(c['lat']!, c['lng']!))
                  .toList();
              final color =
                  p.type.toLowerCase().contains('safe') ||
                      p.type.toLowerCase().contains('evacuation')
                  ? Colors.green
                  : Colors.red;
              return Polyline(
                points: points,
                color: color,
                strokeWidth: 4.0,
                pattern: p.type.toLowerCase().contains('blocked') ? StrokePattern.dashed(segments: const [10, 10]) : const StrokePattern.solid(),
              );
            }),
            if (_isDrawingPath && _currentPathPoints.isNotEmpty)
              Polyline(
                points: _currentPathPoints,
                color: Colors.teal,
                strokeWidth: 4.0,
                pattern: StrokePattern.dashed(segments: const [10, 10]),
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
                  alignment: Alignment.topCenter,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          title: Row(
                            children: [
                              Icon(
                                getHazardIcon(m.type),
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
                              buildTrustBadge(m.trustTier),
                              const SizedBox(height: 16),
                              Text(
                                m.description,
                                style: const TextStyle(fontSize: 16),
                              ),
                              if (m.imageId != null && m.imageId!.isNotEmpty)
                                LocalImageDisplay(imageId: m.imageId!),
                              const SizedBox(height: 8),
                              Text(
                                'Reported: ${formatTimestamp(m.timestamp)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final profile = getProfile(
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
                                Navigator.pop(dialogContext);
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
                                  Navigator.pop(dialogContext);
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
                                  Navigator.pop(dialogContext);
                                  _markAsTrusted(m.senderId);
                                },
                                icon: const Icon(Icons.verified_user, size: 18),
                                label: const Text('Trust'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.green,
                                ),
                              ),
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
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
                            getHazardIcon(m.type),
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
                            color: getTierColor(
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
                                        getHazardIcon(item.type),
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
                                            formatTimestamp(item.timestamp),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    buildTrustBadge(item.trustTier),
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
                                    final profile = getProfile(
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
                            color: getTierColor(item.trustTier),
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
                                          formatTimestamp(item.timestamp),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  buildTrustBadge(item.trustTier),
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
                                  final profile = getProfile(
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
                            color: getTierColor(
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
                                            formatTimestamp(item.timestamp),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    buildTrustBadge(item.trustTier),
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
                                    final profile = getProfile(
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
                    } else if (item is PathEntity) {
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: getTierColor(
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
                                        Icons.route,
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
                                            'Path: ${item.type}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            formatTimestamp(item.timestamp),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    buildTrustBadge(item.trustTier),
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
                                    final profile = getProfile(
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
                                      onPressed: () => _resolvePath(item.id),
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
              children: ['All', 'News', 'Hazards', 'Areas', 'Paths']
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
                      label: Text(getTrustTierName(tier)),
                      selected: filter.trustFilter == tier,
                      onSelected: (selected) => filterNotifier
                          .updateTrustFilter(selected ? tier : null),
                      selectedColor: getTierColor(tier).withValues(alpha: 0.2),
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
                  _isDrawingPath = false;
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
              onEditPathShape: (path) {
                setState(() {
                  _isDrawingPath = true;
                  _isDrawingArea = false;
                  _editingPathId = path.id;
                  _currentPathPoints.clear();
                  _currentPathPoints.addAll(
                    path.coordinates.map((c) => LatLng(c['lat']!, c['lng']!)),
                  );
                  _currentIndex = 0;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Edit the path shape on the map.'),
                  ),
                );
              },
              onNavigateToMap: (point) {
                setState(() => _currentIndex = 0);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  try {
                    _mapController.move(point, 14.0);
                  } catch (e) {
                    debugPrint('Map not ready yet: $e');
                  }
                });
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
                  if (_isDrawingArea || _isDrawingPath) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        FloatingActionButton.extended(
                          heroTag: 'cancel_draw',
                          onPressed: () {
                            setState(() {
                              _isDrawingArea = false;
                              _isDrawingPath = false;
                              _editingAreaId = null;
                              _editingPathId = null;
                              _currentAreaPoints.clear();
                              _currentPathPoints.clear();
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
                        if ((_isDrawingArea && _currentAreaPoints.isNotEmpty) || (_isDrawingPath && _currentPathPoints.isNotEmpty))
                          FloatingActionButton.extended(
                            heroTag: 'undo_draw',
                            onPressed: () {
                              setState(() {
                                if (_isDrawingArea) {
                                  _currentAreaPoints.removeLast();
                                } else {
                                  _currentPathPoints.removeLast();
                                }
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
                        if ((_isDrawingArea && _currentAreaPoints.length >= 3) || (_isDrawingPath && _currentPathPoints.length >= 2))
                          FloatingActionButton.extended(
                            heroTag: 'done_draw',
                            onPressed: () async {
                              if (_isDrawingArea) {
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
                              } else {
                                PathEntity? existingPath;
                                if (_editingPathId != null) {
                                  final paths =
                                      ref.read(pathsControllerProvider).value ??
                                      [];
                                  try {
                                    existingPath = paths.firstWhere(
                                      (p) => p.id == _editingPathId,
                                    );
                                  } catch (_) {}
                                }
                                _showAddPathDialog(existingPath: existingPath);
                              }
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
                                if (mounted) {
                                  ScaffoldMessenger.of(this.context).showSnackBar(
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
                            _isDrawingPath = false;
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

                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
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
                        heroTag: 'path',
                        onPressed: () async {
                          setState(() {
                            _isDrawingPath = true;
                            _isDrawingArea = false;
                            _editingPathId = null;
                            _currentPathPoints.clear();
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

                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Tap on the map to draw a path.',
                                ),
                              ),
                            );
                          }
                        },
                        backgroundColor: Colors.teal,
                        icon: const Icon(
                          Icons.route,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Report Path',
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
                          if (!mounted) return;
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
