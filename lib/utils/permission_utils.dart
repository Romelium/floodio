import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestAppPermissions() async {
  if (!Platform.isAndroid) return true;

  final androidInfo = await DeviceInfoPlugin().androidInfo;
  final sdkInt = androidInfo.version.sdkInt;

  List<Permission> permissions = [
    Permission.location,
  ];

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

  List<Permission> permissions = [
    Permission.location,
  ];

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
