import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/ui_state_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../providers/ui_p2p_provider.dart';
import '../services/cloud_sync_service.dart';
import '../utils/ui_helpers.dart';
import '../utils/permission_utils.dart';

class SyncBottomSheet extends ConsumerWidget {
  const SyncBottomSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p2pState = ref.watch(uiP2pServiceProvider);
    final p2pNotifier = ref.read(uiP2pServiceProvider.notifier);
    final myRegionsAsync = ref.watch(offlineRegionsProvider);
    final myRegions = myRegionsAsync.value ?? [];

    final isConnected = p2pState.hostState?.isActive == true || p2pState.clientState?.isActive == true;
    final isBusy = p2pState.isSyncing || p2pState.isConnecting || p2pState.isScanning;

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
            top: 12.0,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sync & Connect',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Auto-Sync (Primary)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: p2pState.isAutoSyncing
                          ? [Colors.blue.shade700, Colors.blue.shade900]
                          : [Colors.grey.shade100, Colors.grey.shade200],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: p2pState.isAutoSyncing ? [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ] : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () async {
                        if (!p2pState.isAutoSyncing) {
                          final enabled = await ensureServicesEnabled();
                          if (enabled) p2pNotifier.toggleAutoSync();
                        } else {
                          p2pNotifier.toggleAutoSync();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: p2pState.isAutoSyncing ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.autorenew,
                                color: p2pState.isAutoSyncing ? Colors.white : Colors.grey.shade700,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Mesh Auto-Sync',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: p2pState.isAutoSyncing ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    p2pState.isAutoSyncing ? 'Actively searching for peers...' : 'Tap to enable background sync',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: p2pState.isAutoSyncing ? Colors.blue.shade100 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: p2pState.isAutoSyncing,
                              onChanged: (val) async {
                                if (val) {
                                  final enabled = await ensureServicesEnabled();
                                  if (enabled) p2pNotifier.toggleAutoSync();
                                } else {
                                  p2pNotifier.toggleAutoSync();
                                }
                              },
                              activeThumbColor: Colors.white,
                              activeTrackColor: Colors.blue.shade400,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Network Status
                Card(
                  color: isConnected 
                      ? Colors.green.shade50 
                      : (p2pState.isAutoSyncing ? Colors.orange.shade50 : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isConnected 
                          ? Colors.green.shade200 
                          : (p2pState.isAutoSyncing ? Colors.orange.shade200 : Colors.transparent),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isBusy)
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  value: p2pState.syncProgress,
                                  strokeWidth: 3
                                ),
                              )
                            else
                              Icon(
                                isConnected ? Icons.check_circle : (p2pState.isAutoSyncing ? Icons.radar : Icons.cloud_off),
                                color: isConnected ? Colors.green : (p2pState.isAutoSyncing ? Colors.orange : Colors.grey),
                                size: 24,
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                isConnected ? 'Connected to Mesh' : (p2pState.isAutoSyncing ? 'Searching for Peers...' : 'Mesh Offline'),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isConnected ? Colors.green.shade800 : (p2pState.isAutoSyncing ? Colors.orange.shade800 : Colors.grey.shade700),
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (isBusy && p2pState.syncProgress != null) ...[
                          LinearProgressIndicator(
                            value: p2pState.syncProgress,
                            borderRadius: BorderRadius.circular(4),
                            minHeight: 6,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p2pState.syncMessage != null 
                                      ? '${p2pState.syncMessage}${p2pState.syncEstimatedSeconds != null ? ' (~${p2pState.syncEstimatedSeconds}s left)' : ''}'
                                      : 'Ready to sync. Enable Auto-Sync or use manual controls.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.access_time, size: 16, color: Colors.grey.shade700),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  p2pState.lastSyncTime != null 
                                      ? 'Last synced: ${formatTimestamp(p2pState.lastSyncTime!.millisecondsSinceEpoch)}' 
                                      : 'Never synced',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              ref.read(navigationIndexProvider.notifier).setIndex(2);
                            },
                            child: const Text('How does mesh sync work?'),
                          ),
                        ),
                        if (isConnected) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildStatusItem(
                                context, 
                                icon: p2pState.hostState?.isActive == true ? Icons.router : Icons.smartphone, 
                                label: 'Role', 
                                value: p2pState.hostState?.isActive == true ? 'Host' : 'Client'
                              ),
                              _buildStatusItem(
                                context, 
                                icon: Icons.people, 
                                label: 'Peers', 
                                value: p2pState.hostState?.isActive == true ? '${p2pState.connectedClients.length}' : '1 (Host)'
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: p2pState.isSyncing ? null : () {
                                p2pNotifier.triggerSync();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Triggered manual mesh sync...'), behavior: SnackBarBehavior.floating),
                                );
                              },
                              icon: const Icon(Icons.sync),
                              label: Text(p2pState.isSyncing ? 'Syncing...' : 'Force 2-Way Sync Now'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 3. Cloud Sync Section
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
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cloudSyncState.hasInternet ? Colors.blue.shade50 : Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            cloudSyncState.hasInternet ? Icons.cloud_sync : Icons.cloud_off,
                            color: cloudSyncState.hasInternet ? Colors.blue : Colors.red,
                          ),
                        ),
                        title: const Text(
                          'Cloud Gateway',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Last synced: $lastSyncText\n${cloudSyncState.hasInternet ? 'Internet connected.' : 'No internet connection.'}\nPending uploads: ${cloudSyncState.pendingUploads}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: cloudSyncState.isSyncing
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : FilledButton.tonal(
                                onPressed: cloudSyncState.hasInternet ? () async {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Syncing with cloud...'), behavior: SnackBarBehavior.floating),
                                  );
                                  final success = await cloudSyncNotifier.syncWithCloud();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(success ? 'Cloud sync complete.' : 'Cloud sync failed.'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } : null,
                                child: const Text('Cloud Sync'),
                              ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // 4. Peer Offline Maps Section
                if (p2pState.peerOfflineRegions.isNotEmpty) ...[
                  Text(
                    'Available Peer Maps',
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
                            style: const TextStyle(fontSize: 11),
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
                                              behavior: SnackBarBehavior.floating,
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

                // 5. Advanced / Manual Controls
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Advanced Manual Controls',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    children: [
                      if (p2pState.isAutoSyncing)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Manual controls are disabled while Auto-Sync is active.',
                                  style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // Host Section
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('Create Mesh Node (Host)', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('Create a local network. Data syncs both ways.', style: TextStyle(fontSize: 12)),
                              value: p2pState.isHosting,
                              onChanged: (p2pState.isScanning || p2pState.isAutoSyncing)
                                  ? null
                                  : (val) async {
                                      if (val) {
                                        final enabled = await ensureServicesEnabled();
                                        if (enabled) p2pNotifier.startHosting();
                                      } else {
                                        p2pNotifier.stopHosting();
                                      }
                                    },
                            ),
                            if (p2pState.hostState?.isActive == true && p2pState.connectedClients.isNotEmpty) ...[
                              const Divider(height: 1),
                              ...p2pState.connectedClients.map(
                                (client) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.smartphone, size: 18),
                                  title: Text(client.username.isEmpty ? 'Unknown Client' : client.username),
                                  subtitle: Text(client.id, style: const TextStyle(fontSize: 10)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Client Section
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              title: const Text('Join Mesh Node (Scan)', style: TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: const Text('Look for nearby networks. Data syncs both ways.', style: TextStyle(fontSize: 12)),
                              value: p2pState.isScanning || p2pState.clientState?.isActive == true,
                              onChanged: (p2pState.isHosting || p2pState.isAutoSyncing)
                                  ? null
                                  : (val) async {
                                      if (val) {
                                        final enabled = await ensureServicesEnabled();
                                        if (enabled) p2pNotifier.startScanning();
                                      } else {
                                        p2pNotifier.disconnect();
                                      }
                                    },
                            ),
                            if (p2pState.isScanning && p2pState.discoveredDevices.isNotEmpty && p2pState.clientState?.isActive != true) ...[
                              const Divider(height: 1),
                              ...p2pState.discoveredDevices.map(
                                (device) => ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.bluetooth, size: 18),
                                  title: Text(device.deviceName.isEmpty ? 'Unknown Device' : device.deviceName),
                                  trailing: TextButton(
                                    onPressed: p2pState.isConnecting ? null : () => p2pNotifier.connectToDevice(device),
                                    child: const Text('Connect'),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (Platform.isAndroid)
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
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
                        // ignore
                      }
                    },
                    icon: const Icon(Icons.android, size: 18),
                    label: const Text('Share App (APK) via Bluetooth/Wi-Fi'),
                    style: TextButton.styleFrom(foregroundColor: Colors.grey.shade700),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusItem(BuildContext context, {required IconData icon, required String label, required String value}) {
    return Column(
      children: [
        Icon(icon, color: Colors.green.shade700, size: 20),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.green.shade800)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
      ],
    );
  }
}
