import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';
import '../utils/clear_data.dart';

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
            trailing: DropdownButtonHideUnderline(
              child: DropdownButton<MapStyle>(
                value: settings.mapStyle,
                borderRadius: BorderRadius.circular(12),
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
              'How often the device switches between broadcasting and scanning for peers.',
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
              'Note: Faster sync intervals consume more battery but discover peers much quicker. 15s-30s is recommended during active emergencies. Smart-Sync automatically pauses scanning when stationary to save up to 80% battery.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Data Management',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Clear All Data',
              style: TextStyle(color: Colors.red),
            ),
            subtitle: const Text(
              'Deletes all reports, maps, and profile data.',
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Clear All Data?'),
                  content: const Text(
                    'This action cannot be undone. All your reports, trusted senders, and offline maps will be deleted from THIS DEVICE ONLY. It will not remove your previously synced reports from the mesh network.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () async {
                        HapticFeedback.heavyImpact();
                        Navigator.pop(dialogContext);
                        await clearAllAppData(context, ref);
                      },
                      child: const Text('Clear Data'),
                    ),
                  ],
                ),
              );
            },
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
