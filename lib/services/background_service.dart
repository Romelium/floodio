import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/connection.dart';
import '../database/database.dart';
import '../providers/database_provider.dart';
import '../providers/p2p_provider.dart';
import '../providers/offline_regions_provider.dart';
import '../providers/settings_provider.dart';

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
    'floodio_bg_service',
    'Floodio Background Sync',
    description: 'This channel is used for background P2P syncing.',
    importance: Importance.low,
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

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'floodio_bg_service',
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

  container.listen(p2pServiceProvider, (previous, next) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
            FlutterLocalNotificationsPlugin();

        flutterLocalNotificationsPlugin.show(
          id: 888,
          title: 'Floodio Sync Active',
          body: next.syncMessage ?? 'Running in background',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'floodio_bg_service',
              'Floodio Background Sync',
              icon: 'ic_bg_service_small',
              ongoing: true,
            ),
          ),
        );
      }
    }

    service.invoke('p2pStateUpdate', next.toMap());
  });
}
