import 'dart:io';

import 'package:floodio/providers/p2p_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/offline_regions_provider.dart';
import '../providers/ui_p2p_provider.dart';
import '../services/cloud_sync_service.dart';
import '../utils/permission_utils.dart';
import '../utils/ui_helpers.dart';
import 'radar_animation.dart';

class SyncBottomSheet extends ConsumerWidget {
  const SyncBottomSheet({super.key});

  void _showSyncHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Sync & Connect Guide'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mesh Auto-Sync', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Automatically switches between hosting and scanning to find nearby devices and exchange data seamlessly in the background.'),
              SizedBox(height: 12),
              Text('Host Mode', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Creates a Wi-Fi Direct group. Other devices can scan and connect to you to receive and send data.'),
              SizedBox(height: 12),
              Text('Join Mode', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Scans for nearby Hosts using Bluetooth. Once found, it connects to their Wi-Fi Direct group to sync data.'),
              SizedBox(height: 12),
              Text('Cloud Gateway', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('When you have internet access, use this to upload local mesh data to the cloud and download global updates.'),
              SizedBox(height: 12),
              Text('Available Peer Maps', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('If a connected peer has downloaded an offline map, you can request it directly from them without needing internet.'),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p2pState = ref.watch(uiP2pServiceProvider);
    final p2pNotifier = ref.read(uiP2pServiceProvider.notifier);
    final myRegionsAsync = ref.watch(offlineRegionsProvider);
    final myRegions = myRegionsAsync.value ?? [];

    final isConnected =
        (p2pState.isHosting && p2pState.hostState?.isActive == true) ||
        p2pState.clientState?.isActive == true;
    final hasPeers = (p2pState.isHosting && p2pState.connectedClients.isNotEmpty) ||
        (p2pState.clientState?.isActive == true);
    final isBusy =
        p2pState.isSyncing || p2pState.isConnecting || p2pState.isScanning;
    final isSyncingOrConnecting = p2pState.isSyncing || p2pState.isConnecting;

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
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.help_outline),
                          onPressed: () => _showSyncHelp(context),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.blue.shade50,
                            foregroundColor: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.grey.shade100,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 1. Network Status
                _buildNetworkStatusCard(context, ref, p2pState, isConnected, hasPeers, isBusy, isSyncingOrConnecting),

                const SizedBox(height: 24),
                const Text('Connection Mode', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),

                // 2. Auto-Sync
                _buildModeCard(
                  context: context,
                  title: 'Mesh Auto-Sync',
                  subtitle: 'Automatically switch between hosting and scanning to relay data.',
                  icon: Icons.autorenew,
                  activeColor: Colors.blue.shade700,
                  isActive: p2pState.isAutoSyncing,
                  isDisabled: false,
                  onChanged: (val) async {
                    if (val) {
                      final enabled = await ensureServicesEnabled();
                      if (enabled) p2pNotifier.toggleAutoSync();
                    } else {
                      p2pNotifier.toggleAutoSync();
                    }
                  },
                ),
                const SizedBox(height: 12),

                // 3. Manual Controls Row
                Row(
                  children: [
                    Expanded(
                      child: _buildSmallModeCard(
                        context: context,
                        title: 'Host',
                        subtitle: 'Create node',
                        icon: Icons.router,
                        activeColor: Colors.green.shade700,
                        isActive: p2pState.isHosting,
                        isDisabled: p2pState.isScanning || p2pState.isAutoSyncing,
                        onChanged: (val) async {
                          if (val) {
                            final enabled = await ensureServicesEnabled(isHosting: true);
                            if (enabled) p2pNotifier.startHosting();
                          } else {
                            p2pNotifier.stopHosting();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSmallModeCard(
                        context: context,
                        title: 'Join',
                        subtitle: 'Scan nodes',
                        icon: Icons.radar,
                        activeColor: Colors.teal.shade700,
                        isActive: p2pState.isScanning || p2pState.clientState?.isActive == true,
                        isDisabled: p2pState.isHosting || p2pState.isAutoSyncing,
                        onChanged: (val) async {
                          if (val) {
                            final enabled = await ensureServicesEnabled();
                            if (enabled) p2pNotifier.startScanning();
                          } else {
                            p2pNotifier.disconnect();
                          }
                        },
                      ),
                    ),
                  ],
                ),

                // If hosting and has clients, show them
                if (p2pState.hostState?.isActive == true && p2pState.connectedClients.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Connected Peers (${p2pState.connectedClients.length})', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                        const SizedBox(height: 8),
                        ...p2pState.connectedClients.map((client) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Row(
                            children: [
                              Icon(Icons.smartphone, size: 14, color: Colors.green.shade700),
                              const SizedBox(width: 8),
                              Expanded(child: Text(client.username.isEmpty ? 'Unknown Client' : client.username, style: TextStyle(fontSize: 13, color: Colors.green.shade900))),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],

                // If scanning and found devices, show them
                if (p2pState.isScanning && p2pState.discoveredDevices.isNotEmpty && p2pState.clientState?.isActive != true) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Discovered Nodes (${p2pState.discoveredDevices.length})', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade900)),
                        const SizedBox(height: 8),
                        ...p2pState.discoveredDevices.map((device) => Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Row(
                            children: [
                              Icon(Icons.bluetooth, size: 14, color: Colors.teal.shade700),
                              const SizedBox(width: 8),
                              Expanded(child: Text(device.deviceName.isEmpty ? 'Unknown Device' : device.deviceName, style: TextStyle(fontSize: 13, color: Colors.teal.shade900))),
                              SizedBox(
                                height: 28,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12), backgroundColor: Colors.teal.shade600),
                                  onPressed: p2pState.isConnecting ? null : () => p2pNotifier.connectToDevice(device),
                                  child: const Text('Connect', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                            ],
                          ),
                        )),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                const Text('Cloud & Maps', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),

                // 4. Cloud Sync Section
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
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cloudSyncState.hasInternet
                                ? Colors.blue.shade50
                                : Colors.red.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            cloudSyncState.hasInternet
                                ? Icons.cloud_sync
                                : Icons.cloud_off,
                            color: cloudSyncState.hasInternet
                                ? Colors.blue
                                : Colors.red,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : FilledButton.tonal(
                                onPressed: cloudSyncState.hasInternet
                                    ? () async {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Syncing with cloud...',
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                        final success = await cloudSyncNotifier
                                            .syncWithCloud();
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                success
                                                    ? 'Cloud sync complete.'
                                                    : 'Cloud sync failed.',
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    : null,
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
                                              behavior:
                                                  SnackBarBehavior.floating,
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

                if (Platform.isAndroid)
                  TextButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      try {
                        const platform = MethodChannel(
                          'com.example.floodio/apk',
                        );
                        final String? apkPath = await platform.invokeMethod(
                          'getApkPath',
                        );

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
                              text:
                                  'Install Floodio to stay connected during emergencies!',
                            ),
                          );
                        }
                      } catch (e) {
                        // ignore
                      }
                    },
                    icon: const Icon(Icons.android, size: 18),
                    label: const Text('Share App (APK) via Bluetooth/Wi-Fi'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color activeColor,
    required bool isActive,
    required bool isDisabled,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: isDisabled ? null : () => onChanged(!isActive),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isActive ? LinearGradient(colors: [activeColor, activeColor.withValues(alpha: 0.8)]) : null,
          color: isActive ? null : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? activeColor : Colors.grey.shade300),
          boxShadow: isActive ? [BoxShadow(color: activeColor.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 4))] : null,
        ),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isActive ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: isActive ? Colors.white : activeColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: isActive ? Colors.white : null)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 13, color: isActive ? Colors.white70 : Colors.grey.shade600)),
                  ],
                ),
              ),
              Switch(
                value: isActive,
                onChanged: isDisabled ? null : onChanged,
                activeThumbColor: Colors.white,
                activeTrackColor: activeColor.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSmallModeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color activeColor,
    required bool isActive,
    required bool isDisabled,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: isDisabled ? null : () => onChanged(!isActive),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive ? activeColor : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? activeColor : Colors.grey.shade300),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, color: isActive ? Colors.white : activeColor, size: 24),
                  Switch(
                    value: isActive,
                    onChanged: isDisabled ? null : onChanged,
                    activeThumbColor: Colors.white,
                    activeTrackColor: activeColor.withValues(alpha: 0.5),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isActive ? Colors.white : null)),
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(fontSize: 12, color: isActive ? Colors.white70 : Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkStatusCard(
    BuildContext context,
    WidgetRef ref,
    P2pState p2pState,
    bool isConnected,
    bool hasPeers,
    bool isBusy,
    bool isSyncingOrConnecting,
  ) {
    return Card(
      color: hasPeers
          ? Colors.green.shade50
          : (p2pState.isAutoSyncing
                ? Colors.orange.shade50
                : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: hasPeers
              ? Colors.green.shade200
              : (p2pState.isAutoSyncing
                    ? Colors.orange.shade200
                    : Colors.transparent),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((p2pState.isScanning || p2pState.isHosting) && !hasPeers) ...[
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 16.0),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: (p2pState.isScanning ? Colors.teal : Colors.green).withValues(alpha: 0.2),
                        blurRadius: 24,
                        spreadRadius: 4,
                      )
                    ]
                  ),
                  child: p2pState.isScanning
                    ? RadarAnimation(size: 140, color: Colors.teal.shade600)
                    : RippleAnimation(size: 140, color: Colors.green.shade600),
                ),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                if (isSyncingOrConnecting)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      value: p2pState.syncProgress,
                      strokeWidth: 3,
                    ),
                  )
                else if (!p2pState.isScanning && !(p2pState.isHosting && !hasPeers))
                  Icon(
                    hasPeers
                        ? Icons.check_circle
                        : (p2pState.isAutoSyncing
                              ? Icons.radar
                              : Icons.cloud_off),
                    color: hasPeers
                        ? Colors.green
                        : (p2pState.isAutoSyncing
                              ? Colors.orange
                              : Colors.grey),
                    size: 24,
                  ),
                if (!p2pState.isScanning && !(p2pState.isHosting && !hasPeers)) const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasPeers
                        ? 'Connected to Mesh'
                        : (p2pState.isScanning
                              ? 'Scanning for Peers...'
                              : (p2pState.isHosting
                                    ? 'Broadcasting Presence...'
                                    : (p2pState.isAutoSyncing
                                          ? 'Auto-Sync Active'
                                          : 'Standby (Auto-Sync Off)'))),
                    style: TextStyle(
                      fontSize: 16,
                      color: hasPeers
                          ? Colors.green.shade800
                          : (p2pState.isAutoSyncing
                                ? Colors.orange.shade800
                                : Colors.grey.shade700),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                    textAlign: (p2pState.isScanning || (p2pState.isHosting && !hasPeers)) ? TextAlign.center : TextAlign.left,
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
            if (isConnected) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatusItem(
                    context,
                    icon: p2pState.hostState?.isActive == true ? Icons.router : Icons.smartphone,
                    label: 'Role',
                    value: p2pState.hostState?.isActive == true ? 'Host' : 'Client',
                  ),
                  _buildStatusItem(
                    context,
                    icon: Icons.people,
                    label: 'Peers',
                    value: p2pState.hostState?.isActive == true ? '${p2pState.connectedClients.length}' : '1 (Host)',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: p2pState.isSyncing
                      ? null
                      : () {
                          ref.read(uiP2pServiceProvider.notifier).triggerSync();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Triggered manual mesh sync...'),
                              behavior: SnackBarBehavior.floating,
                            ),
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
    );
  }

  Widget _buildStatusItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.green.shade700, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.green.shade800),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade900,
          ),
        ),
      ],
    );
  }
}
