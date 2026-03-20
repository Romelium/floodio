# `flutter_ble_peripheral` API & Usage Documentation

## 1. Overview
`flutter_ble_peripheral` is a Flutter plugin that allows a device to act as a Bluetooth Low Energy (BLE) Peripheral. It enables the device to advertise custom services, characteristics, and manufacturer data to central devices.

*   **Version:** 2.1.0
*   **Supported Platforms:** Android, iOS, macOS, Windows
*   **Architecture:** Singleton pattern (`FlutterBlePeripheral()`)

---

## 2. Platform Setup & Permissions

### Android (`AndroidManifest.xml`)
The plugin handles API level differences automatically, but the following permissions must be declared:
```xml
<!-- API 18 - 30 -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission-sdk-23 android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="30" />
<uses-permission-sdk-23 android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />

<!-- API 31+ -->
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
```

### Windows
*   Requires **Location Services** to be enabled.
*   **Nearby Sharing** can interfere with BLE advertising. The plugin provides methods to check and open settings for this.

### iOS / macOS
*   Requires `NSBluetoothAlwaysUsageDescription` in `Info.plist` (Standard Apple BLE requirement).
*   Permissions are requested implicitly when the peripheral manager initializes.

---

## 3. Core API Reference (`FlutterBlePeripheral`)

Access the singleton instance via `FlutterBlePeripheral()`.

### State & Capability Checks
| Method | Returns | Description |
| :--- | :--- | :--- |
| `isSupported` | `Future<bool>` | Returns `true` if BLE advertising is supported by the hardware. |
| `isBluetoothOn` | `Future<bool>` | Returns `true` if the Bluetooth radio is currently powered on. |
| `isAdvertising` | `Future<bool>` | Returns `true` if the device is currently broadcasting. |
| `isConnected` | `Future<bool>` | Returns `true` if a central device is connected to this peripheral. |

### Permissions & Settings
| Method | Returns | Description |
| :--- | :--- | :--- |
| `hasPermission()` | `Future<BluetoothPeripheralState>` | Checks current BLE permission status. |
| `requestPermission()` | `Future<BluetoothPeripheralState>` | Prompts the user for BLE/Location permissions. |
| `enableBluetooth({bool askUser})` | `Future<bool>` | Prompts to turn on Bluetooth (Android/Windows). Returns `false` on Apple. |
| `openBluetoothSettings()` | `Future<void>` | Opens OS Bluetooth settings. |
| `openAppSettings()` | `Future<void>` | Opens OS App settings (useful if permanently denied). |
| `openLocationSettings()` | `Future<void>` | Opens OS Location settings (Windows). |
| `isNearbyShareEnabled()` | `Future<bool>` | Checks if Nearby Share is active (Windows only). |
| `openNearbyShareSettings()`| `Future<void>` | Opens Nearby Share settings (Windows only). |

### Advertising Actions
| Method | Returns | Description |
| :--- | :--- | :--- |
| `start({required AdvertiseData advertiseData, ...})` | `Future<BluetoothPeripheralState>` | Starts BLE advertising. Accepts optional Android-specific settings. |
| `stop()` | `Future<BluetoothPeripheralState>` | Stops BLE advertising. |
| `sendData(Uint8List data)` | `Future<void>` | Sends data to connected central (Implementation varies by platform). |

### Streams (Event Channels)
| Property | Type | Description |
| :--- | :--- | :--- |
| `onPeripheralStateChanged` | `Stream<PeripheralState>` | Listen to real-time BLE state changes (e.g., `idle`, `advertising`, `poweredOff`). |
| `onMtuChanged` | `Stream<int>` | Listen to MTU size changes. |

---

## 4. Data Models

### `AdvertiseData`
The primary payload for BLE advertising. 
*Note: iOS heavily restricts advertising data. Only `serviceUuids` and `localName` are reliably supported on Apple platforms.*

```dart
AdvertiseData({
  List<String>? serviceUuids,      // iOS & Android: UUIDs to advertise
  String? localName,               // iOS & Android: Device name (max 10 bytes on iOS)
  int? manufacturerId,             // Android only: SIG assigned company ID
  Uint8List? manufacturerData,     // Android only: Custom hex data
  String? serviceDataUuid,         // Android only
  List<int>? serviceData,          // Android only
  bool includeDeviceName = false,  // Android only
  bool includePowerLevel = false,  // Android only
  String? serviceSolicitationUuid, // Android 12+ only
})
```

### `AdvertiseSettings` (Android Only - Legacy API)
```dart
AdvertiseSettings({
  bool advertiseSet = true, // Set to true to use Android 8.0+ AdvertisingSet API
  AdvertiseMode advertiseMode = AdvertiseMode.advertiseModeLowLatency,
  AdvertiseTxPower txPowerLevel = AdvertiseTxPower.advertiseTxPowerLow,
  bool connectable = false,
  int timeout = 400, // Max 180000 ms
})
```

