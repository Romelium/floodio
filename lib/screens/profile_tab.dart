import 'dart:convert';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:floodio/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../crypto/crypto_service.dart';
import '../database/tables.dart';
import '../providers/area_provider.dart';
import '../providers/hazard_marker_provider.dart';
import '../providers/local_user_provider.dart';
import '../providers/news_item_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../providers/path_provider.dart';
import '../providers/trusted_sender_provider.dart';
import '../providers/untrusted_sender_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/map_cache_service.dart';
import '../providers/ui_p2p_provider.dart';
import '../protos/models.pb.dart' as pb;
import 'settings_screen.dart';
import 'compass_screen.dart';
import '../providers/hero_stats_provider.dart';

class ProfileTab extends ConsumerStatefulWidget {
  final Function(AreaEntity) onEditAreaShape;
  final Function(PathEntity) onEditPathShape;
  final Function(LatLng) onNavigateToMap;
  const ProfileTab({
    super.key,
    required this.onEditAreaShape,
    required this.onEditPathShape,
    required this.onNavigateToMap,
  });

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  @override
  void initState() {
    super.initState();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(2)} ${suffixes[i]}';
  }

  void _showMuleHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Data Mule Stats'),
        content: const Text(
          'A "Data Mule" is someone who physically carries data between disconnected areas.\n\n'
          '• Data Carried: Total amount of data you have received and forwarded.\n'
          '• Peers Synced: Number of unique device connections you have made.\n'
          '• Reports Relayed: Number of individual hazard, news, area, and path reports you have successfully passed on to others.\n\n'
          'By keeping Auto-Sync on while moving, you are actively helping your community stay informed!',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Awesome'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStatItem(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  void _removeTrustedSender(String publicKey) {
    HapticFeedback.heavyImpact();
    ref
        .read(trustedSendersControllerProvider.notifier)
        .removeTrustedSender(publicKey);
  }

  void _deleteMarker(String id) {
    HapticFeedback.selectionClick();
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
              HapticFeedback.heavyImpact();
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
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteNews(String id) {
    HapticFeedback.selectionClick();
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
              HapticFeedback.heavyImpact();
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
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deleteArea(String id) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Area?'),
        content: const Text(
          'Are you sure you want to delete this area report?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              HapticFeedback.heavyImpact();
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
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _deletePath(String id) {
    HapticFeedback.selectionClick();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Path?'),
        content: const Text(
          'Are you sure you want to delete this path report?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              HapticFeedback.heavyImpact();
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
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _editProfile() {
    HapticFeedback.selectionClick();
    final localUser = ref.read(localUserControllerProvider).value;
    final nameController = TextEditingController(text: localUser?.name ?? '');
    final contactController = TextEditingController(
      text: localUser?.contact ?? '',
    );

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
              HapticFeedback.mediumImpact();
              final newName = nameController.text.trim();
              final newContact = contactController.text.trim();
              if (newName.isEmpty) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name cannot be empty'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
                return;
              }

              Navigator.pop(dialogContext);

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

              await ref
                  .read(localUserControllerProvider.notifier)
                  .updateProfile(newName, newContact);

              final payload = pb.SyncPayload();
              payload.profiles.add(
                pb.UserProfile(
                  publicKey: profile.publicKey,
                  name: profile.name,
                  contactInfo: profile.contactInfo,
                  timestamp: Int64(profile.timestamp),
                  signature: profile.signature,
                ),
              );
              final encoded = base64Encode(payload.writeToBuffer());
              ref
                  .read(uiP2pServiceProvider.notifier)
                  .broadcastText(
                    jsonEncode({'type': 'payload', 'data': encoded}),
                  );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Profile updated'),
                    behavior: SnackBarBehavior.floating,
                  ),
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
    HapticFeedback.selectionClick();
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
                HapticFeedback.mediumImpact();
                Navigator.pop(dialogContext);
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
                    .broadcastText(
                      jsonEncode({'type': 'payload', 'data': encoded}),
                    );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hazard updated'),
                      behavior: SnackBarBehavior.floating,
                    ),
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
    HapticFeedback.selectionClick();
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
                HapticFeedback.mediumImpact();
                Navigator.pop(dialogContext);
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
                    .broadcastText(
                      jsonEncode({'type': 'payload', 'data': encoded}),
                    );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('News updated'),
                      behavior: SnackBarBehavior.floating,
                    ),
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

  void _editArea(AreaEntity area) {
    HapticFeedback.selectionClick();
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
                HapticFeedback.mediumImpact();
                Navigator.pop(dialogContext);
                final cryptoService = ref.read(cryptoServiceProvider.notifier);
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final newId = area.id; // Keep same ID for LWW CRDT
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;

                final isCriticalStr = isCritical ? "1" : "0";
                final coordsStr = area.coordinates
                    .map((c) => '${c['lat']},${c['lng']}')
                    .join('|');
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

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Area updated'),
                      behavior: SnackBarBehavior.floating,
                    ),
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

  void _editPath(PathEntity path) {
    HapticFeedback.selectionClick();
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
                      ['Evacuation Route', 'Safe Path', 'Blocked Road', 'Other']
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
                HapticFeedback.mediumImpact();
                Navigator.pop(dialogContext);
                final cryptoService = ref.read(cryptoServiceProvider.notifier);
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final newId = path.id; // Keep same ID for LWW CRDT
                final expiresAt = selectedTtlHours != null
                    ? timestamp + (selectedTtlHours! * 3600000)
                    : null;

                final isCriticalStr = isCritical ? "1" : "0";
                final coordsStr = path.coordinates
                    .map((c) => '${c['lat']},${c['lng']}')
                    .join('|');
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

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Path updated'),
                      behavior: SnackBarBehavior.floating,
                    ),
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

  @override
  Widget build(BuildContext context) {
    final localUserAsync = ref.watch(localUserControllerProvider);
    final localUser = localUserAsync.value;
    final myName = localUser?.name ?? 'Unknown';
    final myContact = localUser?.contact ?? '';
    final myPublicKey = localUser?.publicKey;

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
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primaryContainer,
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onPrimary,
                          child: Text(
                            myName.isNotEmpty ? myName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          myName,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        if (myContact.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.phone,
                                size: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                myContact,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            HapticFeedback.selectionClick();
                            if (myPublicKey != null) {
                              Clipboard.setData(
                                ClipboardData(text: myPublicKey),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Public Key copied to clipboard',
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.key,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  myPublicKey != null
                                      ? '${myPublicKey.substring(0, 16)}...'
                                      : 'Loading key...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.copy,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                _editProfile();
                              },
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit Profile'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.settings, size: 18),
                              label: const Text('Settings'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Hero Stats Card
                Consumer(
                  builder: (context, ref, child) {
                    final heroStatsAsync = ref.watch(
                      heroStatsControllerProvider,
                    );
                    final stats = heroStatsAsync.value;
                    if (stats == null) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.military_tech,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Data Mule Stats',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(
                                Icons.help_outline,
                                size: 20,
                                color: Colors.amber,
                              ),
                              onPressed: () => _showMuleHelp(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: Colors.amber.shade300,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          color: Colors.amber.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade100,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.star,
                                        color: Colors.amber.shade800,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Status: ${stats.status}',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 18,
                                              color: Colors.amber.shade900,
                                            ),
                                          ),
                                          Text(
                                            'You are actively helping your community stay connected.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.amber.shade800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildHeroStatItem(
                                      context,
                                      icon: Icons.data_usage,
                                      value: _formatBytes(
                                        stats.dataCarriedBytes,
                                      ),
                                      label: 'Data Carried',
                                      color: Colors.blue.shade700,
                                    ),
                                    _buildHeroStatItem(
                                      context,
                                      icon: Icons.people_alt,
                                      value: '${stats.peersSyncedWith}',
                                      label: 'Peers Synced',
                                      color: Colors.green.shade700,
                                    ),
                                    _buildHeroStatItem(
                                      context,
                                      icon: Icons.forward_to_inbox,
                                      value: '${stats.reportsRelayed}',
                                      label: 'Reports Relayed',
                                      color: Colors.purple.shade700,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    );
                  },
                ),

                // Trusted Senders
                Consumer(
                  builder: (context, ref, child) {
                    final trustedSendersAsync = ref.watch(
                      trustedSendersControllerProvider,
                    );
                    final trustedSenders = trustedSendersAsync.value ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.verified_user,
                              color: Colors.green,
                            ),
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
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  color: Colors.green.shade300,
                                  size: 32,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'You have not trusted any senders yet. Trust senders from the feed to prioritize their reports.',
                                    style: TextStyle(
                                      color: Colors.green.shade800,
                                    ),
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
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
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text(
                                            'Remove Trusted Sender?',
                                          ),
                                          content: Text(
                                            'Are you sure you want to remove ${sender.name} from your trusted senders? Their future reports will be marked as Crowdsourced.',
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
                                              onPressed: () {
                                                Navigator.pop(dialogContext);
                                                _removeTrustedSender(
                                                  sender.publicKey,
                                                );
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
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Blocked Senders
                Consumer(
                  builder: (context, ref, child) {
                    final untrustedSendersAsync = ref.watch(
                      untrustedSendersControllerProvider,
                    );
                    final untrustedSenders = untrustedSendersAsync.value ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.block_outlined,
                                  color: Colors.red.shade300,
                                  size: 32,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'You have not blocked any senders.',
                                    style: TextStyle(
                                      color: Colors.red.shade800,
                                    ),
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
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.restore,
                                      color: Colors.blue,
                                    ),
                                    tooltip: 'Unblock',
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      showDialog(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('Unblock Sender?'),
                                          content: const Text(
                                            'Are you sure you want to unblock this sender?',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dialogContext),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () {
                                                HapticFeedback.mediumImpact();
                                                Navigator.pop(dialogContext);
                                                ref
                                                    .read(
                                                      untrustedSendersControllerProvider
                                                          .notifier,
                                                    )
                                                    .removeUntrustedSender(
                                                      sender.publicKey,
                                                    );
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Sender unblocked.',
                                                    ),
                                                    behavior: SnackBarBehavior
                                                        .floating,
                                                  ),
                                                );
                                              },
                                              child: const Text('Unblock'),
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
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Map Storage
                Consumer(
                  builder: (context, ref, child) {
                    final mapCacheSizeAsync = ref.watch(
                      mapCacheSizeControllerProvider,
                    );
                    final mapCacheSize = mapCacheSizeAsync.value ?? 0;
                    final offlineRegionsAsync = ref.watch(
                      offlineRegionsProvider,
                    );
                    final offlineRegions = offlineRegionsAsync.value ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                                  child: Icon(
                                    Icons.storage,
                                    color: Colors.white,
                                  ),
                                ),
                                title: const Text('Storage Used'),
                                subtitle: Text(_formatBytes(mapCacheSize)),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Clear All Offline Maps',
                                  onPressed: () {
                                    HapticFeedback.selectionClick();
                                    showDialog(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text(
                                          'Clear All Offline Maps?',
                                        ),
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
                                              HapticFeedback.heavyImpact();
                                              Navigator.pop(dialogContext);
                                              await ref
                                                  .read(mapCacheServiceProvider)
                                                  .clearCache();
                                              await ref
                                                  .read(
                                                    offlineRegionsProvider
                                                        .notifier,
                                                  )
                                                  .clearRegions();
                                              ref
                                                  .read(
                                                    mapCacheSizeControllerProvider
                                                        .notifier,
                                                  )
                                                  .refresh();
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Offline maps cleared',
                                                  ),
                                                  behavior:
                                                      SnackBarBehavior.floating,
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
                                          HapticFeedback.selectionClick();
                                          showDialog(
                                            context: context,
                                            builder: (dialogContext) => AlertDialog(
                                              title: const Text(
                                                'Delete Region?',
                                              ),
                                              content: const Text(
                                                'This will delete the map tiles for this region. Overlapping regions may lose some tiles.',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        dialogContext,
                                                      ),
                                                  child: const Text('Cancel'),
                                                ),
                                                FilledButton(
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                  ),
                                                  onPressed: () async {
                                                    HapticFeedback.heavyImpact();
                                                    Navigator.pop(
                                                      dialogContext,
                                                    );
                                                    await ref
                                                        .read(
                                                          offlineRegionsProvider
                                                              .notifier,
                                                        )
                                                        .removeRegion(region);
                                                    await ref
                                                        .read(
                                                          mapCacheServiceProvider,
                                                        )
                                                        .deleteRegionTiles(
                                                          region,
                                                        );
                                                    ref
                                                        .read(
                                                          mapCacheSizeControllerProvider
                                                              .notifier,
                                                        )
                                                        .refresh();
                                                    if (!context.mounted)
                                                      return;
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          'Region deleted',
                                                        ),
                                                        behavior:
                                                            SnackBarBehavior
                                                                .floating,
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
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),

                // My Reports
                Consumer(
                  builder: (context, ref, child) {
                    final markersAsync = ref.watch(
                      hazardMarkersControllerProvider,
                    );
                    final newsAsync = ref.watch(newsItemsControllerProvider);
                    final areasAsync = ref.watch(areasControllerProvider);
                    final pathsAsync = ref.watch(pathsControllerProvider);
                    final localUserAsync = ref.watch(
                      localUserControllerProvider,
                    );
                    final myPublicKey = localUserAsync.value?.publicKey;

                    final myMarkers = (markersAsync.value ?? [])
                        .where((m) => m.senderId == myPublicKey)
                        .toList();
                    final myNews = (newsAsync.value ?? [])
                        .where((n) => n.senderId == myPublicKey)
                        .toList();
                    final myAreas = (areasAsync.value ?? [])
                        .where((a) => a.senderId == myPublicKey)
                        .toList();
                    final myPaths = (pathsAsync.value ?? [])
                        .where((p) => p.senderId == myPublicKey)
                        .toList();

                    final myReports = <dynamic>[
                      ...myMarkers,
                      ...myNews,
                      ...myAreas,
                      ...myPaths,
                    ];
                    myReports.sort(
                      (a, b) =>
                          (b.timestamp as int).compareTo(a.timestamp as int),
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.my_library_books,
                              color: Colors.blue,
                            ),
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
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.my_library_books_outlined,
                                  color: Colors.blue.shade300,
                                  size: 32,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'You have not made any reports yet.',
                                    style: TextStyle(
                                      color: Colors.blue.shade800,
                                    ),
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
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      widget.onNavigateToMap(
                                        LatLng(item.latitude, item.longitude),
                                      );
                                    },
                                    leading: CircleAvatar(
                                      backgroundColor: Colors.orange.shade100,
                                      child: const Icon(
                                        Icons.warning,
                                        color: Colors.orange,
                                      ),
                                    ),
                                    title: Text(
                                      '${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: item.isCritical
                                            ? Colors.red
                                            : null,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            Icons.explore,
                                            color: Colors.teal,
                                          ),
                                          tooltip: 'Compass',
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => CompassScreen(
                                                  target: LatLng(
                                                    item.latitude,
                                                    item.longitude,
                                                  ),
                                                  title: item.type,
                                                ),
                                              ),
                                            );
                                          },
                                        ),
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
                                          onPressed: () =>
                                              _deleteMarker(item.id),
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
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
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
                                      '${item.title}${item.isCritical ? ' (CRITICAL)' : ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: item.isCritical
                                            ? Colors.red
                                            : null,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: ListTile(
                                    onTap: () {
                                      if (item.coordinates.isNotEmpty) {
                                        widget.onNavigateToMap(
                                          LatLng(
                                            item.coordinates.first['lat']!,
                                            item.coordinates.first['lng']!,
                                          ),
                                        );
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
                                      '${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: item.isCritical
                                            ? Colors.red
                                            : null,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            Icons.explore,
                                            color: Colors.teal,
                                          ),
                                          tooltip: 'Compass',
                                          onPressed: () {
                                            if (item.coordinates.isNotEmpty) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => CompassScreen(
                                                    target: LatLng(
                                                      item
                                                          .coordinates
                                                          .first['lat']!,
                                                      item
                                                          .coordinates
                                                          .first['lng']!,
                                                    ),
                                                    title: item.type,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
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
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
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
                                      '${item.type}${item.isCritical ? ' (CRITICAL)' : ''}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: item.isCritical
                                            ? Colors.red
                                            : null,
                                      ),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                            Icons.explore,
                                            color: Colors.teal,
                                          ),
                                          tooltip: 'Compass',
                                          onPressed: () {
                                            if (item.coordinates.isNotEmpty) {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => CompassScreen(
                                                    target: LatLng(
                                                      item
                                                          .coordinates
                                                          .first['lat']!,
                                                      item
                                                          .coordinates
                                                          .first['lng']!,
                                                    ),
                                                    title: item.type,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
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
                    );
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
