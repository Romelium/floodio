import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/settings_provider.dart';
import '../providers/database_provider.dart';
import '../providers/local_user_provider.dart';
import '../screens/initializer_screen.dart';

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
              'Note: Faster sync intervals consume more battery but discover peers much quicker. 15s-30s is recommended during active emergencies.',
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
                        Navigator.pop(dialogContext);
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
                        if (!context.mounted) return;
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
