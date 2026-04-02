import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import '../providers/database_provider.dart';
import '../providers/hero_stats_provider.dart';
import '../providers/local_user_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/ui_p2p_provider.dart';
import '../screens/initializer_screen.dart';
import '../services/cloud_sync_service.dart';
import '../services/map_cache_service.dart';

Future<void> clearAllAppData(BuildContext context, WidgetRef ref) async {
  // Stop P2P services
  ref.read(uiP2pServiceProvider.notifier).stopHosting();
  ref.read(uiP2pServiceProvider.notifier).stopScanning();
  ref.read(uiP2pServiceProvider.notifier).disconnect();

  // Clear Database
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

  // Clear Files (Images and Maps)
  final dir = await getApplicationDocumentsDirectory();
  if (await dir.exists()) {
    final entities = dir.listSync();
    for (final entity in entities) {
      if (entity is File) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('img_') || name.endsWith('.fmap')) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }
  }

  // Clear Map Cache
  await ref.read(mapCacheServiceProvider).clearCache();
  await ref.read(offlineRegionsProvider.notifier).clearRegions();

  // Clear SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  // Notify Background Service
  try {
    FlutterBackgroundService().invoke('reloadSettings');
    FlutterBackgroundService().invoke('reloadOfflineRegions');
    FlutterBackgroundService().invoke('reloadHeroStats');
  } catch (_) {}

  // Invalidate Providers
  ref.invalidate(localUserControllerProvider);
  ref.invalidate(appSettingsProvider);
  ref.invalidate(cryptoServiceProvider);
  ref.invalidate(cloudSyncServiceProvider);
  ref.invalidate(heroStatsControllerProvider);

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
}
