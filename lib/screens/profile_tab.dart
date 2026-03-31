import 'dart:convert';
import 'dart:math';

import 'package:floodio/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import '../database/tables.dart';
import '../providers/area_provider.dart';
import '../providers/hazard_marker_provider.dart';
import '../providers/news_item_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../providers/path_provider.dart';
import '../providers/trusted_sender_provider.dart';
import '../providers/untrusted_sender_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/map_cache_service.dart';
import 'settings_screen.dart';

class ProfileTab extends ConsumerStatefulWidget {
  final Function(AreaEntity) onEditAreaShape;
  final Function(PathEntity) onEditPathShape;
  final Function(LatLng) onNavigateToMap;
  const ProfileTab({super.key, required this.onEditAreaShape, required this.onEditPathShape, required this.onNavigateToMap});

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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Report?'),
        content: const Text(
          'Are you sure you want to delete this hazard report?',
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete News?'),
        content: const Text('Are you sure you want to delete this news item?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(dialogContext);
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

  void _deletePath(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Path?'),
        content: const Text(
          'Are you sure you want to delete this path report?',
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
              ref.read(pathsControllerProvider.notifier).deletePath(id);
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
    final isOfficial = ref.read(appSettingsProvider).isOfficialMode;
    List<String> types = ['Flood', 'Fire', 'Roadblock', 'Medical', 'Other'];
    if (isOfficial) {
      types.addAll(['Supply', 'Medical Triage', 'Custom']);
    }
    if (!types.contains(marker.type)) {
      types.add(marker.type);
    }

    String selectedType = marker.type;
    final descController = TextEditingController(text: marker.description);
    int? selectedTtlHours = 24; // Default to extending by 24h
    bool isCritical = marker.isCritical;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
          title: const Text('Edit Hazard'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: 'Hazard Type'),
                  items: types
                      .map(
                        (type) =>
                            DropdownMenuItem(value: type, child: Text(type)),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setInnerState(() => selectedType = val);
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
                  onChanged: (val) => setInnerState(() => selectedTtlHours = val),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Mark as Critical Emergency', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  value: isCritical,
                  onChanged: (val) => setInnerState(() => isCritical = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.red,
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

                final isCriticalStr = isCritical ? "1" : "0";
                final payloadToSign = utf8.encode(
                  '$newId${marker.latitude}${marker.longitude}$selectedType${descController.text}$timestamp${marker.imageId ?? ""}${expiresAt ?? ""}$isCriticalStr',
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
                  isCritical: isCritical,
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
    bool isCritical = news.isCritical;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
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
                  onChanged: (val) => setInnerState(() => selectedTtlHours = val),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Mark as Critical Emergency', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  value: isCritical,
                  onChanged: (val) => setInnerState(() => isCritical = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.red,
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

                final isCriticalStr = isCritical ? "1" : "0";
                final payloadToSign = utf8.encode(
                  '$newId${titleController.text}${contentController.text}$timestamp${news.imageId ?? ""}${expiresAt ?? ""}$isCriticalStr',
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
                  isCritical: isCritical,
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
    bool isCritical = area.isCritical;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
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
                    if (val != null) setInnerState(() => selectedType = val);
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
                  onChanged: (val) => setInnerState(() => selectedTtlHours = val),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Mark as Critical Emergency', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  value: isCritical,
                  onChanged: (val) => setInnerState(() => isCritical = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.red,
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

                final isCriticalStr = isCritical ? "1" : "0";
                final coordsStr = area.coordinates.map((c) => '${c['lat']},${c['lng']}').join('|');
                final payloadToSign = utf8.encode(
                  '$newId$coordsStr$selectedType${descController.text}$timestamp${expiresAt ?? ""}$isCriticalStr',
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
                  isCritical: isCritical,
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

  void _editPath(PathEntity path) {
    String selectedType = path.type;
    final descController = TextEditingController(text: path.description);
    int? selectedTtlHours = 24;
    bool isCritical = path.isCritical;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (innerContext, setInnerState) => AlertDialog(
          title: const Text('Edit Path'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue:
                      [
                        'Evacuation Route',
                        'Safe Path',
                        'Blocked Road',
                        'Other',
                      ].contains(selectedType)
                      ? selectedType
                      : 'Other',
                  decoration: const InputDecoration(labelText: 'Path Type'),
                  items:
                      [
                            'Evacuation Route',
                            'Safe Path',
                            'Blocked Road',
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
                    if (val != null) setInnerState(() => selectedType = val);
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
                  onChanged: (val) => setInnerState(() => selectedTtlHours = val),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Mark as Critical Emergency', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  value: isCritical,
                  onChanged: (val) => setInnerState(() => isCritical = val ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: Colors.red,
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
                final newId = path.id; // Keep same ID for LWW CRDT
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;

                final isCriticalStr = isCritical ? "1" : "0";
                final coordsStr = path.coordinates.map((c) => '${c['lat']},${c['lng']}').join('|');
                final payloadToSign = utf8.encode(
                  '$newId$coordsStr$selectedType${descController.text}$timestamp${expiresAt ?? ""}$isCriticalStr',
                );
                final signature = await cryptoService.signData(payloadToSign);

                final updatedPath = PathEntity(
                  id: newId,
                  coordinates: path.coordinates,
                  type: selectedType,
                  description: descController.text,
                  timestamp: timestamp,
                  senderId: path.senderId,
                  signature: signature,
                  trustTier: path.trustTier,
                  expiresAt: expiresAt,
                  isCritical: isCritical,
                );

                await ref
                    .read(pathsControllerProvider.notifier)
                    .addPath(updatedPath);
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Path updated')));
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
    final pathsAsync = ref.watch(pathsControllerProvider);
    final myPaths = (pathsAsync.value ?? [])
        .where((p) => p.senderId == _myPublicKey)
        .toList();

    final myReports = <dynamic>[...myMarkers, ...myNews, ...myAreas, ...myPaths];
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
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                            onTap: () {
                              widget.onNavigateToMap(LatLng(item.latitude, item.longitude));
                            },
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: const Icon(
                                Icons.warning,
                                color: Colors.orange,
                              ),
                            ),
                            title: Text(
                              'Hazard: ${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: item.isCritical ? Colors.red : null,
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
                            onTap: () {
                              // News items don't have coordinates
                            },
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: const Icon(
                                Icons.campaign,
                                color: Colors.blue,
                              ),
                            ),
                            title: Text(
                              'News: ${item.title}${item.isCritical ? ' (CRITICAL)' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: item.isCritical ? Colors.red : null,
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
                            onTap: () {
                              if (item.coordinates.isNotEmpty) {
                                widget.onNavigateToMap(LatLng(
                                  item.coordinates.first['lat']!,
                                  item.coordinates.first['lng']!,
                                ));
                              }
                            },
                            leading: CircleAvatar(
                              backgroundColor: Colors.purple.shade100,
                              child: const Icon(
                                Icons.format_shapes,
                                color: Colors.purple,
                              ),
                            ),
                            title: Text(
                              'Area: ${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: item.isCritical ? Colors.red : null,
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
                      } else if (item is PathEntity) {
                        return Card(
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.teal.shade100,
                              child: const Icon(
                                Icons.route,
                                color: Colors.teal,
                              ),
                            ),
                            title: Text(
                              'Path: ${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: item.isCritical ? Colors.red : null,
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
                                    color: Colors.teal,
                                  ),
                                  tooltip: 'Edit Shape',
                                  onPressed: () =>
                                      widget.onEditPathShape(item),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _editPath(item),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _deletePath(item.id),
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
