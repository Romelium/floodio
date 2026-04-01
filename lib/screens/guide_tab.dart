import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/admin_trusted_sender_provider.dart';
import '../providers/local_user_provider.dart';
import '../providers/revoked_delegation_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/ui_helpers.dart';

class GuideTab extends ConsumerWidget {
  const GuideTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final localUserAsync = ref.watch(localUserControllerProvider);
    final myPublicKey = localUserAsync.value?.publicKey;

    final adminTrustedAsync = ref.watch(adminTrustedSendersControllerProvider);
    final revokedAsync = ref.watch(revokedDelegationsControllerProvider);

    final adminTrusted = adminTrustedAsync.value ?? [];
    final revoked = revokedAsync.value ?? [];
    final revokedKeys = revoked.map((e) => e.delegateePublicKey).toSet();

    final isTier2 = myPublicKey != null &&
        adminTrusted.any((a) =>
            a.publicKey == myPublicKey && !revokedKeys.contains(a.publicKey));
    final isOfficial = settings.isOfficialMode;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          expandedHeight: 120.0,
          floating: false,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: const Text(
              'User Guide',
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
            ),
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.tertiary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildRoleBanner(context, isOfficial, isTier2),
                const SizedBox(height: 24),
                _buildQuickStartCard(context, isOfficial, isTier2),
                const SizedBox(height: 24),
                _buildEmergencyProtocolCard(context, isOfficial, isTier2),
                const SizedBox(height: 24),
                
