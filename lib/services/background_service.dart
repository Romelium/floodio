import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:floodio/providers/hero_stats_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/connection.dart';
import '../database/database.dart';
import '../providers/critical_alert_provider.dart';
import '../providers/database_provider.dart';
import '../providers/map_downloader_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../providers/p2p_provider.dart';
import '../providers/settings_provider.dart';
import '../services/cloud_sync_service.dart';
import '../services/map_cache_service.dart';
import '../utils/constants.dart';

bool isBackgroundIsolate = false;
ServiceInstance? bgServiceInstance;

final StreamController<String?> notificationPayloadStream = StreamController<String?>.broadcast();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // Ignore for now, the main isolate will check getNotificationAppLaunchDetails()
}

void terminalLog(String message) {
  print(message);
  if (isBackgroundIsolate) {
    bgServiceInstance?.invoke(BgEvents.terminalLog, {'log': message});
  } else {
    try {
      FlutterBackgroundService().invoke(BgEvents.terminalLog, {'log': message});
    } catch (_) {}
  }
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    AppConstants.bgServiceChannel,
    'Floodio Background Sync',
    description: 'This channel is used for background P2P syncing.',
    importance: Importance.low,
  );

  const AndroidNotificationChannel criticalChannel = AndroidNotificationChannel(
    AppConstants.criticalAlertsChannel,
    'Critical Alerts',
    description: 'High priority emergency alerts',
    importance: Importance.max,
    enableLights: true,
    enableVibration: true,
    playSound: true,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_bg_service_small'),
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        notificationPayloadStream.add(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(criticalChannel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: AppConstants.bgServiceChannel,
      initialNotificationTitle: 'Floodio Sync',
      initialNotificationContent: 'Initializing background sync',
      foregroundServiceNotificationId: 888,
      foregroundServiceTypes: [
        AndroidForegroundType.connectedDevice,
        AndroidForegroundType.dataSync,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  terminalLog("[*] BackgroundService started in isolate.");
  isBackgroundIsolate = true;
  bgServiceInstance = service;
  DartPluginRegistrant.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://placeholder.supabase.co',
    ),
    anonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'placeholder',
    ),
  );

  final connection = await getSharedConnection();
  final db = AppDatabase(connection);
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWith((ref) {
        ref.onDispose(db.close);
        return db;
      }),
      sharedPreferencesProvider.overrideWith((ref) => prefs),
    ],
  );
  final p2pNotifier = container.read(p2pServiceProvider.notifier);

  if (service is AndroidServiceInstance) {
    service.on(BgEvents.setAsForeground).listen((event) {
      service.setAsForegroundService();
    });

    service.on(BgEvents.setAsBackground).listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on(BgEvents.stopService).listen((event) {
    service.stopSelf();
  });

  service.on(BgEvents.toggleAutoSync).listen((event) {
    p2pNotifier.toggleAutoSync();
  });

  service.on(BgEvents.startHosting).listen((event) {
    p2pNotifier.startHosting();
  });

  service.on(BgEvents.stopHosting).listen((event) {
    p2pNotifier.stopHosting();
  });

  service.on(BgEvents.startScanning).listen((event) {
    p2pNotifier.startScanning();
  });

  service.on(BgEvents.stopScanning).listen((event) {
    p2pNotifier.stopScanning();
  });

  service.on(BgEvents.disconnect).listen((event) {
    p2pNotifier.disconnect();
  });

  service.on(BgEvents.connectToDevice).listen((event) {
    if (event != null && event['deviceAddress'] != null) {
      p2pNotifier.connectToDeviceByAddress(event['deviceAddress']);
    }
  });

  service.on(BgEvents.requestMapRegion).listen((event) {
    if (event != null) {
      p2pNotifier.requestMapRegion(
        OfflineRegion.fromJson(Map<String, dynamic>.from(event)),
      );
    }
  });

  service.on(BgEvents.broadcastMapRegion).listen((event) {
    OfflineRegion? region;
    if (event != null && event['region'] != null) {
      region = OfflineRegion.fromJson(
        Map<String, dynamic>.from(event['region']),
      );
    }
    p2pNotifier.broadcastMapRegion(region);
  });

  service.on(BgEvents.triggerSync).listen((event) {
    p2pNotifier.triggerSync();
  });

  service.on(BgEvents.broadcastText).listen((event) {
    if (event != null && event['text'] != null) {
      p2pNotifier.broadcastText(event['text']);
    }
  });

  service.on(BgEvents.broadcastFile).listen((event) {
    if (event != null && event['filePath'] != null) {
      p2pNotifier.broadcastFile(File(event['filePath']));
    }
  });

  service.on(BgEvents.processPayload).listen((event) {
    if (event != null && event['data'] != null) {
      p2pNotifier.processPayload(event['data']);
    }
  });

  service.on(BgEvents.processPayloadFromFile).listen((event) {
    if (event != null && event['filePath'] != null) {
      p2pNotifier.processPayloadFromFile(event['filePath']);
    }
  });

  service.on(BgEvents.mockDiscoveredDevice).listen((_) {
    p2pNotifier.mockDiscoveredDevice();
  });

  service.on(BgEvents.mockConnectedClient).listen((_) {
    p2pNotifier.mockConnectedClient();
  });

  service.on(BgEvents.mockReceivedHazard).listen((_) {
    p2pNotifier.mockReceivedHazard();
  });

  service.on(BgEvents.mockReceivedCriticalHazard).listen((_) {
    p2pNotifier.mockReceivedCriticalHazard();
  });

  service.on(BgEvents.mockHostState).listen((_) {
    p2pNotifier.mockHostState();
  });

  service.on(BgEvents.mockClientState).listen((_) {
    p2pNotifier.mockClientState();
  });

  service.on(BgEvents.mockSyncProgress).listen((_) {
    p2pNotifier.mockSyncProgress();
  });

  bool isMapDownloadCancelled = false;
  int mapDownloadTotal = 0;
  int mapDownloadDownloaded = 0;
  bool isMapDownloading = false;

  service.on(BgEvents.requestMapDownloadState).listen((_) {
    service.invoke(BgEvents.mapDownloadProgress, {
      'total': mapDownloadTotal,
      'downloaded': mapDownloadDownloaded,
      'isDownloading': isMapDownloading,
    });
  });

  service.on(BgEvents.startMapDownload).listen((event) async {
    if (event == null || isMapDownloading) return;
    isMapDownloadCancelled = false;
    isMapDownloading = true;

    final bounds = LatLngBounds(
      LatLng(event['south'], event['west']),
      LatLng(event['north'], event['east']),
    );
    final minZoom = event['minZoom'] as int;
    final maxZoom = event['maxZoom'] as int;
    final urlTemplate = event['urlTemplate'] as String;

    final cacheService = container.read(mapCacheServiceProvider);

    List<MapTile> tilesToDownload = [];
    for (int z = minZoom; z <= maxZoom; z++) {
      final minX = lon2tilex(bounds.west, z);
      final maxX = lon2tilex(bounds.east, z);
      final minY = lat2tiley(bounds.north, z);
      final maxY = lat2tiley(bounds.south, z);

      for (int x = min(minX, maxX); x <= max(minX, maxX); x++) {
        for (int y = min(minY, maxY); y <= max(minY, maxY); y++) {
          tilesToDownload.add(MapTile(x, y, z));
        }
      }
    }

    mapDownloadTotal = tilesToDownload.length;
    mapDownloadDownloaded = 0;

    service.invoke(BgEvents.mapDownloadProgress, {
      'total': mapDownloadTotal,
      'downloaded': mapDownloadDownloaded,
      'isDownloading': isMapDownloading,
    });

    const batchSize = 20;
    int lastReportedProgress = -1;
    for (int i = 0; i < mapDownloadTotal; i += batchSize) {
      if (isMapDownloadCancelled) break;

      final batch = tilesToDownload.skip(i).take(batchSize);
      await Future.wait(
        batch.map(
          (tile) => cacheService.getTile(tile.z, tile.x, tile.y, urlTemplate),
        ),
      );

      mapDownloadDownloaded += batch.length;
      service.invoke(BgEvents.mapDownloadProgress, {
        'total': mapDownloadTotal,
        'downloaded': mapDownloadDownloaded,
        'isDownloading': isMapDownloading,
      });

      if (service is AndroidServiceInstance) {
        int currentProgress = (mapDownloadDownloaded * 100) ~/ mapDownloadTotal;
        if (currentProgress > lastReportedProgress) {
          lastReportedProgress = currentProgress;
          final FlutterLocalNotificationsPlugin
          flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
          flutterLocalNotificationsPlugin.show(
            id: 778,
            title: 'Downloading Offline Map',
            body: '$mapDownloadDownloaded / $mapDownloadTotal tiles',
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                AppConstants.bgServiceChannel,
                'Floodio Background Sync',
                icon: 'ic_bg_service_small',
                ongoing: true,
                onlyAlertOnce: true,
                showProgress: true,
                maxProgress: mapDownloadTotal,
                progress: mapDownloadDownloaded,
                indeterminate: false,
                color: const Color(0xFFE65100),
              ),
            ),
          );
        }
      }
    }

    if (service is AndroidServiceInstance) {
      FlutterLocalNotificationsPlugin().cancel(id: 778);
    }

    if (!isMapDownloadCancelled) {
      container
          .read(offlineRegionsProvider.notifier)
          .addRegion(
            OfflineRegion(bounds: bounds, minZoom: minZoom, maxZoom: maxZoom),
          );

      if (service is AndroidServiceInstance) {
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        flutterLocalNotificationsPlugin.show(
          id: 777,
          title: 'Map Download Complete',
          body: 'Offline map region has been saved.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              AppConstants.bgServiceChannel,
              'Floodio Background Sync',
              icon: 'ic_bg_service_small',
            ),
          ),
        );
      }
    }

    isMapDownloading = false;
    service.invoke(BgEvents.mapDownloadProgress, {
      'total': mapDownloadTotal,
      'downloaded': mapDownloadDownloaded,
      'isDownloading': isMapDownloading,
    });
  });

  service.on(BgEvents.cancelMapDownload).listen((_) {
    isMapDownloadCancelled = true;
    if (bgServiceInstance is AndroidServiceInstance) {
      FlutterLocalNotificationsPlugin().cancel(id: 778);
    }
  });

  service.on(BgEvents.reloadSettings).listen((_) async {
    await prefs.reload();
    container.invalidate(appSettingsProvider);
  });

  service.on(BgEvents.reloadOfflineRegions).listen((_) async {
    await prefs.reload();
    container.invalidate(offlineRegionsProvider);
  });

  service.on(BgEvents.reloadHeroStats).listen((_) async {
    await prefs.reload();
    container.invalidate(heroStatsControllerProvider);
  });

  service.on(BgEvents.requestState).listen((event) {
    final state = container.read(p2pServiceProvider);
    service.invoke(BgEvents.p2pStateUpdate, state.toMap());
  });

  DateTime lastStateUpdateTime = DateTime.now();
  Timer? stateUpdateTimer;

  container.listen(p2pServiceProvider, (previous, next) {
    final now = DateTime.now();

    // Only send updates across the isolate boundary if 500ms have passed to prevent UI jank,
    // OR if a significant state change occurred (e.g., connection status changed, sync finished).
    final isSignificantChange =
        previous == null ||
        previous.isHosting != next.isHosting ||
        previous.isScanning != next.isScanning ||
        previous.isSyncing != next.isSyncing ||
        previous.isConnecting != next.isConnecting ||
        previous.hostState?.isActive != next.hostState?.isActive ||
        previous.clientState?.isActive != next.clientState?.isActive ||
        previous.connectedClients.length != next.connectedClients.length;

    if (isSignificantChange ||
        now.difference(lastStateUpdateTime).inMilliseconds > 500) {
      stateUpdateTimer?.cancel();
      lastStateUpdateTime = now;
      service.invoke(BgEvents.p2pStateUpdate, next.toMap());
      _updateNotification(service, next);
    } else {
      stateUpdateTimer?.cancel();
      stateUpdateTimer = Timer(const Duration(milliseconds: 500), () {
        lastStateUpdateTime = DateTime.now();
        service.invoke(BgEvents.p2pStateUpdate, next.toMap());
        _updateNotification(service, next);
      });
    }
  });

  container.listen(cloudSyncServiceProvider, (previous, next) async {
    if (service is AndroidServiceInstance) {
      if (next.isSyncing) {
        try {
          if (await service.isForegroundService()) {
            final FlutterLocalNotificationsPlugin
            flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

            bool showProgress = next.syncProgress != null;
            int progress = (showProgress
                ? (next.syncProgress! * 100).toInt()
                : 0);

            flutterLocalNotificationsPlugin.show(
              id: 889,
              title: 'Cloud Gateway Sync',
              body: next.syncMessage ?? 'Syncing with cloud...',
              notificationDetails: NotificationDetails(
                android: AndroidNotificationDetails(
                  AppConstants.bgServiceChannel,
                  'Floodio Background Sync',
                  icon: 'ic_bg_service_small',
                  ongoing: true,
                  onlyAlertOnce: true,
                  showProgress: showProgress,
                  maxProgress: 100,
                  progress: progress,
                  indeterminate: !showProgress,
                  color: const Color(0xFF0D47A1),
                ),
              ),
            );
          }
        } catch (e) {
          print("Error updating cloud notification: $e");
        }
      } else if (previous?.isSyncing == true && !next.isSyncing) {
        FlutterLocalNotificationsPlugin().cancel(id: 889);
      }
    }
  });

  container.listen(redAlertControllerProvider, (previous, next) async {
    if (next.isActive &&
        (previous == null ||
            !previous.isActive ||
            (next.latestAlertTitle != previous.latestAlertTitle))) {
      final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
          FlutterLocalNotificationsPlugin();

      String? payload;
      if (next.latestAlertLat != null && next.latestAlertLng != null) {
        payload = '${next.latestAlertLat},${next.latestAlertLng}';
      }

      flutterLocalNotificationsPlugin.show(
        id: 999,
        title: 'CRITICAL EMERGENCY',
        body: next.latestAlertTitle ?? 'A critical alert has been issued.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.criticalAlertsChannel,
            'Critical Alerts',
            channelDescription: 'High priority emergency alerts',
            importance: Importance.max,
            priority: Priority.max,
            icon: 'ic_bg_service_small',
            color: Colors.red,
            enableLights: true,
            enableVibration: true,
            playSound: true,
            fullScreenIntent: true,
          ),
        ),
        payload: payload,
      );
    }
  });
}

