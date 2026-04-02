import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

Future<bool> requestAppPermissions() async {
  if (!Platform.isAndroid) return true;

  final androidInfo = await DeviceInfoPlugin().androidInfo;
  final sdkInt = androidInfo.version.sdkInt;

  List<Permission> permissions = [Permission.location];

  if (sdkInt >= 31) {
    permissions.addAll([
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ]);
  } else {
    permissions.add(Permission.bluetooth);
  }

  if (sdkInt >= 33) {
    permissions.add(Permission.nearbyWifiDevices);
    permissions.add(Permission.notification);
  } else {
    permissions.add(Permission.storage);
  }

  Map<Permission, PermissionStatus> statuses = await permissions.request();

  bool allGranted = true;
  for (final status in statuses.values) {
    if (!status.isGranted && !status.isLimited) {
      allGranted = false;
    }
  }

  return allGranted;
}

Future<bool> checkAppPermissions() async {
  if (!Platform.isAndroid) return true;

  final androidInfo = await DeviceInfoPlugin().androidInfo;
  final sdkInt = androidInfo.version.sdkInt;

  List<Permission> permissions = [Permission.location];

  if (sdkInt >= 31) {
    permissions.addAll([
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ]);
  } else {
    permissions.add(Permission.bluetooth);
  }

  if (sdkInt >= 33) {
    permissions.add(Permission.nearbyWifiDevices);
    permissions.add(Permission.notification);
  } else {
    permissions.add(Permission.storage);
  }

  bool allGranted = true;
  for (final permission in permissions) {
    final status = await permission.status;
    if (!status.isGranted && !status.isLimited) {
      allGranted = false;
      break;
    }
  }

  return allGranted;
}

Future<bool> checkLocationServices() async {
  if (!Platform.isAndroid) return true;
  return await Permission.location.serviceStatus.isEnabled;
}

Future<void> requestBatteryOptimizationExemption() async {
  if (!Platform.isAndroid) return;
  if (!await Permission.ignoreBatteryOptimizations.isGranted) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

Future<bool> ensureServicesEnabled({bool isHosting = false}) async {
  if (!Platform.isAndroid) return true;
  final dummy = FlutterP2pHost();
  bool loc = await dummy.checkLocationEnabled();
  if (!loc) {
    try {
      await dummy.enableLocationServices();
    } catch (_) {}
    loc = await dummy.checkLocationEnabled();
  }

  bool wifi = true;
  if (!isHosting) {
    wifi = await dummy.checkWifiEnabled();
    if (!wifi) {
      try {
        await dummy.enableWifiServices();
      } catch (_) {}
      wifi = await dummy.checkWifiEnabled();
    }
  }
  bool bt = await dummy.checkBluetoothEnabled();
  if (!bt) {
    try {
      await dummy.enableBluetoothServices();
    } catch (_) {}
    bt = await dummy.checkBluetoothEnabled();
  }
  return loc && wifi && bt;
}
