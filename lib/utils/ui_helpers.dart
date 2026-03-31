import 'package:flutter/material.dart';
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
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
