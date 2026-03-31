import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_trusted_sender_provider.dart';
import '../providers/p2p_provider.dart';
import '../providers/revoked_delegation_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/mock_gov_api_service.dart';
import '../utils/ui_helpers.dart';

class CommandTab extends ConsumerWidget {
  const CommandTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminTrustedAsync = ref.watch(adminTrustedSendersControllerProvider);
    final revokedAsync = ref.watch(revokedDelegationsControllerProvider);
    final profilesAsync = ref.watch(userProfilesControllerProvider);

    final adminTrusted = adminTrustedAsync.value ?? [];
    final revoked = revokedAsync.value ?? [];
    final profiles = profilesAsync.value ?? [];

    final revokedKeys = revoked.map((e) => e.delegateePublicKey).toSet();
    final activeVolunteers = adminTrusted.where((a) => !revokedKeys.contains(a.publicKey)).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Command Center',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage official volunteers and broadcast emergency alerts.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                
                // Cloud Gateway Section
                const Row(
                  children: [
                    Icon(Icons.cloud_sync, color: Colors.blue),
                    SizedBox(width: 8),
                    Text(
                      'Cloud Gateway',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCloudGatewayCard(context, ref),
                
                const SizedBox(height: 32),
                
                Row(
                  children: [
                    const Icon(Icons.admin_panel_settings, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Text(
                      'Active Volunteers (Tier 2)',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Chip(
                      label: Text('${activeVolunteers.length}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (activeVolunteers.isEmpty)
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
                            'No active volunteers. You can promote trusted users from the feed.',
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
                      itemCount: activeVolunteers.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final volunteer = activeVolunteers[index];
                        final profile = getProfile(volunteer.publicKey, profiles);
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.purple.shade100,
                            child: const Icon(
                              Icons.verified_user,
                              color: Colors.purple,
                            ),
                          ),
                          title: Text(
                            profile?.name ?? 'Unknown User',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Key: ${volunteer.publicKey.substring(0, 12)}...',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: FilledButton.tonalIcon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Revoke Volunteer?'),
                                  content: Text(
                                    'Are you sure you want to revoke volunteer status for ${profile?.name ?? 'this user'}? Their reports will be downgraded.',
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
                                        await ref.read(mockGovApiServiceProvider.notifier).revokeAdminTrust(volunteer.publicKey);
                                        ref.read(p2pServiceProvider.notifier).triggerSync();
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Volunteer status revoked.')),
                                          );
                                        }
                                      },
                                      child: const Text('Revoke'),
                                    ),
                                  ],
                                ),
                              );
                            },
                            icon: const Icon(Icons.remove_moderator, size: 16),
                            label: const Text('Revoke'),
                            style: FilledButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              backgroundColor: Colors.red.shade50,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCloudGatewayCard(BuildContext context, WidgetRef ref) {
    final cloudState = ref.watch(cloudSyncServiceProvider);
    final cloudNotifier = ref.read(cloudSyncServiceProvider.notifier);

    String lastSyncText = 'Never';
    if (cloudState.lastSyncTime != null) {
      final dt = cloudState.lastSyncTime!.toLocal();
      lastSyncText = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  cloudState.hasInternet ? Icons.wifi : Icons.wifi_off,
                  color: cloudState.hasInternet ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  cloudState.hasInternet ? 'Internet Connected' : 'No Internet Connection',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cloudState.hasInternet ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
                const Spacer(),
                if (cloudState.isSyncing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Pending Uploads:', style: TextStyle(color: Colors.grey)),
                Text(
                  '${cloudState.pendingUploads} items',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Last Sync:', style: TextStyle(color: Colors.grey)),
                Text(
                  lastSyncText,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: cloudState.isSyncing
                    ? null
                    : () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Initiating cloud sync...')),
                        );
                        final success = await cloudNotifier.syncWithCloud();
                        if (context.mounted) {
                          if (success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cloud sync complete.')),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cloud sync failed. Check connection.')),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.cloud_upload, size: 18),
                label: const Text('Force Sync Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
