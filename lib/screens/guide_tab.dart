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
              'User Guide & Tutorials',
              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 20),
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
                const SizedBox(height: 32),

                if (isOfficial) ...[
                  const Text('Official Guides', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.campaign,
                    title: 'Broadcasting Critical Alerts',
                    content: 'As an Official, your alerts override all other reports and are highlighted in blue (Tier 1).\n\n'
                             '• Tap the "+" button and select "Official Alert".\n'
                             '• Use the quick templates for standard alerts (e.g., Evacuation Order, Boil Water Advisory) to save time.\n'
                             '• Check "Mark as Critical Emergency" for immediate life-threatening situations. This ensures the alert is prominently displayed with a red warning.\n'
                             '• Set an appropriate expiration time so the alert automatically clears when the danger has passed.\n'
                             '• You can also create Official Map Markers (Supply, Medical Triage) from the "+" menu.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.admin_panel_settings,
                    title: 'Managing Volunteers',
                    content: 'You can delegate trust to reliable community members, empowering them to verify crowdsourced data.\n\n'
                             '• In the Feed or Map, tap on a report from a reliable user.\n'
                             '• Tap "Make Volunteer". This cryptographically signs a delegation certificate, upgrading them to Tier 2 (Verified).\n'
                             '• To manage or revoke volunteers, go to the "Command" tab.\n'
                             '• Revoking a volunteer immediately downgrades their future and past unverified reports across the entire network.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.cloud_sync,
                    title: 'Using the Cloud Gateway',
                    content: 'The Cloud Gateway bridges the offline mesh network with the central government database.\n\n'
                             '• When you have an active internet connection (e.g., via Starlink or a restored cell tower), go to the "Command" tab.\n'
                             '• Tap "Force Cloud Sync Now".\n'
                             '• This uploads all mesh data collected from citizens to the cloud and downloads the latest global official alerts to your device.\n'
                             '• You can then carry this updated data back into the offline mesh to distribute it to citizens.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.map,
                    title: 'Coordinating with Offline Maps',
                    content: 'Ensure your teams and citizens have access to maps even when cell towers are down.\n\n'
                             '• Download maps of high-risk areas while you have internet access.\n'
                             '• Use the "Command" tab to broadcast these maps to all connected devices in your local mesh.\n'
                             '• Encourage volunteers to request maps from you via their Sync Menu.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.directions_walk,
                    title: 'Acting as a Data Relay (Mule)',
                    content: 'You are the bridge between disconnected neighborhoods.\n\n'
                             '• Keep "Mesh Auto-Sync" enabled when moving between different areas or shelters.\n'
                             '• Your device will automatically pick up reports from one group and deliver them to the next.\n'
                             '• If you encounter an Official, sync with them to receive the latest critical alerts and pass them on to citizens.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.handshake,
                    title: 'Assisting Citizens',
                    content: 'Help others get connected and stay informed.\n\n'
                             '• Share the Floodio app via Bluetooth/Wi-Fi Direct using the Share icon in the top right.\n'
                             '• Broadcast your downloaded offline maps to citizens who need them via the Sync Menu.\n'
                             '• Teach them how to trust reliable neighbors to build their local web of trust.',
                  ),
                  const SizedBox(height: 24),
                ] else if (isTier2) ...[
                  const Text('Volunteer Guides', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.verified,
                    title: 'Verifying & Endorsing Reports',
                    content: 'Your primary role is to filter noise and elevate accurate information.\n\n'
                             '• When you physically confirm a crowdsourced (Grey) report, tap on it and select "Verify & Endorse".\n'
                             '• This cryptographically signs the report with your Tier 2 key, upgrading it to Purple (Verified) for the entire network.\n'
                             '• Only endorse reports you have personally verified to maintain the integrity of the network.\n'
                             '• Your endorsements help citizens know which hazards are real and which safe zones are actually safe.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.gavel,
                    title: 'Debunking Misinformation',
                    content: 'False reports can cause panic or misdirect resources.\n\n'
                             '• If you encounter a definitively false or malicious report, tap "Debunk".\n'
                             '• This is a GLOBAL action. It creates a cryptographic "tombstone" that actively deletes the report from the entire mesh network as devices sync.\n'
                             '• Use this power carefully. For hazards that have simply been cleared (e.g., water receded), use "Resolve" instead.',
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  const Text('Citizen Guides', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.add_location_alt,
                    title: 'Reporting Hazards Effectively',
                    content: 'Good reports save lives. Follow these best practices:\n\n'
                             '• Be Specific: Instead of just "Flood", write "Water is 2 feet deep, impassable for sedans."\n'
                             '• Add Photos: A picture provides instant context. Tap "Attach Photo" when creating a hazard.\n'
                             '• Set Expiration: If a road is temporarily blocked by a fallen tree, set it to expire in 12 or 24 hours so the map doesn\'t get cluttered with old data.\n'
                             '• Use Areas/Paths: For large floods, use "Report Area" to draw a polygon. For blocked evacuation routes, use "Report Path" to draw a line.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.verified_user,
                    title: 'Trusting Reliable Neighbors',
                    content: 'You can build your own localized web of trust.\n\n'
                             '• If you see a report from someone you know is reliable, tap "Trust" on their report.\n'
                             '• Their future reports will appear as Trusted (Green) for YOU ONLY.\n'
                             '• If someone posts spam or false info, tap "Block" to hide their reports from your device.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.battery_saver,
                    title: 'Conserving Battery',
                    content: 'During a disaster, battery life is critical.\n\n'
                             '• Mesh Auto-Sync uses Bluetooth Low Energy (BLE) to find peers, which is efficient, but frequent Wi-Fi Direct transfers use more power.\n'
                             '• You can adjust the "Sync Interval" in Settings (e.g., change from 30s to 5m) to save power.\n'
                             '• If you are stationary in a safe place, you can turn off Auto-Sync and only sync manually when needed.',
                  ),
                  _buildGuideExpansionTile(
                    context,
                    icon: Icons.share,
                    title: 'Sharing the App Offline',
                    content: 'If someone needs Floodio but has no internet, you can share the app directly:\n\n'
                             '• Tap the "Share" icon in the top right of the app bar.\n'
                             '• This extracts the Floodio APK from your device.\n'
                             '• Send it to them via Bluetooth, Nearby Share, or Wi-Fi Direct.\n'
                             '• Once they install it, they can immediately join the mesh network.',
                  ),
                  const SizedBox(height: 24),
                ],

                const Text('General Guides', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildGuideExpansionTile(
                  context,
                  icon: Icons.wifi_tethering,
                  title: 'How Mesh Syncing Works',
                  content: 'Floodio uses a "Store and Forward" mesh network to keep you connected without internet or cell towers.\n\n'
                           '• When Auto-Sync is ON, your phone uses Bluetooth Low Energy (BLE) to silently find nearby Floodio users.\n'
                           '• Once a peer is found, the phones automatically negotiate a high-speed, secure Wi-Fi Direct connection.\n'
                           '• They compare their databases using a highly efficient "Bloom Filter" and exchange only the missing reports, news, or map files.\n'
                           '• After syncing, they disconnect. As you move around, your phone carries this data and passes it to the next person you meet, spreading critical information across the city like a digital whisper.',
                ),
                _buildGuideExpansionTile(
                  context,
                  icon: Icons.map,
                  title: 'Using & Sharing Offline Maps',
                  content: 'Standard maps go blank without internet. Floodio allows you to save maps directly to your phone and share them offline.\n\n'
                           '• Downloading: Go to the Map tab, pan to your city, and tap the Download icon (top right). Choose your zoom level and download.\n'
                           '• Broadcasting: If you have a map and meet someone who doesn\'t, open the Sync Menu (tap the status chip) and select "Broadcast Offline Map". They will receive the map file directly over Wi-Fi Direct.\n'
                           '• Requesting: If a peer has a map you need, it will appear in your Sync Menu under "Available Peer Maps". Tap the download icon to request it.',
                ),
                _buildGuideExpansionTile(
                  context,
                  icon: Icons.cleaning_services,
                  title: 'Resolving vs. Debunking vs. Blocking',
                  content: 'It is important to use the right tool to manage reports:\n\n'
                           '• Resolve (Green Check): The hazard existed but is now cleared (e.g., water receded, tree removed). This removes it from the map for everyone globally.\n'
                           '• Debunk (Red Hammer - Officials/Volunteers only): The report was fake, malicious, or a duplicate. This deletes it globally and prevents it from spreading further.\n'
                           '• Block (Red Circle): You don\'t trust this user. This hides their reports on YOUR device only. It does not affect other users.',
                ),
                _buildGuideExpansionTile(
                  context,
                  icon: Icons.security,
                  title: 'Understanding Cryptographic Signatures',
                  content: 'To prevent malicious actors from spoofing official alerts or impersonating others, Floodio uses Ed25519 cryptographic signatures.\n\n'
                           '• Every user has a unique private key generated on their device.\n'
                           '• Every report you create is signed with this key.\n'
                           '• When an Official promotes a user to a Volunteer, they sign a "Trust Delegation" certificate.\n'
                           '• When your phone receives a report, it verifies the signature against the sender\'s public key and the known Official keys to determine its Trust Tier. Fake official reports are instantly rejected by the network.',
                ),

                const SizedBox(height: 32),

                const Text(
                  'The 4-Tier Trust Model',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'To prevent misinformation, every report is cryptographically signed and categorized:',
                  style: TextStyle(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 16),
                _buildTrustTierInfo(context, 1),
                _buildTrustTierInfo(context, 2),
                _buildTrustTierInfo(context, 3),
                _buildTrustTierInfo(context, 4),
                
                const SizedBox(height: 32),
                const Text(
                  'Frequently Asked Questions',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildFAQ(
                  'How do I draw an Area or Path?',
                  'Tap the "+" button and select "Report Area" or "Report Path". The map will enter drawing mode. Tap on the map to add points to your polygon or line. If you make a mistake, tap "Undo". When finished, tap the green "Done" button in the bottom right to add details and submit.',
                ),
                _buildFAQ(
                  'What happens when a report expires?',
                  'When creating a report, you can set an expiration time (e.g., 24 hours). Once that time passes, the report is automatically hidden from the map and feed. It will eventually be deleted from the database to keep the app fast and the map clean. You can extend the expiration by editing the report before it expires.',
                ),
                _buildFAQ(
                  'Does this drain my battery?',
                  'Mesh syncing uses Bluetooth Low Energy (BLE) to find peers, which is very efficient. However, frequent Wi-Fi Direct transfers can impact battery life. You can adjust the "Sync Interval" in Settings (e.g., change from 15s to 5m) to save power. The app also respects Android\'s battery optimization settings.',
                ),
                _buildFAQ(
                  'What is a "Global Action"?',
                  'When an Official or Volunteer Resolves a hazard or Debunks a report, that "deletion" is broadcast to the whole network. Once you sync with someone, they will also see that hazard as removed. Local actions (like Blocking a user or Trusting a neighbor) only affect your personal device.',
                ),
                _buildFAQ(
                  'Is my data private?',
                  'Your reports are signed with a unique cryptographic key stored only on your device. While your name is shared with reports so others can verify authenticity, your exact location is only shared when you explicitly create a marker. The app does not track your background location for analytics or advertising.',
                ),
                _buildFAQ(
                  'Why do I need so many permissions?',
                  'Android requires Location and Nearby Devices permissions to use Bluetooth and Wi-Fi Direct. Floodio does not track you for advertising; it strictly uses these APIs to find other mesh nodes during emergencies. Background execution permissions are needed so the app can sync while in your pocket.',
                ),
                
                const SizedBox(height: 32),
                const Text(
                  'Troubleshooting',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildFAQ(
                  'My status says "OFFLINE" even with Auto-Sync on?',
                  'Ensure Bluetooth and Location are enabled. Android requires Location services to be ON for Bluetooth scanning to work. Also, check if you have granted the "Nearby Devices" permission in your phone\'s settings. Try toggling Auto-Sync off and on again.',
                ),
                _buildFAQ(
                  'Syncing is taking a long time or failing?',
                  'Wi-Fi Direct can sometimes be slow to negotiate depending on the Android device manufacturer. Try moving closer to the other device. If it consistently fails, try toggling Auto-Sync off and on again, or restart your phone\'s Wi-Fi. Ensure neither device is currently connected to a standard Wi-Fi network that requires a captive portal login.',
                ),
                _buildFAQ(
                  'I can\'t see offline maps?',
                  'Make sure you have downloaded a map region while connected to the internet, or received one from a peer. Check the "Map Storage" section in your Profile tab to see your downloaded regions. Ensure the "Layers" button on the map has offline regions toggled ON.',
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
      title = 'Official Command Node';
      subtitle = 'You have full administrative capabilities to broadcast critical alerts, manage volunteers, and bridge the mesh network to the cloud.';
      icon = Icons.security;
    } else if (isTier2) {
      bgColor = Colors.purple.shade50;
      textColor = Colors.purple.shade900;
      title = 'Verified Volunteer Node';
      subtitle = 'You are a trusted community leader. Your role is to verify crowdsourced reports, debunk misinformation, and help distribute offline maps.';
      icon = Icons.admin_panel_settings;
    } else {
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade900;
      title = 'Citizen Node';
      subtitle = 'You are a vital part of the mesh network. Report local hazards, trust reliable neighbors, and keep Auto-Sync on to relay information.';
      icon = Icons.people;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: textColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ]
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 42),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 20)),
                const SizedBox(height: 6),
                Text(subtitle, style: TextStyle(color: textColor, fontSize: 14, height: 1.4)),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bolt, color: Colors.yellow.shade800, size: 32),
                const SizedBox(width: 12),
                const Text(
                  'Quick Start Guide',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (isOfficial) ...[
              _buildStep(1, 'Enable Auto-Sync', 'Tap the status chip (top right) and toggle "Mesh Auto-Sync" ON to connect with nearby devices and build the local mesh.'),
              _buildStep(2, 'Broadcast Alerts', 'Tap the "+" button to send Official Alerts. Mark them as "Critical" for immediate evacuation notices. These appear in Blue (Tier 1).'),
              _buildStep(3, 'Promote Volunteers', 'Find reliable users in the feed and tap "Make Volunteer" to grant them verification powers. Manage them in the Command Tab.'),
              _buildStep(4, 'Cloud Gateway', 'When internet is available, go to the Command Tab and tap "Force Cloud Sync Now" to upload mesh data to the central database and download global updates.'),
            ] else if (isTier2) ...[
              _buildStep(1, 'Enable Auto-Sync', 'Tap the status chip (top right) and toggle "Mesh Auto-Sync" ON to relay data between citizens and officials.'),
              _buildStep(2, 'Verify Reports', 'Check Unverified (Grey) reports. If you physically confirm them, tap "Verify & Endorse" to upgrade them to Verified (Purple) for everyone.'),
              _buildStep(3, 'Debunk False Info', 'If a report is definitively false, tap "Debunk" to permanently remove it from the entire mesh network.'),
              _buildStep(4, 'Share Maps', 'Download offline maps (Map tab -> Download icon) and broadcast them via the Sync menu to users without internet.'),
            ] else ...[
              _buildStep(1, 'Enable Auto-Sync', 'Tap the status chip (top right) and toggle "Mesh Auto-Sync" ON. Your phone will act as a secure relay for emergency data.'),
              _buildStep(2, 'Download a Map', 'While you still have internet, tap the download icon on the Map tab to save your local area for offline use.'),
              _buildStep(3, 'Report Hazards', 'Tap the "+" button to mark floods, roadblocks, or safe zones. Your reports will spread automatically to nearby phones.'),
              _buildStep(4, 'Trust Reliable Users', 'Tap "Trust" on reports from people you know. Their future updates will be prioritized on your device (Green).'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyProtocolCard(BuildContext context, bool isOfficial, bool isTier2) {
    String text;
    if (isOfficial) {
      text = '1. Issue "Critical" alerts for immediate life-threatening situations. These bypass standard filters and alert users immediately.\n\n2. Use the Command Tab to force cloud syncs whenever a temporary internet connection is established to bridge the mesh with the outside world.\n\n3. Delegate trust to local community leaders (Make Volunteer) to scale verification efforts across disconnected zones.\n\n4. Broadcast offline maps to areas where cellular infrastructure has completely collapsed.';
    } else if (isTier2) {
      text = '1. Misinformation can be deadly during a crisis. Actively monitor the feed for Unverified (Grey) reports.\n\n2. If you physically verify a hazard, use "Verify & Endorse" to elevate its trust level.\n\n3. If you know a report is false or outdated, use "Debunk" to delete it globally and prevent panic.\n\n4. Keep your device charged and Auto-Sync enabled to act as a critical data bridge between neighborhoods.';
    } else {
      text = '1. If you see a hazard, report it immediately with a clear description and photo if possible. Accurate data saves lives.\n\n2. If you see a false report, tap "Block" to hide that user\'s posts locally.\n\n3. Conserve battery, but try to keep Auto-Sync enabled when moving between locations to carry data to others (acting as a "data mule").\n\n4. Follow instructions from Official (Blue) and Verified (Purple) reports.';
    }

    return Card(
      color: Colors.red.shade50,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.red.shade200, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.gavel, color: Colors.red.shade900, size: 28),
                const SizedBox(width: 12),
                Text(
                  'Emergency Protocol',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.red.shade900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              text,
              style: TextStyle(fontSize: 15, height: 1.5, color: Colors.red.shade900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int num, String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.blue.shade100,
            foregroundColor: Colors.blue.shade900,
            child: Text(num.toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(desc, style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideExpansionTile(BuildContext context, {required IconData icon, required String title, required String content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surface,
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text(
              content,
              style: TextStyle(color: Colors.grey.shade800, height: 1.5, fontSize: 14),
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
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: color, size: 28),
        title: Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 16),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text(desc, style: TextStyle(fontSize: 14, color: Colors.grey.shade800, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildFAQ(String question, String answer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
        color: Colors.grey.shade50,
      ),
      child: ExpansionTile(
        title: Text(
          question,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Text(
              answer,
              style: TextStyle(color: Colors.grey.shade800, height: 1.5, fontSize: 14),
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
      'content': 'Floodio is an offline-first disaster communication network. It keeps you connected when cell towers and internet fail.',
      'icon': '👋',
    },
    {
      'title': 'The Mesh Network',
      'content': 'By turning on "Mesh Auto-Sync", your phone will automatically find nearby users via Bluetooth and securely exchange emergency data over Wi-Fi Direct. You become a vital link in the chain.',
      'icon': '📡',
    },
    {
      'title': 'Trust & Verification',
      'content': 'To fight rumors, reports are color-coded:\n\n🔵 Official (Gov/NGO)\n🟣 Verified (Trusted Volunteers)\n🟢 Trusted (Your Contacts)\n⚪ Unverified (Public)',
      'icon': '🛡️',
    },
    {
      'title': 'Reporting Hazards',
      'content': 'Tap the "+" button to report floods, draw safe zones, or mark blocked roads. Add photos and descriptions to help your community navigate safely.',
      'icon': '📍',
    },
    {
      'title': 'Offline Maps',
      'content': 'Download maps while you have internet. If the network goes down, you can still navigate and even share your downloaded maps directly with other users offline.',
      'icon': '🗺️',
    },
    {
      'title': 'Share the App Offline',
      'content': 'If someone needs Floodio but has no internet, tap the Share icon in the top right to send them the app directly via Bluetooth or Nearby Share.',
      'icon': '📲',
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
              color: Colors.black.withValues(alpha: 0.90),
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
                      const SizedBox(height: 32),
                      Text(
                        _steps[_currentStep]['title']!,
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _steps[_currentStep]['content']!,
                        style: const TextStyle(color: Colors.white70, fontSize: 18, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 48),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_currentStep > 0)
                            OutlinedButton(
                              onPressed: () => setState(() => _currentStep--),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white, 
                                side: const BorderSide(color: Colors.white38, width: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Back', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          if (_currentStep > 0)
                            const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                if (_currentStep < _steps.length - 1) {
                                  setState(() => _currentStep++);
                                } else {
                                  _finish();
                                }
                              },
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: Text(
                                _currentStep < _steps.length - 1 ? 'Next' : 'Start Using Floodio',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _steps.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentStep == index ? Colors.blue : Colors.white24,
                            ),
                          ),
                        ),
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
