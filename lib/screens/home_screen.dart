import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fixnum/fixnum.dart';
import 'package:floodio/widgets/sync_bottom_sheet.dart';
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
import '../protos/models.pb.dart' as pb;
import '../providers/admin_trusted_sender_provider.dart';
import '../providers/area_provider.dart';
import '../providers/cached_tile_provider.dart';
import '../providers/database_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/hazard_marker_provider.dart';
import '../providers/local_user_provider.dart';
import '../providers/location_provider.dart';
import '../providers/map_downloader_provider.dart';
import '../providers/news_item_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../providers/path_provider.dart';
import '../providers/revoked_delegation_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/trusted_sender_provider.dart';
import '../providers/ui_p2p_provider.dart';
import '../providers/ui_state_provider.dart';
import '../providers/untrusted_sender_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/map_cache_service.dart';
import '../services/gov_api_service.dart';
import '../utils/permission_utils.dart';
import '../utils/ui_helpers.dart';
import '../widgets/download_map_dialog.dart';
import '../widgets/local_image_display.dart';
import '../widgets/mesh_status_chip.dart';
import 'command_tab.dart';
import 'guide_tab.dart';
import 'initializer_screen.dart';
import 'mesh_topology_screen.dart';
import 'profile_tab.dart';

class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar();

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  Timer? _debounce;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(feedFilterControllerProvider, (prev, next) {
      if (next.searchQuery.isEmpty && _controller.text.isNotEmpty) {
        _controller.clear();
      }
    });

    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: 'Search reports...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  ref
                      .read(feedFilterControllerProvider.notifier)
                      .updateSearchQuery('');
                  setState(() {});
                },
              )
            : null,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
      ),
      onChanged: (val) {
        setState(() {});
        if (_debounce?.isActive ?? false) _debounce!.cancel();
        _debounce = Timer(const Duration(milliseconds: 300), () {
          if (mounted) {
            ref
                .read(feedFilterControllerProvider.notifier)
                .updateSearchQuery(val);
          }
        });
      },
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _tapCount = 0;
  DateTime? _lastTapTime;
  final MapController _mapController = MapController();
  bool _hasCenteredOnLocation = false;
  bool _isTrackingLocation = true;
  double _mapRotation = 0.0;
  bool _showTutorial = false;
  bool _isRequestingPermissions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPermissions();
    _checkTutorial();
  }

  Future<void> _checkTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('has_seen_tutorial') ?? false)) {
      setState(() => _showTutorial = true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(cloudSyncServiceProvider);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isRequestingPermissions) {
      _checkPermissionsSilently();
    }
  }

  Future<void> _checkPermissionsSilently() async {
    final granted = await checkAppPermissions();
    if (granted) {
      final service = FlutterBackgroundService();
      if (!(await service.isRunning())) {
        await service.startService();
      }
      if (mounted) {
        ref.invalidate(locationControllerProvider);
      }
    }
  }

  Future<void> _initPermissions() async {
    if (_isRequestingPermissions) return;
    _isRequestingPermissions = true;

    try {
      final alreadyGranted = await checkAppPermissions();
      if (!alreadyGranted) {
        if (!mounted) return;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.security, color: Colors.blue),
                SizedBox(width: 8),
                Text('Permissions Required'),
              ],
            ),
            content: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: Icon(Icons.bluetooth),
                    title: Text('Bluetooth & Nearby Devices'),
                    subtitle: Text(
                      'Used to discover and connect to nearby devices without internet.',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.location_on),
                    title: Text('Location'),
                    subtitle: Text(
                      'Required by Android to scan for Bluetooth and Wi-Fi Direct devices.',
                    ),
                  ),
                  ListTile(
                    leading: Icon(Icons.notifications),
                    title: Text('Notifications'),
                    subtitle: Text(
                      'Keeps the background sync service alive so you can receive alerts.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Grant Permissions'),
              ),
            ],
          ),
        );
      }

      final granted = await requestAppPermissions();
      await Future.delayed(const Duration(milliseconds: 500));

      if (!granted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Permissions are required for offline syncing.',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (granted) {
        if (mounted) {
          final batteryExempt =
              await Permission.ignoreBatteryOptimizations.isGranted;
          if (!batteryExempt && mounted) {
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Background Sync'),
                content: const Text(
                  'To keep syncing while the app is closed, please allow Floodio to run in the background (ignore battery optimizations).',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Skip'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await requestBatteryOptimizationExemption();
                    },
                    child: const Text('Allow'),
                  ),
                ],
              ),
            );
          }
        }

        final service = FlutterBackgroundService();
        if (!(await service.isRunning())) {
          await service.startService();
        }
        if (mounted) {
          ref.invalidate(locationControllerProvider);
        }
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final locationEnabled = await checkLocationServices();
      if (!locationEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Please enable Location Services (GPS) for Bluetooth discovery.',
            ),
            action: SnackBarAction(
              label: 'Enable',
              onPressed: () => Geolocator.openLocationSettings(),
            ),
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _isRequestingPermissions = false;
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
          child: SingleChildScrollView(
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
                      await db.delete(db.paths).go();
                      await db.delete(db.adminTrustedSenders).go();
                      await db.delete(db.revokedDelegations).go();
                    });
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.remove('user_name');
                    await prefs.remove('user_contact');
                    ref.invalidate(localUserControllerProvider);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('All data cleared'),
                        behavior: SnackBarBehavior.floating,
                      ),
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
                  leading: const Icon(
                    Icons.admin_panel_settings,
                    color: Colors.purple,
                  ),
                  title: const Text('Make Me Admin-Trusted (Tier 2)'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final localUser = ref.read(localUserControllerProvider).value;
                    final myPubKey = localUser?.publicKey;
                    if (myPubKey == null) return;
                    await ref
                        .read(govApiServiceProvider.notifier)
                        .delegateAdminTrust(myPubKey);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('You are now an Admin-Trusted Volunteer!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.remove_moderator, color: Colors.red),
                  title: const Text('Revoke My Admin Trust'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final localUser = ref.read(localUserControllerProvider).value;
                    final myPubKey = localUser?.publicKey;
                    if (myPubKey == null) return;
                    await ref
                        .read(govApiServiceProvider.notifier)
                        .revokeAdminTrust(myPubKey);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Your Admin Trust has been revoked!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.security, color: Colors.orange),
                  title: const Text('Toggle Official Mode'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final current = ref.read(appSettingsProvider).isOfficialMode;
                    await ref
                        .read(appSettingsProvider.notifier)
                        .setOfficialMode(!current);
  
                    if (current && ref.read(navigationIndexProvider) == 4) {
                      ref.read(navigationIndexProvider.notifier).setIndex(3);
                    }
  
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Official Mode: ${!current ? "ON" : "OFF"}',
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Mock Actions',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.bluetooth, color: Colors.blue),
                  title: const Text('Mock Discovered Peer'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref.read(uiP2pServiceProvider.notifier).mockDiscoveredDevice();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mock peer added')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people, color: Colors.green),
                  title: const Text('Mock Connected Client'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref.read(uiP2pServiceProvider.notifier).mockConnectedClient();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mock client added')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.warning, color: Colors.orange),
                  title: const Text('Mock Received Hazard'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref.read(uiP2pServiceProvider.notifier).mockReceivedHazard();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mock hazard added')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.router, color: Colors.teal),
                  title: const Text('Mock Host State'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref.read(uiP2pServiceProvider.notifier).mockHostState();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mock host state set')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.smartphone, color: Colors.indigo),
                  title: const Text('Mock Client State'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref.read(uiP2pServiceProvider.notifier).mockClientState();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mock client state set')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sync, color: Colors.cyan),
                  title: const Text('Mock Sync Progress'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref.read(uiP2pServiceProvider.notifier).mockSyncProgress();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _blockSender(String senderId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Block Sender?'),
        content: const Text(
          'Are you sure you want to block this sender? All their reports will be hidden and deleted from your device only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(dialogContext);
              ref
                  .read(untrustedSendersControllerProvider.notifier)
                  .addUntrustedSender(senderId);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Sender blocked. Their reports have been removed.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  void _resolveMarker(String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve Hazard?'),
        content: const Text(
          'Marking this hazard as resolved will remove it from the map for everyone in the mesh network upon sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(dialogContext);
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              ref
                  .read(hazardMarkersControllerProvider.notifier)
                  .deleteMarker(id, timestamp: timestamp);
              final payload = pb.SyncPayload();
              payload.deletedItems.add(
                pb.DeletedItem(id: id, timestamp: Int64(timestamp)),
              );
              final encoded = base64Encode(payload.writeToBuffer());
              ref
                  .read(uiP2pServiceProvider.notifier)
                  .broadcastText(
                    jsonEncode({'type': 'payload', 'data': encoded}),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Hazard marked as resolved.'),
                  behavior: SnackBarBehavior.floating,
                ),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve Area?'),
        content: const Text(
          'Marking this area as resolved will remove it from the map for everyone in the mesh network upon sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(dialogContext);
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              ref
                  .read(areasControllerProvider.notifier)
                  .deleteArea(id, timestamp: timestamp);
              final payload = pb.SyncPayload();
              payload.deletedItems.add(
                pb.DeletedItem(id: id, timestamp: Int64(timestamp)),
              );
              final encoded = base64Encode(payload.writeToBuffer());
              ref
                  .read(uiP2pServiceProvider.notifier)
                  .broadcastText(
                    jsonEncode({'type': 'payload', 'data': encoded}),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Area marked as resolved.'),
                  behavior: SnackBarBehavior.floating,
                ),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resolve Path?'),
        content: const Text(
          'Marking this path as resolved will remove it from the map for everyone in the mesh network upon sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(dialogContext);
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              ref
                  .read(pathsControllerProvider.notifier)
                  .deletePath(id, timestamp: timestamp);
              final payload = pb.SyncPayload();
              payload.deletedItems.add(
                pb.DeletedItem(id: id, timestamp: Int64(timestamp)),
              );
              final encoded = base64Encode(payload.writeToBuffer());
              ref
                  .read(uiP2pServiceProvider.notifier)
                  .broadcastText(
                    jsonEncode({'type': 'payload', 'data': encoded}),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Path marked as resolved.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
  }

  Future<void> _debunkReport(String id, String type) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (type == 'marker') {
      await ref
          .read(hazardMarkersControllerProvider.notifier)
          .deleteMarker(id, timestamp: timestamp);
    } else if (type == 'news') {
      await ref
          .read(newsItemsControllerProvider.notifier)
          .deleteNewsItem(id, timestamp: timestamp);
    } else if (type == 'area') {
      await ref
          .read(areasControllerProvider.notifier)
          .deleteArea(id, timestamp: timestamp);
    } else if (type == 'path') {
      await ref
          .read(pathsControllerProvider.notifier)
          .deletePath(id, timestamp: timestamp);
    }

    final payload = pb.SyncPayload();
    payload.deletedItems.add(
      pb.DeletedItem(id: id, timestamp: Int64(timestamp)),
    );

    final encoded = base64Encode(payload.writeToBuffer());
    ref
        .read(uiP2pServiceProvider.notifier)
        .broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report debunked and removal broadcasted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _confirmDebunkReport(String id, String type) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Debunk Report?'),
        content: const Text(
          'Marking this report as false will actively delete it from the entire mesh network for everyone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(dialogContext);
              _debunkReport(id, type);
            },
            child: const Text('Debunk'),
          ),
        ],
      ),
    );
  }

  void _dismissNews(String id) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete News Globally?'),
        content: const Text(
          'This will permanently delete this news item for everyone in the mesh network upon sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(dialogContext);
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              ref
                  .read(newsItemsControllerProvider.notifier)
                  .deleteNewsItem(id, timestamp: timestamp);
              final payload = pb.SyncPayload();
              payload.deletedItems.add(
                pb.DeletedItem(id: id, timestamp: Int64(timestamp)),
              );
              final encoded = base64Encode(payload.writeToBuffer());
              ref
                  .read(uiP2pServiceProvider.notifier)
                  .broadcastText(
                    jsonEncode({'type': 'payload', 'data': encoded}),
                  );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('News deleted globally.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _endorseHazard(HazardMarkerEntity marker) async {
    final localUser = ref.read(localUserControllerProvider).value;
    final myPublicKey = localUser?.publicKey;
    if (myPublicKey == null) return;
    final cryptoService = ref.read(cryptoServiceProvider.notifier);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final settings = ref.read(appSettingsProvider);

    String senderId;
    String signature;

    final isCriticalStr = marker.isCritical ? "1" : "0";
    final payloadToSign = utf8.encode(
      '${marker.id}${marker.latitude}${marker.longitude}${marker.type}${marker.description}$timestamp${marker.imageId ?? ""}${marker.expiresAt ?? ""}$isCriticalStr',
    );

    if (settings.isOfficialMode) {
      final official = await generateOfficialMarkerSignature(payloadToSign);
      senderId = official.$1;
      signature = official.$2;
    } else {
      senderId = myPublicKey;
      signature = await cryptoService.signData(payloadToSign);
    }

    final trustedSendersAsync = ref.read(trustedSendersControllerProvider);
    final untrustedSendersAsync = ref.read(untrustedSendersControllerProvider);
    final revokedSendersAsync = ref.read(revokedDelegationsControllerProvider);
    final adminTrustedSendersAsync = ref.read(
      adminTrustedSendersControllerProvider,
    );

    final trustedKeys =
        trustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];
    final untrustedKeys =
        untrustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];
    final revokedKeys =
        revokedSendersAsync.value?.map((e) => e.delegateePublicKey).toList() ??
        [];
    final adminTrustedKeys =
        adminTrustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];

    final trustTier = await cryptoService.verifyAndGetTrustTier(
      data: payloadToSign,
      signatureStr: signature,
      senderPublicKeyStr: senderId,
      trustedPublicKeys: trustedKeys,
      adminTrustedPublicKeys: adminTrustedKeys,
      untrustedPublicKeys: untrustedKeys,
      revokedPublicKeys: revokedKeys,
    );

    final updatedMarker = HazardMarkerEntity(
      id: marker.id,
      latitude: marker.latitude,
      longitude: marker.longitude,
      type: marker.type,
      description: marker.description,
      timestamp: timestamp,
      senderId: senderId,
      signature: signature,
      trustTier: trustTier,
      imageId: marker.imageId,
      expiresAt: marker.expiresAt,
      isCritical: marker.isCritical,
    );

    await ref
        .read(hazardMarkersControllerProvider.notifier)
        .addMarker(updatedMarker);

    final payload = pb.SyncPayload();
    payload.markers.add(
      pb.HazardMarker(
        id: updatedMarker.id,
        latitude: updatedMarker.latitude,
        longitude: updatedMarker.longitude,
        type: updatedMarker.type,
        description: updatedMarker.description,
        timestamp: Int64(updatedMarker.timestamp),
        senderId: updatedMarker.senderId,
        signature: updatedMarker.signature ?? '',
        trustTier: updatedMarker.trustTier,
        imageId: updatedMarker.imageId ?? '',
        expiresAt: Int64(updatedMarker.expiresAt ?? 0),
        isCritical: updatedMarker.isCritical,
      ),
    );

    final encoded = base64Encode(payload.writeToBuffer());
    ref
        .read(uiP2pServiceProvider.notifier)
        .broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hazard verified and endorsed!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _endorseArea(AreaEntity area) async {
    final localUser = ref.read(localUserControllerProvider).value;
    final myPublicKey = localUser?.publicKey;
    if (myPublicKey == null) return;
    final cryptoService = ref.read(cryptoServiceProvider.notifier);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final settings = ref.read(appSettingsProvider);

    String senderId;
    String signature;

    final isCriticalStr = area.isCritical ? "1" : "0";
    final coordsStr = area.coordinates
        .map((c) => '${c['lat']},${c['lng']}')
        .join('|');
    final payloadToSign = utf8.encode(
      '${area.id}$coordsStr${area.type}${area.description}$timestamp${area.expiresAt ?? ""}$isCriticalStr',
    );

    if (settings.isOfficialMode) {
      final official = await generateOfficialMarkerSignature(payloadToSign);
      senderId = official.$1;
      signature = official.$2;
    } else {
      senderId = myPublicKey;
      signature = await cryptoService.signData(payloadToSign);
    }

    final trustedSendersAsync = ref.read(trustedSendersControllerProvider);
    final untrustedSendersAsync = ref.read(untrustedSendersControllerProvider);
    final revokedSendersAsync = ref.read(revokedDelegationsControllerProvider);
    final adminTrustedSendersAsync = ref.read(
      adminTrustedSendersControllerProvider,
    );

    final trustedKeys =
        trustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];
    final untrustedKeys =
        untrustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];
    final revokedKeys =
        revokedSendersAsync.value?.map((e) => e.delegateePublicKey).toList() ??
        [];
    final adminTrustedKeys =
        adminTrustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];

    final trustTier = await cryptoService.verifyAndGetTrustTier(
      data: payloadToSign,
      signatureStr: signature,
      senderPublicKeyStr: senderId,
      trustedPublicKeys: trustedKeys,
      adminTrustedPublicKeys: adminTrustedKeys,
      untrustedPublicKeys: untrustedKeys,
      revokedPublicKeys: revokedKeys,
    );

    final updatedArea = AreaEntity(
      id: area.id,
      coordinates: area.coordinates,
      type: area.type,
      description: area.description,
      timestamp: timestamp,
      senderId: senderId,
      signature: signature,
      trustTier: trustTier,
      expiresAt: area.expiresAt,
      isCritical: area.isCritical,
    );

    await ref.read(areasControllerProvider.notifier).addArea(updatedArea);

    final payload = pb.SyncPayload();
    final areaMarker = pb.AreaMarker(
      id: updatedArea.id,
      type: updatedArea.type,
      description: updatedArea.description,
      timestamp: Int64(updatedArea.timestamp),
      senderId: updatedArea.senderId,
      signature: updatedArea.signature ?? '',
      trustTier: updatedArea.trustTier,
      expiresAt: Int64(updatedArea.expiresAt ?? 0),
      isCritical: updatedArea.isCritical,
    );
    for (final coord in updatedArea.coordinates) {
      areaMarker.coordinates.add(
        pb.Coordinate(latitude: coord['lat']!, longitude: coord['lng']!),
      );
    }
    payload.areas.add(areaMarker);

    final encoded = base64Encode(payload.writeToBuffer());
    ref
        .read(uiP2pServiceProvider.notifier)
        .broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Area verified and endorsed!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _endorsePath(PathEntity path) async {
    final localUser = ref.read(localUserControllerProvider).value;
    final myPublicKey = localUser?.publicKey;
    if (myPublicKey == null) return;
    final cryptoService = ref.read(cryptoServiceProvider.notifier);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final settings = ref.read(appSettingsProvider);

    String senderId;
    String signature;

    final isCriticalStr = path.isCritical ? "1" : "0";
    final coordsStr = path.coordinates
        .map((c) => '${c['lat']},${c['lng']}')
        .join('|');
    final payloadToSign = utf8.encode(
      '${path.id}$coordsStr${path.type}${path.description}$timestamp${path.expiresAt ?? ""}$isCriticalStr',
    );

    if (settings.isOfficialMode) {
      final official = await generateOfficialMarkerSignature(payloadToSign);
      senderId = official.$1;
      signature = official.$2;
    } else {
      senderId = myPublicKey;
      signature = await cryptoService.signData(payloadToSign);
    }

    final trustedSendersAsync = ref.read(trustedSendersControllerProvider);
    final untrustedSendersAsync = ref.read(untrustedSendersControllerProvider);
    final revokedSendersAsync = ref.read(revokedDelegationsControllerProvider);
    final adminTrustedSendersAsync = ref.read(
      adminTrustedSendersControllerProvider,
    );

    final trustedKeys =
        trustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];
    final untrustedKeys =
        untrustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];
    final revokedKeys =
        revokedSendersAsync.value?.map((e) => e.delegateePublicKey).toList() ??
        [];
    final adminTrustedKeys =
        adminTrustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];

    final trustTier = await cryptoService.verifyAndGetTrustTier(
      data: payloadToSign,
      signatureStr: signature,
      senderPublicKeyStr: senderId,
      trustedPublicKeys: trustedKeys,
      adminTrustedPublicKeys: adminTrustedKeys,
      untrustedPublicKeys: untrustedKeys,
      revokedPublicKeys: revokedKeys,
    );

    final updatedPath = PathEntity(
      id: path.id,
      coordinates: path.coordinates,
      type: path.type,
      description: path.description,
      timestamp: timestamp,
      senderId: senderId,
      signature: signature,
      trustTier: trustTier,
      expiresAt: path.expiresAt,
      isCritical: path.isCritical,
    );

    await ref.read(pathsControllerProvider.notifier).addPath(updatedPath);

    final payload = pb.SyncPayload();
    final pathMarker = pb.PathMarker(
      id: updatedPath.id,
      type: updatedPath.type,
      description: updatedPath.description,
      timestamp: Int64(updatedPath.timestamp),
      senderId: updatedPath.senderId,
      signature: updatedPath.signature ?? '',
      trustTier: updatedPath.trustTier,
      expiresAt: Int64(updatedPath.expiresAt ?? 0),
      isCritical: updatedPath.isCritical,
    );
    for (final coord in updatedPath.coordinates) {
      pathMarker.coordinates.add(
        pb.Coordinate(latitude: coord['lat']!, longitude: coord['lng']!),
      );
    }
    payload.paths.add(pathMarker);

    final encoded = base64Encode(payload.writeToBuffer());
    ref
        .read(uiP2pServiceProvider.notifier)
        .broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Path verified and endorsed!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _endorseNews(NewsItemEntity news) async {
    final localUser = ref.read(localUserControllerProvider).value;
    final myPublicKey = localUser?.publicKey;
    if (myPublicKey == null) return;
    final cryptoService = ref.read(cryptoServiceProvider.notifier);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final settings = ref.read(appSettingsProvider);

    String senderId;
    String signature;

    final isCriticalStr = news.isCritical ? "1" : "0";
    final payloadToSign = utf8.encode(
      '${news.id}${news.title}${news.content}$timestamp${news.imageId ?? ""}${news.expiresAt ?? ""}$isCriticalStr',
    );

    if (settings.isOfficialMode) {
      final official = await generateOfficialMarkerSignature(payloadToSign);
      senderId = official.$1;
      signature = official.$2;
    } else {
      senderId = myPublicKey;
      signature = await cryptoService.signData(payloadToSign);
    }

    final trustedSendersAsync = ref.read(trustedSendersControllerProvider);
    final untrustedSendersAsync = ref.read(untrustedSendersControllerProvider);
    final revokedSendersAsync = ref.read(revokedDelegationsControllerProvider);
    final adminTrustedSendersAsync = ref.read(
      adminTrustedSendersControllerProvider,
    );

    final trustedKeys =
        trustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];
    final untrustedKeys =
        untrustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];
    final revokedKeys =
        revokedSendersAsync.value?.map((e) => e.delegateePublicKey).toList() ??
        [];
    final adminTrustedKeys =
        adminTrustedSendersAsync.value?.map((e) => e.publicKey).toList() ?? [];

    final trustTier = await cryptoService.verifyAndGetTrustTier(
      data: payloadToSign,
      signatureStr: signature,
      senderPublicKeyStr: senderId,
      trustedPublicKeys: trustedKeys,
      adminTrustedPublicKeys: adminTrustedKeys,
      untrustedPublicKeys: untrustedKeys,
      revokedPublicKeys: revokedKeys,
    );

    final updatedNews = NewsItemEntity(
      id: news.id,
      title: news.title,
      content: news.content,
      timestamp: timestamp,
      senderId: senderId,
      signature: signature,
      trustTier: trustTier,
      expiresAt: news.expiresAt,
      imageId: news.imageId,
      isCritical: news.isCritical,
    );

    await ref
        .read(newsItemsControllerProvider.notifier)
        .addNewsItem(updatedNews);

    final payload = pb.SyncPayload();
    payload.news.add(
      pb.NewsItem(
        id: updatedNews.id,
        title: updatedNews.title,
        content: updatedNews.content,
        timestamp: Int64(updatedNews.timestamp),
        senderId: updatedNews.senderId,
        signature: updatedNews.signature ?? '',
        trustTier: updatedNews.trustTier,
        expiresAt: Int64(updatedNews.expiresAt ?? 0),
        imageId: updatedNews.imageId ?? '',
        isCritical: updatedNews.isCritical,
      ),
    );

    final encoded = base64Encode(payload.writeToBuffer());
    ref
        .read(uiP2pServiceProvider.notifier)
        .broadcastText(jsonEncode({'type': 'payload', 'data': encoded}));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('News verified and endorsed!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<LatLng> _getPointForReport() async {
    final pos = await ref
        .read(locationControllerProvider.notifier)
        .getCurrentPosition();
    if (pos != null) {
      return LatLng(pos.latitude, pos.longitude);
    } else {
      try {
        return _mapController.camera.center;
      } catch (_) {
        return const LatLng(10.730185, 122.559115);
      }
    }
  }

  void _showReportOptions() {
    final isOfficial = ref.read(appSettingsProvider).isOfficialMode;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16, top: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Create Report',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.add_location_alt, color: Colors.white),
                  ),
                  title: const Text('Report Hazard'),
                  subtitle: const Text('Mark a specific point on the map'),
                  onTap: () async {
                    Navigator.pop(context);
                    LatLng point = await _getPointForReport();
                    if (!mounted) return;
                    _showAddHazardDialog(point);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.purple,
                    child: Icon(Icons.format_shapes, color: Colors.white),
                  ),
                  title: const Text('Report Area'),
                  subtitle: const Text('Draw a polygon on the map'),
                  onTap: () async {
                    Navigator.pop(context);
                    ref
                        .read(drawingControllerProvider.notifier)
                        .startDrawingArea();
                    ref.read(navigationIndexProvider.notifier).setIndex(0);
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
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: Icon(Icons.route, color: Colors.white),
                  ),
                  title: const Text('Report Path'),
                  subtitle: const Text('Draw a line on the map'),
                  onTap: () async {
                    Navigator.pop(context);
                    ref
                        .read(drawingControllerProvider.notifier)
                        .startDrawingPath();
                    ref.read(navigationIndexProvider.notifier).setIndex(0);
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
                          content: Text('Tap on the map to draw a path.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.campaign, color: Colors.white),
                  ),
                  title: const Text('Official Alert'),
                  subtitle: const Text('Broadcast a general news or alert'),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddNewsDialog();
                  },
                ),
                if (isOfficial) ...[
                  const Divider(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8.0, top: 8.0),
                    child: Text(
                      'Official Reports',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.indigo,
                      child: Icon(Icons.local_shipping, color: Colors.white),
                    ),
                    title: const Text('Report Supply'),
                    subtitle: const Text('Mark a supply distribution point'),
                    onTap: () async {
                      Navigator.pop(context);
                      LatLng point = await _getPointForReport();
                      if (!mounted) return;
                      _showAddHazardDialog(point, initialType: 'Supply');
                    },
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.pink,
                      child: Icon(Icons.medical_services, color: Colors.white),
                    ),
                    title: const Text('Medical Triage'),
                    subtitle: const Text('Mark a medical triage area'),
                    onTap: () async {
                      Navigator.pop(context);
                      LatLng point = await _getPointForReport();
                      if (!mounted) return;
                      _showAddHazardDialog(
                        point,
                        initialType: 'Medical Triage',
                      );
                    },
                  ),
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.deepOrange,
                      child: Icon(Icons.star, color: Colors.white),
                    ),
                    title: const Text('Custom Official Marker'),
                    subtitle: const Text('Mark a custom official point'),
                    onTap: () async {
                      Navigator.pop(context);
                      LatLng point = await _getPointForReport();
                      if (!mounted) return;
                      _showAddHazardDialog(point, initialType: 'Custom');
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddHazardDialog(LatLng point, {String? initialType}) {
    final isOfficial = ref.read(appSettingsProvider).isOfficialMode;
    List<String> types = ['Flood', 'Fire', 'Roadblock', 'Medical', 'Other'];
    if (isOfficial) {
      types.addAll(['Supply', 'Medical Triage', 'Custom']);
    }
    if (initialType != null && !types.contains(initialType)) {
      types.add(initialType);
    }

    String selectedType = initialType ?? 'Flood';
    final descController = TextEditingController(
      text: initialType == 'Supply'
          ? 'Water and food distribution'
          : initialType == 'Medical Triage'
          ? 'First aid and triage'
          : initialType == 'Custom'
          ? 'Official custom marker'
          : 'Water level rising',
    );
    XFile? selectedImage;
    int? selectedTtlHours = 24;
    bool isCritical = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                getHazardIcon(selectedType),
                color: getHazardColor(selectedType, isOfficial ? 1 : 4),
              ),
              const SizedBox(width: 8),
              const Text('Report Hazard'),
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
                  items: types
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
                  onChanged: (val) =>
                      setInnerState(() => selectedTtlHours = val),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text(
                    'Mark as Critical Emergency',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: isCritical,
                  onChanged: (val) =>
                      setInnerState(() => isCritical = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.red,
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
                  Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          setInnerState(() => selectedImage = null),
                      icon: const Icon(Icons.delete, color: Colors.red),
                      label: const Text(
                        'Remove Image',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ] else
                  Center(
                    child: OutlinedButton.icon(
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
                              const SnackBar(
                                content: Text(
                                  'Image is too large (limit 1MB). Please try again.',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            try {
                              setInnerState(() => selectedImage = image);
                            } catch (_) {}
                          }
                        }
                      },
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Attach Photo'),
                    ),
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
                      .read(uiP2pServiceProvider.notifier)
                      .broadcastFile(savedImage);
                }

                final isCriticalStr = isCritical ? "1" : "0";
                final payloadToSign = utf8.encode(
                  '$id${point.latitude}${point.longitude}$type$description$timestamp${imageId ?? ""}${expiresAt ?? ""}$isCriticalStr',
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
                  isCritical: isCritical,
                );
                await ref
                    .read(hazardMarkersControllerProvider.notifier)
                    .addMarker(newMarker);

                final payload = pb.SyncPayload();
                payload.markers.add(
                  pb.HazardMarker(
                    id: newMarker.id,
                    latitude: newMarker.latitude,
                    longitude: newMarker.longitude,
                    type: newMarker.type,
                    description: newMarker.description,
                    timestamp: Int64(newMarker.timestamp),
                    senderId: newMarker.senderId,
                    signature: newMarker.signature ?? '',
                    trustTier: newMarker.trustTier,
                    imageId: newMarker.imageId ?? '',
                    expiresAt: Int64(newMarker.expiresAt ?? 0),
                    isCritical: newMarker.isCritical,
                  ),
                );
                final encoded = base64Encode(payload.writeToBuffer());
                ref
                    .read(uiP2pServiceProvider.notifier)
                    .broadcastText(
                      jsonEncode({'type': 'payload', 'data': encoded}),
                    );
              },
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Report'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddAreaDialog({
    AreaEntity? existingArea,
    required List<LatLng> points,
  }) {
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
    bool isCritical = existingArea?.isCritical ?? false;

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
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text(
                  'Mark as Critical Emergency',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                value: isCritical,
                onChanged: (val) =>
                    setInnerState(() => isCritical = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.red,
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

                final isCriticalStr = isCritical ? "1" : "0";
                final coordsStr = points
                    .map((p) => '${p.latitude},${p.longitude}')
                    .join('|');
                final payloadToSign = utf8.encode(
                  '$id$coordsStr$type$description$timestamp${expiresAt ?? ""}$isCriticalStr',
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

                final coords = points
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
                  isCritical: isCritical,
                );
                await ref
                    .read(areasControllerProvider.notifier)
                    .addArea(newArea);

                final payload = pb.SyncPayload();
                final areaMarker = pb.AreaMarker(
                  id: newArea.id,
                  type: newArea.type,
                  description: newArea.description,
                  timestamp: Int64(newArea.timestamp),
                  senderId: newArea.senderId,
                  signature: newArea.signature ?? '',
                  trustTier: newArea.trustTier,
                  expiresAt: Int64(newArea.expiresAt ?? 0),
                  isCritical: newArea.isCritical,
                );
                for (final coord in newArea.coordinates) {
                  areaMarker.coordinates.add(
                    pb.Coordinate(
                      latitude: coord['lat']!,
                      longitude: coord['lng']!,
                    ),
                  );
                }
                payload.areas.add(areaMarker);
                final encoded = base64Encode(payload.writeToBuffer());
                ref
                    .read(uiP2pServiceProvider.notifier)
                    .broadcastText(
                      jsonEncode({'type': 'payload', 'data': encoded}),
                    );

                if (!mounted) return;
                ref.read(drawingControllerProvider.notifier).cancel();
              },
              icon: const Icon(Icons.send, size: 18),
              label: const Text('Report'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddPathDialog({
    PathEntity? existingPath,
    required List<LatLng> points,
  }) {
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
    bool isCritical = existingPath?.isCritical ?? false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
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
              CheckboxListTile(
                title: const Text(
                  'Mark as Critical Emergency',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                value: isCritical,
                onChanged: (val) =>
                    setInnerState(() => isCritical = val ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: Colors.red,
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

                final isCriticalStr = isCritical ? "1" : "0";
                final coordsStr = points
                    .map((p) => '${p.latitude},${p.longitude}')
                    .join('|');
                final payloadToSign = utf8.encode(
                  '$id$coordsStr$type$description$timestamp${expiresAt ?? ""}$isCriticalStr',
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

                final coords = points
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
                  isCritical: isCritical,
                );
                await ref
                    .read(pathsControllerProvider.notifier)
                    .addPath(newPath);

                final payload = pb.SyncPayload();
                final pathMarker = pb.PathMarker(
                  id: newPath.id,
                  type: newPath.type,
                  description: newPath.description,
                  timestamp: Int64(newPath.timestamp),
                  senderId: newPath.senderId,
                  signature: newPath.signature ?? '',
                  trustTier: newPath.trustTier,
                  expiresAt: Int64(newPath.expiresAt ?? 0),
                  isCritical: newPath.isCritical,
                );
                for (final coord in newPath.coordinates) {
                  pathMarker.coordinates.add(
                    pb.Coordinate(
                      latitude: coord['lat']!,
                      longitude: coord['lng']!,
                    ),
                  );
                }
                payload.paths.add(pathMarker);
                final encoded = base64Encode(payload.writeToBuffer());
                ref
                    .read(uiP2pServiceProvider.notifier)
                    .broadcastText(
                      jsonEncode({'type': 'payload', 'data': encoded}),
                    );

                if (!mounted) return;
                ref.read(drawingControllerProvider.notifier).cancel();
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
        const SnackBar(
          content: Text('Please wait for the map to load first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _shareApk() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('APK sharing is only available on Android.'),
          behavior: SnackBarBehavior.floating,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share APK: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
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
    bool isCritical = false;

    final templates = [
      {
        'title': 'Evacuation Order',
        'content': 'Move to higher ground immediately. Flood waters rising.',
        'critical': true,
      },
      {
        'title': 'Boil Water Advisory',
        'content':
            'Tap water is unsafe to drink. Boil water for at least 1 minute before consumption.',
        'critical': false,
      },
      {
        'title': 'Shelter Open',
        'content': 'Emergency shelter is now open and accepting evacuees.',
        'critical': false,
      },
      {
        'title': 'All Clear',
        'content': 'The emergency has passed. It is safe to return.',
        'critical': false,
      },
    ];

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Templates:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: templates
                        .map(
                          (t) => Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: ActionChip(
                              label: Text(t['title'] as String),
                              onPressed: () {
                                setInnerState(() {
                                  titleController.text = t['title'] as String;
                                  contentController.text =
                                      t['content'] as String;
                                  isCritical = t['critical'] as bool;
                                });
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 16),
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
                  onChanged: (val) =>
                      setInnerState(() => selectedTtlHours = val),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text(
                    'Mark as Critical Emergency',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: isCritical,
                  onChanged: (val) =>
                      setInnerState(() => isCritical = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.red,
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
                            const SnackBar(
                              content: Text(
                                'Image is too large (limit 1MB). Please try again.',
                              ),
                              behavior: SnackBarBehavior.floating,
                            ),
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
                      .read(uiP2pServiceProvider.notifier)
                      .broadcastFile(savedImage);
                }

                final isCriticalStr = isCritical ? "1" : "0";
                final payloadToSign = utf8.encode(
                  '$id$title$content$timestamp${imageId ?? ""}${expiresAt ?? ""}$isCriticalStr',
                );

                final (senderId, signature) =
                    await generateOfficialMarkerSignature(payloadToSign);

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
                  isCritical: isCritical,
                );
                await ref
                    .read(newsItemsControllerProvider.notifier)
                    .addNewsItem(newNews);

                final payload = pb.SyncPayload();
                payload.news.add(
                  pb.NewsItem(
                    id: newNews.id,
                    title: newNews.title,
                    content: newNews.content,
                    timestamp: Int64(newNews.timestamp),
                    senderId: newNews.senderId,
                    signature: newNews.signature ?? '',
                    trustTier: newNews.trustTier,
                    expiresAt: Int64(newNews.expiresAt ?? 0),
                    imageId: newNews.imageId ?? '',
                    isCritical: newNews.isCritical,
                  ),
                );
                final encoded = base64Encode(payload.writeToBuffer());
                ref
                    .read(uiP2pServiceProvider.notifier)
                    .broadcastText(
                      jsonEncode({'type': 'payload', 'data': encoded}),
                    );
              },
              icon: const Icon(Icons.broadcast_on_personal, size: 18),
              label: const Text('Broadcast'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    return Consumer(
      builder: (context, ref, child) {
        final localUserAsync = ref.watch(localUserControllerProvider);
        final myPublicKey = localUserAsync.value?.publicKey;
        final markersAsync = ref.watch(hazardMarkersControllerProvider);
        final areasAsync = ref.watch(areasControllerProvider);
        final pathsAsync = ref.watch(pathsControllerProvider);
        final profilesAsync = ref.watch(userProfilesControllerProvider);
        final offlineRegionsAsync = ref.watch(offlineRegionsProvider);
        final settings = ref.watch(appSettingsProvider);

        final markers = markersAsync.value ?? [];
        final areas = areasAsync.value ?? [];
        final paths = pathsAsync.value ?? [];
        final profiles = profilesAsync.value ?? [];
        final offlineRegions = offlineRegionsAsync.value ?? [];

        final adminTrustedAsync = ref.watch(
          adminTrustedSendersControllerProvider,
        );
        final revokedAsync = ref.watch(revokedDelegationsControllerProvider);
        final adminTrusted = adminTrustedAsync.value ?? [];
        final revoked = revokedAsync.value ?? [];
        final revokedKeys = revoked.map((e) => e.delegateePublicKey).toSet();
        final isTier2 =
            myPublicKey != null &&
            adminTrusted.any(
              (a) =>
                  a.publicKey == myPublicKey &&
                  !revokedKeys.contains(a.publicKey),
            );
        final isAdmin = settings.isOfficialMode || isTier2;
        final drawingState = ref.watch(drawingControllerProvider);
        final showOfflineRegions = ref.watch(showOfflineRegionsProvider);

        ref.listen<LatLng?>(mapTargetProvider, (prev, next) {
          if (next != null) {
            try {
              _mapController.move(next, 15.0);
            } catch (e) {
              debugPrint('Map not ready yet: $e');
            }
          }
        });

        ref.listen<AsyncValue<Position?>>(locationControllerProvider, (
          prev,
          next,
        ) {
          if (next.value != null) {
            if (!_hasCenteredOnLocation || _isTrackingLocation) {
              final zoom = _hasCenteredOnLocation
                  ? _mapController.camera.zoom
                  : 15.0;
              _hasCenteredOnLocation = true;
              try {
                _mapController.move(
                  LatLng(next.value!.latitude, next.value!.longitude),
                  zoom,
                );
              } catch (e) {
                debugPrint('Map not ready yet: $e');
              }
            }
          }
        });

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(10.730185, 122.559115),
                initialZoom: 13.0,
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture && _isTrackingLocation) {
                    setState(() {
                      _isTrackingLocation = false;
                    });
                  }
                  if (camera.rotation != _mapRotation) {
                    setState(() {
                      _mapRotation = camera.rotation;
                    });
                  }
                },
                onTap: (tapPosition, point) {
                  final drawingState = ref.read(drawingControllerProvider);
                  if (drawingState.mode == DrawingMode.area) {
                    ref
                        .read(drawingControllerProvider.notifier)
                        .addPoint(point);
                  } else if (drawingState.mode == DrawingMode.path) {
                    ref
                        .read(drawingControllerProvider.notifier)
                        .addPoint(point);
                  } else {
                    _showAddHazardDialog(point);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: settings.mapStyle.url,
                  userAgentPackageName: 'com.example.floodio',
                  tileProvider: CachedTileProvider(
                    ref.read(mapCacheServiceProvider),
                  ),
                ),
                PolygonLayer(
                  polygons: [
                    if (showOfflineRegions)
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
                      final color = a.isCritical
                          ? Colors.red
                          : (a.type.toLowerCase().contains('safe') ||
                                    a.type.toLowerCase().contains('evacuation')
                                ? Colors.green
                                : Colors.orange);
                      return Polygon(
                        points: points,
                        color: color.withValues(alpha: 0.3),
                        borderColor: color,
                        borderStrokeWidth: 2,
                        label: a.type,
                        labelStyle: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          backgroundColor: Colors.white.withValues(alpha: 0.8),
                        ),
                        labelPlacementCalculator:
                            const PolygonLabelPlacementCalculator.polylabel(),
                      );
                    }),
                    if (drawingState.mode == DrawingMode.area &&
                        drawingState.points.length >= 3)
                      Polygon(
                        points: drawingState.points,
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
                      final color = p.isCritical
                          ? Colors.red
                          : (p.type.toLowerCase().contains('safe') ||
                                    p.type.toLowerCase().contains('evacuation')
                                ? Colors.green
                                : Colors.orange);
                      return Polyline(
                        points: points,
                        color: color,
                        strokeWidth: 4.0,
                        pattern: p.type.toLowerCase().contains('blocked')
                            ? StrokePattern.dashed(segments: const [10.0, 10.0])
                            : const StrokePattern.solid(),
                      );
                    }),
                    if (drawingState.mode != DrawingMode.none &&
                        drawingState.points.isNotEmpty)
                      Polyline(
                        points: drawingState.mode == DrawingMode.area
                            ? (drawingState.points.length > 1
                                  ? [
                                      ...drawingState.points,
                                      drawingState.points.first,
                                    ]
                                  : drawingState.points)
                            : drawingState.points,
                        color: drawingState.mode == DrawingMode.area
                            ? Colors.blue
                            : Colors.teal,
                        strokeWidth: 4.0,
                        pattern: StrokePattern.dashed(segments: [10.0, 10.0]),
                      ),
                  ],
                ),
                if (drawingState.mode != DrawingMode.none &&
                    drawingState.points.isNotEmpty)
                  CircleLayer(
                    circles: drawingState.points
                        .map(
                          (p) => CircleMarker(
                            point: p,
                            radius: 6,
                            color: Colors.white,
                            borderColor: drawingState.mode == DrawingMode.area
                                ? Colors.blue
                                : Colors.teal,
                            borderStrokeWidth: 2,
                          ),
                        )
                        .toList(),
                  ),
                CircleLayer(
                  circles: markers
                      .where((m) => m.trustTier == 1 || m.trustTier == 2)
                      .map((m) {
                        final color = getHazardColor(m.type, m.trustTier);
                        return CircleMarker(
                          point: LatLng(m.latitude, m.longitude),
                          radius: m.trustTier == 1 ? 500 : 300,
                          useRadiusInMeter: true,
                          color: color.withValues(alpha: 0.2),
                          borderColor: color,
                          borderStrokeWidth: 2,
                        );
                      })
                      .toList(),
                ),
                MarkerLayer(
                  markers: [
                    ...paths.where((p) => p.coordinates.isNotEmpty).map((p) {
                      final points = p.coordinates
                          .map((c) => LatLng(c['lat']!, c['lng']!))
                          .toList();
                      final color = p.isCritical
                          ? Colors.red
                          : (p.type.toLowerCase().contains('safe') ||
                                    p.type.toLowerCase().contains('evacuation')
                                ? Colors.green
                                : Colors.orange);

                      final midPoint = points[points.length ~/ 2];

                      return Marker(
                        point: midPoint,
                        width: 120,
                        height: 30,
                        alignment: Alignment.center,
                        child: IgnorePointer(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.8),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: color, width: 1),
                            ),
                            child: Text(
                              p.type,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      );
                    }),
                    ...markers.map((m) {
                      final color = getHazardColor(m.type, m.trustTier);
                      return Marker(
                        point: LatLng(m.latitude, m.longitude),
                        width: m.isCritical ? 50 : 40,
                        height: m.isCritical ? 50 : 40,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            final canEndorse =
                                isAdmin &&
                                (m.trustTier == 3 || m.trustTier == 4);

                            showDialog(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                title: Row(
                                  children: [
                                    Icon(getHazardIcon(m.type), color: color),
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
                                    if (m.imageId != null &&
                                        m.imageId!.isNotEmpty)
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
                                              Text(
                                                'Reported by: ${profile.name}',
                                              ),
                                              if (profile
                                                  .contactInfo
                                                  .isNotEmpty)
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
                                  if (canEndorse)
                                    TextButton.icon(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
                                        _endorseHazard(m);
                                      },
                                      icon: const Icon(
                                        Icons.verified,
                                        size: 18,
                                      ),
                                      label: const Text('Verify & Endorse'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.purple,
                                      ),
                                    ),
                                  if (canEndorse)
                                    TextButton.icon(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
                                        _confirmDebunkReport(m.id, 'marker');
                                      },
                                      icon: const Icon(Icons.gavel, size: 18),
                                      label: const Text('Debunk'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                      ),
                                    ),
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
                                  if (m.trustTier == 4 ||
                                      (settings.isOfficialMode &&
                                          m.trustTier == 3))
                                    TextButton.icon(
                                      onPressed: () {
                                        Navigator.pop(dialogContext);
                                        if (settings.isOfficialMode) {
                                          _makeOfficialVolunteer(m.senderId);
                                        } else {
                                          _markAsTrusted(m.senderId);
                                        }
                                      },
                                      icon: Icon(
                                        settings.isOfficialMode
                                            ? Icons.admin_panel_settings
                                            : Icons.verified_user,
                                        size: 18,
                                      ),
                                      label: Text(
                                        settings.isOfficialMode
                                            ? 'Make Volunteer'
                                            : 'Trust',
                                      ),
                                      style: TextButton.styleFrom(
                                        foregroundColor: settings.isOfficialMode
                                            ? Colors.purple
                                            : Colors.green,
                                      ),
                                    ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.location_on,
                                color: color,
                                size: m.isCritical ? 50 : 40,
                              ),
                              Positioned(
                                top: m.isCritical ? 8 : 6,
                                child: Icon(
                                  getHazardIcon(m.type),
                                  color: Colors.white,
                                  size: m.isCritical ? 20 : 16,
                                ),
                              ),
                              if (m.isCritical)
                                const Positioned(
                                  right: -4,
                                  top: -4,
                                  child: Icon(
                                    Icons.warning,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final locationAsync = ref.watch(locationControllerProvider);
                    final currentPosition = locationAsync.value;
                    if (currentPosition == null) return const SizedBox.shrink();
                    return CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(
                            currentPosition.latitude,
                            currentPosition.longitude,
                          ),
                          radius: currentPosition.accuracy,
                          useRadiusInMeter: true,
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderColor: Colors.blue.withValues(alpha: 0.3),
                          borderStrokeWidth: 1,
                        ),
                      ],
                    );
                  },
                ),
                Consumer(
                  builder: (context, ref, child) {
                    final locationAsync = ref.watch(locationControllerProvider);
                    final currentPosition = locationAsync.value;
                    if (currentPosition == null) return const SizedBox.shrink();
                    return MarkerLayer(
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
                    );
                  },
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: IgnorePointer(
                ignoring: !ref.watch(
                  uiP2pServiceProvider.select((s) => s.isSyncing),
                ),
                child: AnimatedOpacity(
                  opacity:
                      ref.watch(uiP2pServiceProvider.select((s) => s.isSyncing))
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              value: ref.watch(
                                uiP2pServiceProvider.select(
                                  (s) => s.syncProgress,
                                ),
                              ),
                              strokeWidth: 2,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              ref.watch(
                                uiP2pServiceProvider.select((s) {
                                  final msg =
                                      s.syncMessage ?? 'Syncing data...';
                                  if (s.syncEstimatedSeconds != null) {
                                    return '$msg (~${s.syncEstimatedSeconds}s left)';
                                  }
                                  return msg;
                                }),
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onPrimaryContainer,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyFeedState(bool isLoading) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No reports found',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Try adjusting your filters, or sync with nearby devices to receive the latest updates.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const SyncBottomSheet(),
                );
              },
              icon: const Icon(Icons.sync),
              label: const Text('Open Sync Menu'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeed() {
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: const _SearchBar(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              const Text(
                'Live Reports',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  ref.read(navigationIndexProvider.notifier).setIndex(2);
                },
                icon: const Icon(Icons.help_outline, size: 14),
                label: const Text(
                  'Trust Model',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        Consumer(
          builder: (context, ref, child) {
            final filter = ref.watch(feedFilterControllerProvider);
            final filterNotifier = ref.read(
              feedFilterControllerProvider.notifier,
            );
            return _buildFilterBar(filter, filterNotifier);
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          child: ref.watch(uiP2pServiceProvider.select((s) => s.isSyncing))
              ? Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.primaryContainer,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          value: ref.watch(
                            uiP2pServiceProvider.select((s) => s.syncProgress),
                          ),
                          strokeWidth: 2,
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          ref.watch(
                            uiP2pServiceProvider.select((s) {
                              final msg = s.syncMessage ?? 'Syncing data...';
                              if (s.syncEstimatedSeconds != null) {
                                return '$msg (~${s.syncEstimatedSeconds}s left)';
                              }
                              return msg;
                            }),
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              ref.read(uiP2pServiceProvider.notifier).triggerSync();
              ref.read(cloudSyncServiceProvider.notifier).syncWithCloud();
              await Future.delayed(const Duration(seconds: 1));
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (ScrollNotification scrollInfo) {
                if (scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 200) {
                  ref.read(feedLimitProvider.notifier).loadMore();
                }
                return false;
              },
              child: Consumer(
                builder: (context, ref, child) {
                  final localUserAsync = ref.watch(localUserControllerProvider);
                  final myPublicKey = localUserAsync.value?.publicKey;
                  final combined = ref.watch(combinedFeedProvider);
                  final profiles =
                      ref.watch(userProfilesControllerProvider).value ?? [];
                  final settings = ref.watch(appSettingsProvider);

                  final isLoading =
                      ref.watch(filteredHazardMarkersProvider).isLoading ||
                      ref.watch(filteredNewsItemsProvider).isLoading ||
                      ref.watch(filteredAreasProvider).isLoading;

                  final adminTrustedAsync = ref.watch(
                    adminTrustedSendersControllerProvider,
                  );
                  final revokedAsync = ref.watch(
                    revokedDelegationsControllerProvider,
                  );
                  final adminTrusted = adminTrustedAsync.value ?? [];
                  final revoked = revokedAsync.value ?? [];
                  final revokedKeys = revoked
                      .map((e) => e.delegateePublicKey)
                      .toSet();
                  final isTier2 =
                      myPublicKey != null &&
                      adminTrusted.any(
                        (a) =>
                            a.publicKey == myPublicKey &&
                            !revokedKeys.contains(a.publicKey),
                      );
                  final isAdmin = settings.isOfficialMode || isTier2;

                  if (combined.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _buildEmptyFeedState(isLoading),
                        ),
                      ],
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8, bottom: 80),
                    itemCount:
                        combined.length +
                        (combined.length >= ref.watch(feedLimitProvider)
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (index == combined.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final item = combined[index];
                      final canEndorse =
                          isAdmin &&
                          (item.trustTier == 3 || item.trustTier == 4);

                      if (item is HazardMarkerEntity) {
                        final color = getHazardColor(item.type, item.trustTier);
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: color.withValues(alpha: 0.3),
                              width: item.trustTier == 1 ? 2 : 1,
                            ),
                          ),
                          child: InkWell(
                            onTap: () {
                              ref
                                  .read(navigationIndexProvider.notifier)
                                  .setIndex(0);
                              ref
                                  .read(mapTargetProvider.notifier)
                                  .setTarget(
                                    LatLng(item.latitude, item.longitude),
                                  );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: color.withValues(
                                          alpha: 0.2,
                                        ),
                                        child: Icon(
                                          getHazardIcon(item.type),
                                          color: color,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: item.isCritical
                                                    ? Colors.red
                                                    : null,
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
                                      if (canEndorse)
                                        FilledButton.tonalIcon(
                                          onPressed: () => _endorseHazard(item),
                                          icon: const Icon(
                                            Icons.verified,
                                            size: 16,
                                          ),
                                          label: const Text('Verify & Endorse'),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                Colors.purple.shade700,
                                            backgroundColor:
                                                Colors.purple.shade50,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                      if (canEndorse)
                                        FilledButton.tonalIcon(
                                          onPressed: () => _confirmDebunkReport(
                                            item.id,
                                            'marker',
                                          ),
                                          icon: const Icon(
                                            Icons.gavel,
                                            size: 16,
                                          ),
                                          label: const Text('Debunk'),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                Colors.red.shade700,
                                            backgroundColor: Colors.red.shade50,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _resolveMarker(item.id),
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
                                          icon: const Icon(
                                            Icons.block,
                                            size: 16,
                                          ),
                                          label: const Text('Block'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red,
                                          ),
                                        ),
                                      if (item.trustTier == 4 ||
                                          (settings.isOfficialMode &&
                                              item.trustTier == 3))
                                        FilledButton.tonalIcon(
                                          onPressed: () {
                                            if (settings.isOfficialMode) {
                                              _makeOfficialVolunteer(
                                                item.senderId,
                                              );
                                            } else {
                                              _markAsTrusted(item.senderId);
                                            }
                                          },
                                          icon: Icon(
                                            settings.isOfficialMode
                                                ? Icons.admin_panel_settings
                                                : Icons.verified_user,
                                            size: 16,
                                          ),
                                          label: Text(
                                            settings.isOfficialMode
                                                ? 'Make Volunteer'
                                                : 'Trust',
                                          ),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                settings.isOfficialMode
                                                ? Colors.purple.shade700
                                                : Colors.green.shade700,
                                            backgroundColor:
                                                settings.isOfficialMode
                                                ? Colors.purple.shade50
                                                : Colors.green.shade50,
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
                              color: getTierColor(
                                item.trustTier,
                              ).withValues(alpha: 0.3),
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
                                            '${item.title}${item.isCritical ? ' (CRITICAL)' : ''}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: item.isCritical
                                                  ? Colors.red
                                                  : null,
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
                                    if (canEndorse)
                                      FilledButton.tonalIcon(
                                        onPressed: () => _endorseNews(item),
                                        icon: const Icon(
                                          Icons.verified,
                                          size: 16,
                                        ),
                                        label: const Text('Verify & Endorse'),
                                        style: FilledButton.styleFrom(
                                          foregroundColor:
                                              Colors.purple.shade700,
                                          backgroundColor:
                                              Colors.purple.shade50,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    if (canEndorse)
                                      FilledButton.tonalIcon(
                                        onPressed: () => _confirmDebunkReport(
                                          item.id,
                                          'news',
                                        ),
                                        icon: const Icon(Icons.gavel, size: 16),
                                        label: const Text('Debunk'),
                                        style: FilledButton.styleFrom(
                                          foregroundColor: Colors.red.shade700,
                                          backgroundColor: Colors.red.shade50,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                        ),
                                      ),
                                    TextButton.icon(
                                      onPressed: () => _dismissNews(item.id),
                                      icon: const Icon(
                                        Icons.delete_forever,
                                        size: 16,
                                      ),
                                      label: const Text('Delete (Global)'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
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
                                    if (item.trustTier == 4 ||
                                        (settings.isOfficialMode &&
                                            item.trustTier == 3))
                                      FilledButton.tonalIcon(
                                        onPressed: () {
                                          if (settings.isOfficialMode) {
                                            _makeOfficialVolunteer(
                                              item.senderId,
                                            );
                                          } else {
                                            _markAsTrusted(item.senderId);
                                          }
                                        },
                                        icon: Icon(
                                          settings.isOfficialMode
                                              ? Icons.admin_panel_settings
                                              : Icons.verified_user,
                                          size: 16,
                                        ),
                                        label: Text(
                                          settings.isOfficialMode
                                              ? 'Make Volunteer'
                                              : 'Trust',
                                        ),
                                        style: FilledButton.styleFrom(
                                          foregroundColor:
                                              settings.isOfficialMode
                                              ? Colors.purple.shade700
                                              : Colors.green.shade700,
                                          backgroundColor:
                                              settings.isOfficialMode
                                              ? Colors.purple.shade50
                                              : Colors.green.shade50,
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
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              if (item.coordinates.isNotEmpty) {
                                ref
                                    .read(navigationIndexProvider.notifier)
                                    .setIndex(0);
                                ref
                                    .read(mapTargetProvider.notifier)
                                    .setTarget(
                                      LatLng(
                                        item.coordinates.first['lat']!,
                                        item.coordinates.first['lng']!,
                                      ),
                                    );
                              }
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
                                              '${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: item.isCritical
                                                    ? Colors.red
                                                    : null,
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
                                      if (canEndorse)
                                        FilledButton.tonalIcon(
                                          onPressed: () => _endorseArea(item),
                                          icon: const Icon(
                                            Icons.verified,
                                            size: 16,
                                          ),
                                          label: const Text('Verify & Endorse'),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                Colors.purple.shade700,
                                            backgroundColor:
                                                Colors.purple.shade50,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                      if (canEndorse)
                                        FilledButton.tonalIcon(
                                          onPressed: () => _confirmDebunkReport(
                                            item.id,
                                            'area',
                                          ),
                                          icon: const Icon(
                                            Icons.gavel,
                                            size: 16,
                                          ),
                                          label: const Text('Debunk'),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                Colors.red.shade700,
                                            backgroundColor: Colors.red.shade50,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
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
                                          icon: const Icon(
                                            Icons.block,
                                            size: 16,
                                          ),
                                          label: const Text('Block'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red,
                                          ),
                                        ),
                                      if (item.trustTier == 4 ||
                                          (settings.isOfficialMode &&
                                              item.trustTier == 3))
                                        FilledButton.tonalIcon(
                                          onPressed: () {
                                            if (settings.isOfficialMode) {
                                              _makeOfficialVolunteer(
                                                item.senderId,
                                              );
                                            } else {
                                              _markAsTrusted(item.senderId);
                                            }
                                          },
                                          icon: Icon(
                                            settings.isOfficialMode
                                                ? Icons.admin_panel_settings
                                                : Icons.verified_user,
                                            size: 16,
                                          ),
                                          label: Text(
                                            settings.isOfficialMode
                                                ? 'Make Volunteer'
                                                : 'Trust',
                                          ),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                settings.isOfficialMode
                                                ? Colors.purple.shade700
                                                : Colors.green.shade700,
                                            backgroundColor:
                                                settings.isOfficialMode
                                                ? Colors.purple.shade50
                                                : Colors.green.shade50,
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
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              if (item.coordinates.isNotEmpty) {
                                ref
                                    .read(navigationIndexProvider.notifier)
                                    .setIndex(0);
                                ref
                                    .read(mapTargetProvider.notifier)
                                    .setTarget(
                                      LatLng(
                                        item.coordinates.first['lat']!,
                                        item.coordinates.first['lng']!,
                                      ),
                                    );
                              }
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
                                              '${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: item.isCritical
                                                    ? Colors.red
                                                    : null,
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
                                      if (canEndorse)
                                        FilledButton.tonalIcon(
                                          onPressed: () => _endorsePath(item),
                                          icon: const Icon(
                                            Icons.verified,
                                            size: 16,
                                          ),
                                          label: const Text('Verify & Endorse'),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                Colors.purple.shade700,
                                            backgroundColor:
                                                Colors.purple.shade50,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
                                      if (canEndorse)
                                        FilledButton.tonalIcon(
                                          onPressed: () => _confirmDebunkReport(
                                            item.id,
                                            'path',
                                          ),
                                          icon: const Icon(
                                            Icons.gavel,
                                            size: 16,
                                          ),
                                          label: const Text('Debunk'),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                Colors.red.shade700,
                                            backgroundColor: Colors.red.shade50,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                          ),
                                        ),
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
                                          icon: const Icon(
                                            Icons.block,
                                            size: 16,
                                          ),
                                          label: const Text('Block'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: Colors.red,
                                          ),
                                        ),
                                      if (item.trustTier == 4 ||
                                          (settings.isOfficialMode &&
                                              item.trustTier == 3))
                                        FilledButton.tonalIcon(
                                          onPressed: () {
                                            if (settings.isOfficialMode) {
                                              _makeOfficialVolunteer(
                                                item.senderId,
                                              );
                                            } else {
                                              _markAsTrusted(item.senderId);
                                            }
                                          },
                                          icon: Icon(
                                            settings.isOfficialMode
                                                ? Icons.admin_panel_settings
                                                : Icons.verified_user,
                                            size: 16,
                                          ),
                                          label: Text(
                                            settings.isOfficialMode
                                                ? 'Make Volunteer'
                                                : 'Trust',
                                          ),
                                          style: FilledButton.styleFrom(
                                            foregroundColor:
                                                settings.isOfficialMode
                                                ? Colors.purple.shade700
                                                : Colors.green.shade700,
                                            backgroundColor:
                                                settings.isOfficialMode
                                                ? Colors.purple.shade50
                                                : Colors.green.shade50,
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
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(FeedFilter filter, dynamic filterNotifier) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                        showCheckmark: false,
                        selectedColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        side: BorderSide(
                          color: filter.typeFilter == type
                              ? Colors.transparent
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
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
                if (filter.typeFilter != 'All' || filter.trustFilter != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ActionChip(
                      label: const Text('Clear'),
                      avatar: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        filterNotifier.updateTypeFilter('All');
                        filterNotifier.updateTrustFilter(null);
                      },
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
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
                  showCheckmark: false,
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  side: BorderSide(
                    color: filter.trustFilter == null
                        ? Colors.transparent
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
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
                      showCheckmark: false,
                      selectedColor: getTierColor(tier).withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: filter.trustFilter == tier
                            ? getTierColor(tier)
                            : null,
                        fontWeight: filter.trustFilter == tier
                            ? FontWeight.bold
                            : null,
                      ),
                      side: BorderSide(
                        color: filter.trustFilter == tier
                            ? getTierColor(tier)
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
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
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trust Sender?'),
        content: const Text(
          'Are you sure you want to trust this sender? Their reports will be prioritized and marked as Trusted on your device only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              Navigator.pop(dialogContext);
              ref
                  .read(trustedSendersControllerProvider.notifier)
                  .addTrustedSender(senderId, 'Trusted User');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sender marked as trusted!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Trust'),
          ),
        ],
      ),
    );
  }

  void _makeOfficialVolunteer(String senderId) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Make Official Volunteer?'),
        content: const Text(
          'Are you sure you want to promote this user to an Official Volunteer? Their reports will be marked as Verified for everyone in the mesh network.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.purple),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await ref
                  .read(govApiServiceProvider.notifier)
                  .delegateAdminTrust(senderId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('User upgraded to Official Volunteer!'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Promote'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cryptoState = ref.watch(cryptoServiceProvider);
    final downloadProgress = ref.watch(mapDownloaderProvider);
    final settings = ref.watch(appSettingsProvider);
    final effectiveIndex = ref.watch(navigationIndexProvider);

    int displayIndex = effectiveIndex;
    if (!settings.isOfficialMode && displayIndex > 3) {
      displayIndex = 3;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      child: TutorialOverlay(
        onComplete: () => setState(() => _showTutorial = false),
        child: Scaffold(
          appBar: AppBar(
            title: downloadProgress.isDownloading
                ? Row(
                    children: [
                      const Text(
                        'FLOODIO',
                        style: TextStyle(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Downloading map: ${(downloadProgress.percentage * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'FLOODIO',
                    style: TextStyle(
                      letterSpacing: 2,
                      fontWeight: FontWeight.w900,
                    ),
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
              Consumer(
                builder: (context, ref, child) {
                  final p2pState = ref.watch(uiP2pServiceProvider);
                  final isConnected =
                      p2pState.hostState?.isActive == true ||
                      p2pState.clientState?.isActive == true;

                  if (!isConnected) return const SizedBox.shrink();

                  return IconButton(
                    icon: const Icon(Icons.sync),
                    tooltip: 'Manual Mesh Sync',
                    onPressed: p2pState.isSyncing
                        ? null
                        : () {
                            ref
                                .read(uiP2pServiceProvider.notifier)
                                .triggerSync();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Triggered manual mesh sync...'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                  );
                },
              ),
              Consumer(
                builder: (context, ref, child) {
                  final hasInternet = ref.watch(
                    cloudSyncServiceProvider.select((s) => s.hasInternet),
                  );
                  final isSyncing = ref.watch(
                    cloudSyncServiceProvider.select((s) => s.isSyncing),
                  );
                  final pendingUploads = ref.watch(
                    cloudSyncServiceProvider.select((s) => s.pendingUploads),
                  );

                  if (isSyncing) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.0),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                      ),
                    );
                  }

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          hasInternet ? Icons.cloud_done : Icons.cloud_off,
                          color: hasInternet ? Colors.white : Colors.white54,
                        ),
                        tooltip: hasInternet
                            ? 'Cloud Connected'
                            : 'Cloud Offline',
                        onPressed: () {
                          if (hasInternet) {
                            ref
                                .read(cloudSyncServiceProvider.notifier)
                                .syncWithCloud();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Syncing with cloud...'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No internet connection available.',
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      ),
                      if (pendingUploads > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Center(
                              child: Text(
                                pendingUploads > 99 ? '99+' : '$pendingUploads',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.device_hub),
                tooltip: 'Mesh Topology',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MeshTopologyScreen()),
                  );
                },
              ),
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
            index: displayIndex,
            children: [
              _buildMap(),
              _buildFeed(),
              const GuideTab(),
              ProfileTab(
                onEditAreaShape: (area) {
                  ref.read(navigationIndexProvider.notifier).setIndex(0);
                  ref
                      .read(drawingControllerProvider.notifier)
                      .startDrawingArea(
                        area.id,
                        area.coordinates
                            .map((c) => LatLng(c['lat']!, c['lng']!))
                            .toList(),
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Edit the area shape on the map.'),
                    ),
                  );
                },
                onEditPathShape: (path) {
                  ref.read(navigationIndexProvider.notifier).setIndex(0);
                  ref
                      .read(drawingControllerProvider.notifier)
                      .startDrawingPath(
                        path.id,
                        path.coordinates
                            .map((c) => LatLng(c['lat']!, c['lng']!))
                            .toList(),
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Edit the path shape on the map.'),
                    ),
                  );
                },
                onNavigateToMap: (point) {
                  ref.read(navigationIndexProvider.notifier).setIndex(0);
                  ref.read(mapTargetProvider.notifier).setTarget(point);
                },
              ),
              if (settings.isOfficialMode) const CommandTab(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: displayIndex,
            onDestinationSelected: (index) =>
                ref.read(navigationIndexProvider.notifier).setIndex(index),
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.map_outlined),
                selectedIcon: Icon(Icons.map),
                label: 'Map',
              ),
              const NavigationDestination(
                icon: Icon(Icons.view_list_outlined),
                selectedIcon: Icon(Icons.view_list),
                label: 'Feed',
              ),
              const NavigationDestination(
                icon: Icon(Icons.help_outline),
                selectedIcon: Icon(Icons.help),
                label: 'Guide',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
              if (settings.isOfficialMode)
                const NavigationDestination(
                  icon: Icon(Icons.admin_panel_settings_outlined),
                  selectedIcon: Icon(Icons.admin_panel_settings),
                  label: 'Command',
                ),
            ],
          ),
          floatingActionButton: (displayIndex >= 2)
              ? null
              : cryptoState.when(
                  data: (_) {
                    final drawingState = ref.watch(drawingControllerProvider);
                    if (drawingState.mode != DrawingMode.none) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FloatingActionButton.extended(
                            heroTag: 'cancel_draw',
                            onPressed: () {
                              ref
                                  .read(drawingControllerProvider.notifier)
                                  .cancel();
                            },
                            backgroundColor: Colors.red,
                            icon: const Icon(Icons.close, color: Colors.white),
                            label: const Text(
                              'Cancel',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (drawingState.points.isNotEmpty)
                            FloatingActionButton.extended(
                              heroTag: 'undo_draw',
                              onPressed: () {
                                ref
                                    .read(drawingControllerProvider.notifier)
                                    .removeLastPoint();
                              },
                              backgroundColor: Colors.orange,
                              icon: const Icon(Icons.undo, color: Colors.white),
                              label: const Text(
                                'Undo',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          const SizedBox(width: 16),
                          if ((drawingState.mode == DrawingMode.area &&
                                  drawingState.points.length >= 3) ||
                              (drawingState.mode == DrawingMode.path &&
                                  drawingState.points.length >= 2))
                            FloatingActionButton.extended(
                              heroTag: 'done_draw',
                              onPressed: () async {
                                if (drawingState.mode == DrawingMode.area) {
                                  AreaEntity? existingArea;
                                  if (drawingState.editingId != null) {
                                    final areas =
                                        ref
                                            .read(areasControllerProvider)
                                            .value ??
                                        [];
                                    try {
                                      existingArea = areas.firstWhere(
                                        (a) => a.id == drawingState.editingId,
                                      );
                                    } catch (_) {}
                                  }
                                  _showAddAreaDialog(
                                    existingArea: existingArea,
                                    points: drawingState.points,
                                  );
                                } else {
                                  PathEntity? existingPath;
                                  if (drawingState.editingId != null) {
                                    final paths =
                                        ref
                                            .read(pathsControllerProvider)
                                            .value ??
                                        [];
                                    try {
                                      existingPath = paths.firstWhere(
                                        (p) => p.id == drawingState.editingId,
                                      );
                                    } catch (_) {}
                                  }
                                  _showAddPathDialog(
                                    existingPath: existingPath,
                                    points: drawingState.points,
                                  );
                                }
                              },
                              backgroundColor: Colors.green,
                              icon: const Icon(
                                Icons.check,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Done',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                        ],
                      );
                    }

                    final locationState = ref.watch(locationControllerProvider);
                    final isLocationLoading =
                        locationState.isLoading && locationState.value == null;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (displayIndex == 0) ...[
                          if (_mapRotation != 0.0) ...[
                            FloatingActionButton.small(
                              heroTag: 'reset_rotation',
                              onPressed: () {
                                _mapController.rotate(0);
                              },
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surface,
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              child: const Icon(Icons.explore),
                            ),
                            const SizedBox(height: 16),
                          ],
                          FloatingActionButton.small(
                            heroTag: 'zoom_in',
                            onPressed: () {
                              try {
                                final currentZoom = _mapController.camera.zoom;
                                _mapController.move(
                                  _mapController.camera.center,
                                  currentZoom + 1,
                                );
                              } catch (e) {
                                debugPrint('Map not ready: $e');
                              }
                            },
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'zoom_out',
                            onPressed: () {
                              try {
                                final currentZoom = _mapController.camera.zoom;
                                _mapController.move(
                                  _mapController.camera.center,
                                  currentZoom - 1,
                                );
                              } catch (e) {
                                debugPrint('Map not ready: $e');
                              }
                            },
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            child: const Icon(Icons.remove),
                          ),
                          const SizedBox(height: 16),
                          FloatingActionButton.small(
                            heroTag: 'layers',
                            onPressed: () {
                              ref
                                  .read(showOfflineRegionsProvider.notifier)
                                  .toggle();
                              final show = ref.read(showOfflineRegionsProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    show
                                        ? 'Showing offline regions'
                                        : 'Hiding offline regions',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            child: const Icon(Icons.layers),
                          ),
                          const SizedBox(height: 16),
                          FloatingActionButton.small(
                            heroTag: 'center_map',
                            onPressed: () async {
                              setState(() {
                                _isTrackingLocation = true;
                              });
                              try {
                                final pos = await ref
                                    .read(locationControllerProvider.notifier)
                                    .getCurrentPosition();
                                if (pos != null) {
                                  final zoom = _mapController.camera.zoom < 10.0
                                      ? 15.0
                                      : _mapController.camera.zoom;
                                  _mapController.move(
                                    LatLng(pos.latitude, pos.longitude),
                                    zoom,
                                  );
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(
                                      this.context,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Location not available. Please check permissions.',
                                        ),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                debugPrint('Map not ready yet: $e');
                              }
                            },
                            backgroundColor: _isTrackingLocation
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.surface,
                            foregroundColor: _isTrackingLocation
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.primary,
                            child: isLocationLoading
                                ? Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _isTrackingLocation
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.onPrimary
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                    ),
                                  )
                                : const Icon(Icons.my_location),
                          ),
                          const SizedBox(height: 16),
                        ],
                        FloatingActionButton.extended(
                          heroTag: 'create_report',
                          onPressed: _showReportOptions,
                          icon: const Icon(Icons.add),
                          label: const Text('Create Report'),
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
      ),
    );
  }
}
