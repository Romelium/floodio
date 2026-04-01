import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/ui_helpers.dart';

class GuideTab extends ConsumerWidget {
  const GuideTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                _buildQuickStartCard(context),
                const SizedBox(height: 24),
                _buildEmergencyProtocolCard(context),
                const SizedBox(height: 24),
                const Text(
                  'Core Concepts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Getting Started',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildConceptTile(
                  context,
                  icon: Icons.sync,
                  title: '1. Enable Mesh Sync',
                  description: 'Tap the status chip in the top right (usually says "OFFLINE"). Toggle "Mesh Auto-Sync" to ON. Your phone will now periodically look for other Floodio users nearby.',
                  color: Colors.green,
                ),
                _buildConceptTile(
                  context,
                  icon: Icons.map,
                  title: '2. Prepare Offline Maps',
                  description: 'While you have internet, go to the Map tab and tap the Download icon. Select your local area. This ensures you can see streets even when the grid is down.',
                  color: Colors.teal,
                ),
                _buildConceptTile(
                  context,
                  icon: Icons.add_circle_outline,
                  title: '3. Report & Share',
                  description: 'Use the "+" button to report hazards. When you walk past another user, your reports will automatically jump to their phone, and theirs to yours.',
                  color: Colors.blue,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Advanced Mesh Features',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildConceptTile(
                  context,
                  icon: Icons.hub,
                  title: 'Broadcasting Maps',
                  description: 'If you have a map downloaded and meet someone who doesn\'t, you can "Broadcast" it to them. Open the Sync menu, and if connected, you\'ll see an option to send your map regions.',
                  color: Colors.orange,
                ),
                _buildConceptTile(
                  context,
                  icon: Icons.gavel,
                  title: 'Global vs Local Actions',
                  description: 'Resolving a hazard or debunking a report is a GLOBAL action—it deletes the item for everyone. Trusting a sender is a LOCAL action—it only changes how YOU see their reports.',
                  color: Colors.red,
                ),
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
                  'Map Management',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildConceptTile(
                  context,
                  icon: Icons.map_outlined,
                  title: 'Offline Maps',
                  description: 'Standard maps require internet. Use the Download icon on the Map tab to save a region. You can then "Broadcast" this map file to other users who have no internet at all.',
                  color: Colors.teal,
                ),
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
                  'When you Resolve a hazard or Debunk a report, that "deletion" is broadcast to the whole network. Once you sync with someone, they will also see that hazard as removed.',
                ),
                _buildFAQ(
                  'Is my data private?',
                  'Your reports are signed with a unique cryptographic key stored only on your device. While your name is shared with reports, your exact location is only shared when you explicitly create a marker.',
                ),
                _buildFAQ(
                  'Why do I need so many permissions?',
                  'Android requires Location and Nearby Devices permissions to use Bluetooth and Wi-Fi Direct. Floodio does not track you for advertising; it only uses these to find other mesh nodes.',
                ),
                _buildFAQ(
                  'How do I get offline maps?',
                  'Tap the Download icon on the Map screen. Select an area while you have internet. You can then "Broadcast" this map to others who are offline via the Sync menu.',
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

  Widget _buildEmergencyProtocolCard(BuildContext context) {
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
            const Text(
              'In a crisis, misinformation can be deadly. If you see a report you know is false, use the "Debunk" action. This is a GLOBAL action that will tell every device you sync with to delete that report.',
              style: TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStartCard(BuildContext context) {
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
            _buildStep(1, 'Enable Auto-Sync', 'Tap the "OFFLINE" chip in the top right and toggle "Mesh Auto-Sync" to ON.'),
            _buildStep(2, 'Download a Map', 'While you have internet, use the download button on the map to save your local area.'),
            _buildStep(3, 'Report Hazards', 'Use the "+" button to mark floods, roadblocks, or safe zones. Your reports will spread to others automatically.'),
            _buildStep(4, 'Verify Others', 'If you see a report you know is true, tap "Verify & Endorse" to increase its trust level for the network.'),
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
        desc = 'People you have personally marked as "Trusted" in your Profile. Their reports are prioritized on your device.';
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
      'content': 'The "OFFLINE" chip at the top shows your sync status. Tap it to enable Auto-Sync and find nearby peers.',
      'icon': '📡',
    },
    {
      'title': 'Trust Tiers',
      'content': 'Reports have colors: Blue is Official, Purple is Verified, Green is Trusted, and Grey is Crowdsourced.',
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