                if (isOfficial) ...[
                  const Text('Official Capabilities', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildConceptTile(context, icon: Icons.campaign, title: 'Broadcast Alerts', description: 'Use the "+" button to send Official Alerts. These appear in Blue (Tier 1) and override all other reports.', color: Colors.blue),
                  _buildConceptTile(context, icon: Icons.admin_panel_settings, title: 'Manage Volunteers', description: 'Find reliable users in the feed and tap "Make Volunteer" to grant them Tier 2 status. Manage them in the Command Tab.', color: Colors.purple),
                  _buildConceptTile(context, icon: Icons.cloud_sync, title: 'Cloud Gateway', description: 'When you have internet, use the Command Tab to force a Cloud Sync. This bridges the offline mesh network with the central government database.', color: Colors.indigo),
                  const SizedBox(height: 24),
                ] else if (isTier2) ...[
                  const Text('Volunteer Capabilities', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildConceptTile(context, icon: Icons.verified, title: 'Verify Reports', description: 'When you physically confirm a crowdsourced (Grey) report, tap "Verify & Endorse". It will be upgraded to Verified (Purple) for the entire network.', color: Colors.purple),
                  _buildConceptTile(context, icon: Icons.gavel, title: 'Debunk Misinformation', description: 'If you see a false report, tap "Debunk". This is a GLOBAL action that deletes the report from the entire mesh network.', color: Colors.red),
                  const SizedBox(height: 24),
                ] else ...[
                  const Text('Citizen Capabilities', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildConceptTile(context, icon: Icons.add_location_alt, title: 'Report Hazards', description: 'Use the "+" button to report floods, roadblocks, or safe zones. Your reports start as Unverified (Grey) until a volunteer confirms them.', color: Colors.blueGrey),
                  _buildConceptTile(context, icon: Icons.verified_user, title: 'Trust Users', description: 'If you know someone is reliable, tap "Trust" on their report. Their future reports will appear as Trusted (Green) for YOU ONLY.', color: Colors.green),
                  const SizedBox(height: 24),
                ],

                const Text('Core Concepts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildConceptTile(context, icon: Icons.sync, title: 'Mesh Syncing', description: 'Tap the status chip in the top right. Toggle "Mesh Auto-Sync" to ON. Your phone will automatically find nearby users via Bluetooth and exchange data via Wi-Fi Direct.', color: Colors.teal),
                _buildConceptTile(context, icon: Icons.map, title: 'Offline Maps', description: 'Standard maps require internet. Go to the Map tab and tap the Download icon to save your area. You can "Broadcast" this map to others via the Sync menu.', color: Colors.orange),
                
                const SizedBox(height: 24),
                const Text(
                  'The 4-Tier Trust Model',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'To prevent misinformation, every report is cryptographically signed and categorized:',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                _buildTrustTierInfo(context, 1),
                _buildTrustTierInfo(context, 2),
                _buildTrustTierInfo(context, 3),
                _buildTrustTierInfo(context, 4),
                const SizedBox(height: 24),
                const Text(
                  'Frequently Asked Questions',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildFAQ(
                  'Does this drain my battery?',
                  'Mesh syncing uses Bluetooth Low Energy (BLE) to find peers, which is very efficient. However, frequent Wi-Fi Direct transfers can impact battery. You can adjust the "Sync Interval" in Settings.',
                ),
                _buildFAQ(
                  'What is a "Global Action"?',
                  'When an Official or Volunteer Resolves a hazard or Debunks a report, that "deletion" is broadcast to the whole network. Once you sync with someone, they will also see that hazard as removed.',
                ),
                _buildFAQ(
                  'Is my data private?',
                  'Your reports are signed with a unique cryptographic key stored only on your device. While your name is shared with reports, your exact location is only shared when you explicitly create a marker.',
                ),
                _buildFAQ(
                  'Why do I need so many permissions?',
                  'Android requires Location and Nearby Devices permissions to use Bluetooth and Wi-Fi Direct. Floodio does not track you for advertising; it only uses these to find other mesh nodes.',
                ),
                const SizedBox(height: 24),
                const Text(
                  'Troubleshooting',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildFAQ(
                  'My status says "OFFLINE" even with Auto-Sync on?',
                  'Ensure Bluetooth and Location are enabled. Android requires Location services to be ON for Bluetooth scanning to work. Also, check if you have granted the "Nearby Devices" permission.',
                ),
                _buildFAQ(
                  'Syncing is taking a long time?',
                  'Wi-Fi Direct can sometimes be slow to negotiate. Try moving closer to the other device. If it fails, try toggling Auto-Sync off and on again.',
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleBanner(BuildContext context, bool isOfficial, bool isTier2) {
    Color bgColor;
    Color textColor;
    String title;
    String subtitle;
    IconData icon;

    if (isOfficial) {
      bgColor = Colors.blue.shade50;
      textColor = Colors.blue.shade900;
      title = 'Official Mode Active';
      subtitle = 'You have full administrative capabilities to broadcast alerts and manage volunteers.';
      icon = Icons.security;
    } else if (isTier2) {
      bgColor = Colors.purple.shade50;
      textColor = Colors.purple.shade900;
      title = 'Verified Volunteer';
      subtitle = 'You are a trusted node. You can verify crowdsourced reports and debunk misinformation.';
      icon = Icons.admin_panel_settings;
    } else {
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade900;
      title = 'Citizen Node';
      subtitle = 'You are part of the mesh. Report hazards and sync with others to keep your community informed.';
      icon = Icons.people;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 36),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: textColor, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStartCard(BuildContext context, bool isOfficial, bool isTier2) {
    return Card(
      elevation: 4,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: Colors.yellow.shade800, size: 28),
                const SizedBox(width: 8),
                const Text(
                  'Quick Start',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildStep(1, 'Enable Auto-Sync', 'Tap the status chip in the top right and toggle "Mesh Auto-Sync" to ON.'),
            if (isOfficial) ...[
              _buildStep(2, 'Broadcast Alerts', 'Use the "+" button to send Official Alerts to the network.'),
              _buildStep(3, 'Promote Volunteers', 'Find reliable users in the feed and tap "Make Volunteer".'),
              _buildStep(4, 'Cloud Gateway', 'Use the Command Tab to sync the offline mesh with the internet when available.'),
            ] else if (isTier2) ...[
              _buildStep(2, 'Verify Reports', 'Check Unverified (Grey) reports. If true, tap "Verify & Endorse".'),
              _buildStep(3, 'Debunk False Info', 'If a report is false, tap "Debunk" to remove it for everyone.'),
              _buildStep(4, 'Share Maps', 'Download offline maps and broadcast them to users who need them.'),
            ] else ...[
              _buildStep(2, 'Download a Map', 'While you have internet, use the download button on the map to save your local area.'),
              _buildStep(3, 'Report Hazards', 'Use the "+" button to mark floods or roadblocks. Your reports will spread automatically.'),
              _buildStep(4, 'Trust Reliable Users', 'Tap "Trust" on reports from people you know to prioritize their updates.'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyProtocolCard(BuildContext context, bool isOfficial, bool isTier2) {
    String text;
    if (isOfficial) {
      text = 'In a crisis, use the Command Tab to force cloud syncs when internet is available. Issue "Critical" alerts for immediate evacuation notices. These will bypass filters and alert all users.';
    } else if (isTier2) {
      text = 'In a crisis, misinformation can be deadly. Actively monitor the feed for Unverified (Grey) reports. If you physically verify them, use "Verify & Endorse". If you know they are false, use "Debunk" to delete them globally.';
    } else {
      text = 'If you see a hazard, report it immediately. If you see a false report, you can "Block" the sender locally to hide their posts. Leave global debunking to Verified Volunteers (Purple) and Officials (Blue).';
    }

    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gavel, color: Colors.red.shade900),
                const SizedBox(width: 8),
                Text(
                  'Emergency Protocol',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: Colors.blue.shade100,
            child: Text(num.toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                Text(desc, style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConceptTile(BuildContext context, {required IconData icon, required String title, required String description, required Color color}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(description, style: const TextStyle(fontSize: 14, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrustTierInfo(BuildContext context, int tier) {
    final color = getTierColor(tier);
    String title = getTrustTierName(tier);
    String desc = '';
    IconData icon = Icons.help;

    switch (tier) {
      case 1:
        icon = Icons.verified;
        desc = 'Reports from Government, NGOs, or Emergency Services. These are always prioritized and highlighted in blue.';
        break;
      case 2:
        icon = Icons.admin_panel_settings;
        desc = 'Reports from vetted volunteers. These carry high weight and can be used to verify crowdsourced data.';
        break;
      case 3:
        icon = Icons.thumb_up;
        desc = 'People you have personally marked as "Trusted" in your Profile. Their reports are prioritized on your device only.';
        break;
      case 4:
        icon = Icons.people;
        desc = 'General public reports. These are unverified until endorsed by a Tier 1 or Tier 2 user.';
        break;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(desc, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildFAQ(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              answer,
              style: TextStyle(color: Colors.grey.shade800, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// A helper widget to show a mini-tutorial overlay on first launch
class TutorialOverlay extends StatefulWidget {
  final Widget child;
  final VoidCallback onComplete;
  const TutorialOverlay({super.key, required this.child, required this.onComplete});

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  bool _showTutorial = false;
  int _currentStep = 0;

  final List<Map<String, String>> _steps = [
    {
      'title': 'Welcome to Floodio',
      'content': 'This app helps you stay informed during floods, even when the internet is down.',
      'icon': '👋',
    },
    {
      'title': 'Mesh Networking',
      'content': 'The status chip at the top shows your connection. Tap it to enable Auto-Sync and automatically share data with nearby phones via Bluetooth and Wi-Fi.',
      'icon': '📡',
    },
    {
      'title': 'Trust Tiers',
      'content': 'Reports are color-coded to fight misinformation:\n🔵 Official\n🟣 Verified Volunteer\n🟢 Personally Trusted\n⚪ Unverified Public',
      'icon': '🛡️',
    },
    {
      'title': 'Reporting Hazards',
      'content': 'Use the "+" button to report floods or roadblocks. Your report will spread to others as they pass by you.',
      'icon': '📍',
    },
    {
      'title': 'Offline Maps',
      'content': 'Tap the download icon on the map to save areas for offline use. You can even share these maps with others over the mesh!',
      'icon': '🗺️',
    },
  ];

  @override
  void initState() {
    super.initState();
    _showTutorial = true;
  }

  void _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_tutorial', true);
    widget.onComplete();
    setState(() => _showTutorial = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showTutorial)
          Positioned.fill(
            child: Material(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _steps[_currentStep]['icon']!,
                        style: const TextStyle(fontSize: 80),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _steps[_currentStep]['title']!,
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _steps[_currentStep]['content']!,
                        style: const TextStyle(color: Colors.white70, fontSize: 18, height: 1.4),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_currentStep > 0)
                            OutlinedButton(
                              onPressed: () => setState(() => _currentStep--),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24)),
                              child: const Text('Back'),
                            ),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () {
                              if (_currentStep < _steps.length - 1) {
                                setState(() => _currentStep++);
                              } else {
                                _finish();
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                            ),
                            child: Text(_currentStep < _steps.length - 1 ? 'Next' : 'Start Using Floodio'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Step ${_currentStep + 1} of ${_steps.length}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
      ],
    );
  }
}
