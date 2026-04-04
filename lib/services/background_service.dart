import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void terminalLog(String message) {
  print(message);
  if (isBackgroundIsolate) {
    bgServiceInstance?.invoke('terminalLog', {'log': message});
  } else {
    try {
      FlutterBackgroundService().invoke('terminalLog', {'log': message});
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
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  service.on('toggleAutoSync').listen((event) {
    p2pNotifier.toggleAutoSync();
  });

  service.on('startHosting').listen((event) {
    p2pNotifier.startHosting();
  });

  service.on('stopHosting').listen((event) {
    p2pNotifier.stopHosting();
  });

  service.on('startScanning').listen((event) {
    p2pNotifier.startScanning();
  });

  service.on('stopScanning').listen((event) {
    p2pNotifier.stopScanning();
  });

  service.on('disconnect').listen((event) {
    p2pNotifier.disconnect();
  });

  service.on('connectToDevice').listen((event) {
    if (event != null && event['deviceAddress'] != null) {
      p2pNotifier.connectToDeviceByAddress(event['deviceAddress']);
    }
  });

  service.on('requestMapRegion').listen((event) {
    if (event != null) {
      p2pNotifier.requestMapRegion(
        OfflineRegion.fromJson(Map<String, dynamic>.from(event)),
      );
    }
  });

  service.on('broadcastMapRegion').listen((event) {
    OfflineRegion? region;
    if (event != null && event['region'] != null) {
      region = OfflineRegion.fromJson(
        Map<String, dynamic>.from(event['region']),
      );
    }
    p2pNotifier.broadcastMapRegion(region);
  });

  service.on('triggerSync').listen((event) {
    p2pNotifier.triggerSync();
  });

  service.on('broadcastText').listen((event) {
    if (event != null && event['text'] != null) {
      p2pNotifier.broadcastText(event['text']);
    }
  });

  service.on('broadcastFile').listen((event) {
    if (event != null && event['filePath'] != null) {
      p2pNotifier.broadcastFile(File(event['filePath']));
    }
  });

  service.on('processPayload').listen((event) {
    if (event != null && event['data'] != null) {
      p2pNotifier.processPayload(event['data']);
    }
  });

  service.on('processPayloadFromFile').listen((event) {
    if (event != null && event['filePath'] != null) {
      p2pNotifier.processPayloadFromFile(event['filePath']);
    }
  });

  service.on('mockDiscoveredDevice').listen((_) {
    p2pNotifier.mockDiscoveredDevice();
  });

  service.on('mockConnectedClient').listen((_) {
    p2pNotifier.mockConnectedClient();
  });

  service.on('mockReceivedHazard').listen((_) {
    p2pNotifier.mockReceivedHazard();
  });

  service.on('mockReceivedCriticalHazard').listen((_) {
    p2pNotifier.mockReceivedCriticalHazard();
  });

  service.on('mockHostState').listen((_) {
    p2pNotifier.mockHostState();
  });

  service.on('mockClientState').listen((_) {
    p2pNotifier.mockClientState();
  });

  service.on('mockSyncProgress').listen((_) {
    p2pNotifier.mockSyncProgress();
  });

  bool isMapDownloadCancelled = false;
  int mapDownloadTotal = 0;
  int mapDownloadDownloaded = 0;
  bool isMapDownloading = false;

  service.on('requestMapDownloadState').listen((_) {
    service.invoke('mapDownloadProgress', {
      'total': mapDownloadTotal,
      'downloaded': mapDownloadDownloaded,
      'isDownloading': isMapDownloading,
    });
  });

  service.on('startMapDownload').listen((event) async {
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

    service.invoke('mapDownloadProgress', {
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
      service.invoke('mapDownloadProgress', {
        'total': mapDownloadTotal,
        'downloaded': mapDownloadDownloaded,
        'isDownloading': isMapDownloading,
      });

      if (service is AndroidServiceInstance) {
        int currentProgress = (mapDownloadDownloaded * 100) ~/ mapDownloadTotal;
        if (currentProgress > lastReportedProgress) {
          lastReportedProgress = currentProgress;
          final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
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
    service.invoke('mapDownloadProgress', {
      'total': mapDownloadTotal,
      'downloaded': mapDownloadDownloaded,
      'isDownloading': isMapDownloading,
    });
  });

  service.on('cancelMapDownload').listen((_) {
    isMapDownloadCancelled = true;
    if (bgServiceInstance is AndroidServiceInstance) {
      FlutterLocalNotificationsPlugin().cancel(id: 778);
    }
  });

  service.on('reloadSettings').listen((_) async {
    await prefs.reload();
    container.invalidate(appSettingsProvider);
  });

  service.on('reloadOfflineRegions').listen((_) async {
    await prefs.reload();
    container.invalidate(offlineRegionsProvider);
  });

  service.on('requestState').listen((event) {
    final state = container.read(p2pServiceProvider);
    service.invoke('p2pStateUpdate', state.toMap());
  });

  DateTime lastStateUpdateTime = DateTime.now();
  Timer? stateUpdateTimer;

  container.listen(p2pServiceProvider, (previous, next) {
    final now = DateTime.now();
    
    // Only send updates across the isolate boundary if 500ms have passed to prevent UI jank,
    // OR if a significant state change occurred (e.g., connection status changed, sync finished).
    final isSignificantChange = previous == null || 
        previous.isHosting != next.isHosting ||
        previous.isScanning != next.isScanning ||
        previous.isSyncing != next.isSyncing ||
        previous.isConnecting != next.isConnecting ||
        previous.hostState?.isActive != next.hostState?.isActive ||
        previous.clientState?.isActive != next.clientState?.isActive ||
        previous.connectedClients.length != next.connectedClients.length;

    if (isSignificantChange || now.difference(lastStateUpdateTime).inMilliseconds > 500) {
      stateUpdateTimer?.cancel();
      lastStateUpdateTime = now;
      service.invoke('p2pStateUpdate', next.toMap());
      _updateNotification(service, next);
    } else {
      stateUpdateTimer?.cancel();
      stateUpdateTimer = Timer(const Duration(milliseconds: 500), () {
        lastStateUpdateTime = DateTime.now();
        service.invoke('p2pStateUpdate', next.toMap());
        _updateNotification(service, next);
      });
    }
  });

  container.listen(cloudSyncServiceProvider, (previous, next) async {
    if (service is AndroidServiceInstance) {
      if (next.isSyncing) {
        try {
          if (await service.isForegroundService()) {
            final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
            
            bool showProgress = next.syncProgress != null;
            int progress = (showProgress ? (next.syncProgress! * 100).toInt() : 0);
            
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
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
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
