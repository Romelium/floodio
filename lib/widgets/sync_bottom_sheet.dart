import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/ui_p2p_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../services/cloud_sync_service.dart';

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
                    margin: const EdgeInsets.only(bottom: 16),
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
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: (p2pState.isSyncing || p2pState.isConnecting)
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
                          : Theme.of(context).colorScheme.outlineVariant,
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
                            color: Theme.of(context).colorScheme.primary,
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
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.black87,
                                ),
                              ),
                              if (p2pState.isSyncing ||
                                  p2pState.isConnecting) ...[
                                const SizedBox(height: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                    color: Theme.of(context).colorScheme.primary,
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
                            leading: Icon(
                              cloudSyncState.hasInternet ? Icons.cloud_sync : Icons.cloud_off,
                              color: cloudSyncState.hasInternet ? Colors.blue : Colors.red,
                            ),
                            title: const Text(
                              'Cloud Gateway Sync',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Last synced: $lastSyncText\n${cloudSyncState.hasInternet ? 'Internet connected.' : 'No internet connection.'}',
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
                                    onPressed: cloudSyncState.hasInternet ? () async {
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
                                        if (success) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Cloud sync complete.',
                                              ),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        } else {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Cloud sync failed.',
                                              ),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    } : null,
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
