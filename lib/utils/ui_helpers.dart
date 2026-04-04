import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/tables.dart';

String getTrustTierName(int tier) {
  switch (tier) {
    case 1:
      return 'OFFICIAL';
    case 2:
      return 'VERIFIED';
    case 3:
      return 'TRUSTED';
    case 4:
      return 'UNVERIFIED';
    default:
      return 'Unknown';
  }
}

Color getTierColor(int tier) {
  switch (tier) {
    case 1:
      return Colors.blue.shade800;
    case 2:
      return Colors.purple.shade700;
    case 3:
      return Colors.green.shade700;
    default:
      return Colors.grey.shade600;
  }
}

Color getHazardColor(String type, int tier) {
  final lowerType = type.toLowerCase();
  if (lowerType == 'supply') return Colors.indigo;
  if (lowerType == 'medical triage') return Colors.pink;
  if (lowerType == 'custom') return Colors.deepOrange;

  return getTierColor(tier);
}

IconData getHazardIcon(String type) {
  switch (type.toLowerCase()) {
    case 'flood':
    case 'flooded area':
      return Icons.water;
    case 'fire':
    case 'fire zone':
      return Icons.local_fire_department;
    case 'roadblock':
      return Icons.remove_road;
    case 'medical':
    case 'medical triage':
      return Icons.medical_services;
    case 'evacuation zone':
      return Icons.directions_run;
    case 'safe zone':
      return Icons.health_and_safety;
    case 'supply':
      return Icons.local_shipping;
    case 'custom':
      return Icons.star;
    default:
      return Icons.warning;
  }
}

String formatTimestamp(int timestamp) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60 && diff.inSeconds >= 0) {
    return 'Just now';
  } else if (diff.inMinutes < 60 && diff.inMinutes >= 0) {
    return '${diff.inMinutes}m ago';
  } else if (diff.inHours < 24 && diff.inHours >= 0) {
    return '${diff.inHours}h ago';
  } else if (diff.inDays < 7 && diff.inDays >= 0) {
    return '${diff.inDays}d ago';
  } else {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

Widget buildTrustBadge(int tier) {
  final color = getTierColor(tier);
  final icon = tier == 1
      ? Icons.verified
      : tier == 2
      ? Icons.admin_panel_settings
      : tier == 3
      ? Icons.thumb_up
      : Icons.people;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          getTrustTierName(tier),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    ),
  );
}

UserProfileEntity? getProfile(
  String publicKey,
  List<UserProfileEntity> profiles,
) {
  try {
    return profiles.firstWhere((p) => p.publicKey == publicKey);
  } catch (_) {
    return null;
  }
}

Future<void> checkAndShowWifiWarning(BuildContext context, VoidCallback onProceed) async {
  final prefs = await SharedPreferences.getInstance();
  final hasSeen = prefs.getBool('has_seen_wifi_warning') ?? false;
  if (hasSeen) {
    onProceed();
    return;
  }

  if (!context.mounted) return;

  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Important Notice'),
        ],
      ),
      content: const Text(
        'Android will ask if you want to stay connected to a network without internet access.\n\n'
        'You MUST tap "Yes", "Keep", or "Always Connect" on that system prompt, otherwise the connection will be dropped and syncing will fail.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await prefs.setBool('has_seen_wifi_warning', true);
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            onProceed();
          },
          child: const Text('I Understand'),
        ),
      ],
    ),
  );
}