void _updateNotification(ServiceInstance service, P2pState next) async {
  if (service is AndroidServiceInstance) {
    String title = 'Floodio Mesh';
    if (next.isHosting) {
      title = 'Broadcasting (${next.connectedClients.length} peers)';
    } else if (next.clientState?.isActive == true) {
      title = 'Connected to Mesh';
    } else if (next.isScanning) {
      title = 'Scanning for peers...';
    } else if (next.isAutoSyncing) {
      title = 'Auto-Sync Active';
    } else {
      title = 'Standby';
    }

    String body = next.syncMessage ?? 'Running in background';
    if (next.syncEstimatedSeconds != null) {
      body += ' (~${next.syncEstimatedSeconds}s left)';
    }

    bool showProgress = next.isSyncing && next.syncProgress != null;
    int progress = (showProgress ? (next.syncProgress! * 100).toInt() : 0);
    bool indeterminate = next.isSyncing && next.syncProgress == null;

    try {
      if (await service.isForegroundService()) {
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();
        flutterLocalNotificationsPlugin.show(
          id: 888,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              AppConstants.bgServiceChannel,
              'Floodio Background Sync',
              icon: 'ic_bg_service_small',
              ongoing: true,
              onlyAlertOnce: true,
              showProgress: showProgress || indeterminate,
              maxProgress: 100,
              progress: progress,
              indeterminate: indeterminate,
              color: const Color(0xFF0D47A1),
            ),
          ),
        );
      }
    } catch (e) {
      print("Error updating notification: $e");
    }
  }
}
