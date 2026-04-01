import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                const Text(
                  'Core Concepts',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildConceptTile(
                  context,
                  icon: Icons.hub,
                  title: 'The Mesh Network',
                  description: 'Floodio works without internet. It uses Bluetooth and Wi-Fi Direct to "gossip" data between phones. When two users are near each other, their databases automatically sync missing reports.',
                  color: Colors.blue,
                ),
                _buildConceptTile(
                  context,
                  icon: Icons.directions_run,
                  title: 'Functioning as a "Mule"',
                  description: 'If you have internet access, your app downloads the latest official data. When you move to an offline area, you carry that data with you and automatically share it with offline users you encounter.',
                  color: Colors.orange,
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
                  'How do I get offline maps?',
                  'Tap the Download icon on the Map screen. Select an area while you have internet. You can then "Broadcast" this map to others who are offline via the Sync menu.',
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
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
  const TutorialOverlay({super.key, required this.child});

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
    },
    {
      'title': 'The Mesh Network',
      'content': 'Data is shared phone-to-phone. Keep Bluetooth on to automatically sync with people nearby.',
    },
    {
      'title': 'Trust Tiers',
      'content': 'Look for the "Official" and "Verified" badges to find the most reliable information.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _checkFirstTime();
  }

  void _checkFirstTime() async {
    // In a real app, check SharedPreferences here
    // For now, we'll just show it once per session if needed
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showTutorial)
          Container(
            color: Colors.black87,
            width: double.infinity,
            height: double.infinity,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _steps[_currentStep]['title']!,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _steps[_currentStep]['content']!,
                      style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.normal, decoration: TextDecoration.none),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_currentStep > 0)
                          TextButton(
                            onPressed: () => setState(() => _currentStep--),
                            child: const Text('Back', style: TextStyle(color: Colors.white)),
                          ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () {
                            if (_currentStep < _steps.length - 1) {
                              setState(() => _currentStep++);
                            } else {
                              setState(() => _showTutorial = false);
                            }
                          },
                          child: Text(_currentStep < _steps.length - 1 ? 'Next' : 'Got it!'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