### `AdvertiseSetParameters` (Android 8.0+ Only)
Used when `advertiseSet` is true. Allows extended advertising features.
```dart
AdvertiseSetParameters({
  bool connectable = false,
  int txPowerLevel = txPowerHigh,
  int interval = intervalHigh,
  bool legacyMode = false,
  bool includeTxPowerLevel = false,
  // ... primaryPhy, secondaryPhy, anonymous, duration, maxExtendedAdvertisingEvents
})
```

---

## 5. Enums

### `PeripheralState` (Active BLE Status)
Used by `onPeripheralStateChanged` stream.
*   `unknown`, `unsupported`, `unauthorized`, `poweredOff`, `idle` (ready), `advertising`, `connected`.

### `BluetoothPeripheralState` (Permission/Hardware Status)
Returned by permission and start/stop methods.
*   `granted`, `denied`, `permanentlyDenied`, `restricted` (iOS), `limited` (iOS), `turnedOff`, `unsupported`, `unknown`, `ready`.

---

## 6. Usage Guide & Code Examples

### Step 1: Initialization & Permission Checks
Always check if the device supports BLE and if permissions are granted before starting.

```dart
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

final blePeripheral = FlutterBlePeripheral();

Future<void> initBle() async {
  // 1. Check if supported
  final isSupported = await blePeripheral.isSupported;
  if (!isSupported) return;

  // 2. Check/Request Permissions
  var permission = await blePeripheral.hasPermission();
  if (permission != BluetoothPeripheralState.granted) {
    permission = await blePeripheral.requestPermission();
  }
  
  if (permission == BluetoothPeripheralState.permanentlyDenied) {
    await blePeripheral.openAppSettings();
    return;
  }

  // 3. Check if Bluetooth is ON
  final isBluetoothOn = await blePeripheral.isBluetoothOn;
  if (!isBluetoothOn) {
    await blePeripheral.enableBluetooth(); // Prompts user on Android/Windows
  }
}
```

### Step 2: Start Advertising
Define your payload and start broadcasting.

```dart
Future<void> startBroadcasting() async {
  final advertiseData = AdvertiseData(
    serviceUuids: ['bf27730d-860a-4e09-889c-2d8b6a9e0fe7'],
    localName: 'MyBLEDevice',
    manufacturerId: 1234,
    manufacturerData: Uint8List.fromList([0x01, 0x02, 0x03]),
  );

  // Optional: Android specific settings
  final advertiseSettings = AdvertiseSettings(
    advertiseMode: AdvertiseMode.advertiseModeLowLatency,
    txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
    connectable: true,
  );

  await blePeripheral.start(
    advertiseData: advertiseData,
    advertiseSettings: advertiseSettings,
  );
}
```

### Step 3: Listen to State Changes (UI Updates)
Use a `StreamBuilder` to react to the peripheral's state.

```dart
StreamBuilder<PeripheralState>(
  stream: FlutterBlePeripheral().onPeripheralStateChanged,
  initialData: PeripheralState.unknown,
  builder: (context, snapshot) {
    final state = snapshot.data;
    
    if (state == PeripheralState.advertising) {
      return Text('Currently Broadcasting!');
    } else if (state == PeripheralState.connected) {
      return Text('Device Connected!');
    } else if (state == PeripheralState.poweredOff) {
      return Text('Please turn on Bluetooth');
    }
    
    return Text('Ready to broadcast');
  },
)
```

### Step 4: Stop Advertising
```dart
Future<void> stopBroadcasting() async {
  await blePeripheral.stop();
}
```

---

## 7. Developer Notes & Gotchas

1.  **Apple Limitations:** iOS/macOS strictly limits background advertising and custom data. `manufacturerData` will be ignored on Apple devices. Rely on `serviceUuids` and `localName`.
2.  **Windows Nearby Share:** On Windows, if Nearby Share is enabled, it hogs the Bluetooth radio, causing BLE advertising to fail silently or throw a `ResourceInUse` error. Always check `isNearbyShareEnabled()` on Windows and prompt the user to disable it via `openNearbyShareSettings()`.
3.  **Android `advertiseSet`:** By default, `AdvertiseSettings.advertiseSet` is `true`. This uses the modern Android 8.0+ `AdvertisingSet` API. If supporting older Android devices, ensure graceful fallbacks or set it to `false`.
4.  **State vs Permission Enums:** Do not confuse `PeripheralState` (the real-time operational state of the radio, used in streams) with `BluetoothPeripheralState` (the result of permission requests and method calls).