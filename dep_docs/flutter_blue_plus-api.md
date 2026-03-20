# Context Document: `flutter_blue_plus`

## 1. Package Overview & Directives
* **Purpose:** Bluetooth Low Energy (BLE) Central Role plugin for Flutter.
* **Supported Platforms:** Android, iOS, macOS, Linux, Web.
* **Not Supported:** Bluetooth Classic (e.g., older audio devices, HC-05), Peripheral Role, iBeacons on iOS.
* **CRITICAL RULES:**
  1. **NO INSTANCE:** `FlutterBluePlus` is a static class. **NEVER** generate `FlutterBluePlus.instance`. Use `FlutterBluePlus.methodName()`.
  2. **LICENSE REQUIRED:** As of v2.0.0, `device.connect()` requires a `License` enum argument (e.g., `license: License.free`).
  3. **NAMING CONVENTIONS:** Use `remoteId` (not `id`), `platformName` (not `name`), `adapterState` (not `state`), and `lastValueStream` (not `value`).
  4. **ERROR HANDLING:** Wrap all BLE operations (`read`, `write`, `connect`, `discoverServices`) in `try/catch` blocks. The package throws `FlutterBluePlusException`.
  5. **DISCOVER SERVICES:** You **MUST** call `device.discoverServices()` after every successful connection before interacting with characteristics.

---

## 2. Setup & Permissions

### Android (`android/app/build.gradle` & `AndroidManifest.xml`)
* **minSdkVersion:** Must be `21` or higher.
* **Permissions:**
  ```xml
  <uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
  <!-- Android 12+ -->
  <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
  <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  <!-- Android 11 or lower -->
  <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
  <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>
  ```

### iOS (`ios/Runner/Info.plist`)
* **Permissions:**
  ```xml
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>This app needs Bluetooth to function</string>
  ```

---

## 3. Core Workflows (Code Generation Templates)

### 3.1. Check Adapter State
```dart
// Wait for Bluetooth to be turned on
await FlutterBluePlus.adapterState.where((s) => s == BluetoothAdapterState.on).first;

// Listen to state changes
final subscription = FlutterBluePlus.adapterState.listen((state) {
  if (state == BluetoothAdapterState.on) {
    // Bluetooth is on
  }
});
```

### 3.2. Scanning for Devices
```dart
// Listen to scan results
final subscription = FlutterBluePlus.onScanResults.listen((results) {
  for (ScanResult r in results) {
    print('${r.device.remoteId}: "${r.device.platformName}" - RSSI: ${r.rssi}');
  }
}, onError: (e) => print(e));

// Cancel subscription when scan completes
FlutterBluePlus.cancelWhenScanComplete(subscription);

// Start scanning
await FlutterBluePlus.startScan(
  withServices: [Guid("180D")], // Optional filter
  timeout: const Duration(seconds: 15),
);

// Wait for scan to finish
await FlutterBluePlus.isScanning.where((val) => val == false).first;
```

### 3.3. Connecting & Discovering Services
```dart
// Listen to connection state
final subscription = device.connectionState.listen((state) async {
  if (state == BluetoothConnectionState.disconnected) {
    print("Disconnected: ${device.disconnectReason}");
  }
});

// Automatically clean up the subscription on disconnect
device.cancelWhenDisconnected(subscription, delayed: true, next: true);

try {
  // Connect (Requires License enum)
  await device.connect(license: License.free, timeout: const Duration(seconds: 35));
  
  // MUST discover services after connecting
  List<BluetoothService> services = await device.discoverServices();
} catch (e) {
  print("Connection failed: $e");
}
```

### 3.4. Reading, Writing, and Subscribing
```dart
// Find target characteristic
BluetoothCharacteristic? targetChar;
for (var service in services) {
  for (var char in service.characteristics) {
    if (char.uuid == Guid("YOUR_CHAR_UUID")) targetChar = char;
  }
}

if (targetChar != null) {
  // READ
  if (targetChar.properties.read) {
    List<int> value = await targetChar.read();
  }

  // WRITE
  if (targetChar.properties.write || targetChar.properties.writeWithoutResponse) {
    await targetChar.write([0x01, 0x02], withoutResponse: targetChar.properties.writeWithoutResponse);
  }

  // SUBSCRIBE (Notify/Indicate)
  if (targetChar.properties.notify || targetChar.properties.indicate) {
    final sub = targetChar.lastValueStream.listen((value) {
      print("New value: $value");
    });
    device.cancelWhenDisconnected(sub);
    
    await targetChar.setNotifyValue(true);
  }
}
```

---

## 4. API Reference

### `FlutterBluePlus` (Static Methods)
* `adapterState` (Stream<BluetoothAdapterState>): Current state of the Bluetooth adapter.
* `adapterStateNow` (BluetoothAdapterState): Synchronous getter for adapter state.
* `isSupported` (Future<bool>): Checks if hardware supports BLE.
* `turnOn()` (Future<void>): Prompts user to turn on Bluetooth (Android only).
* `startScan({List<Guid> withServices, Duration timeout, ...})` (Future<void>): Starts scanning.
* `stopScan()` (Future<void>): Stops scanning.
* `onScanResults` (Stream<List<ScanResult>>): Stream of scan results (cleared between scans).
* `scanResults` (Stream<List<ScanResult>>): Stream of scan results (re-emits previous results).
* `isScanning` (Stream<bool>): Stream indicating if a scan is active.
* `connectedDevices` (List<BluetoothDevice>): Devices currently connected to *this app*.
* `systemDevices(List<Guid> withServices)` (Future<List<BluetoothDevice>>): Devices connected to the OS by *any* app.
* `events` (BluetoothEvents): Global event bus for all BLE events.

### `BluetoothDevice`
* **Properties:**
  * `remoteId` (DeviceIdentifier): MAC address on Android, UUID on iOS/macOS.
  * `platformName` (String): OS-cached name of the device.
  * `advName` (String): Name found in the advertisement packet during scanning.
* **Methods:**
  * `connect({required License license, Duration timeout, bool autoConnect, int? mtu})` (Future<void>): Connects to the device.
  * `disconnect()` (Future<void>): Disconnects.
  * `discoverServices()` (Future<List<BluetoothService>>): Discovers GATT services.
  * `requestMtu(int desiredMtu)` (Future<int>): Requests MTU change (Android only).
  * `readRssi()` (Future<int>): Reads current RSSI.
  * `cancelWhenDisconnected(StreamSubscription sub)`: Utility to prevent memory leaks.
* **Streams:**
  * `connectionState` (Stream<BluetoothConnectionState>)
  * `mtu` (Stream<int>)
  * `onServicesReset` (Stream<void>): Emits when services change (0x2A05). Must re-call `discoverServices()`.

### `BluetoothService`
* `uuid` (Guid): Service UUID.
* `characteristics` (List<BluetoothCharacteristic>): List of characteristics.
* `includedServices` (List<BluetoothService>): Secondary services.

### `BluetoothCharacteristic`
* **Properties:**
  * `uuid` (Guid): Characteristic UUID.
  * `properties` (CharacteristicProperties): Booleans for `read`, `write`, `notify`, `indicate`, etc.
  * `isNotifying` (bool): True if currently subscribed.
* **Methods:**
  * `read()` (Future<List<int>>): Reads value.
  * `write(List<int> value, {bool withoutResponse, bool allowLongWrite})` (Future<void>): Writes value.
  * `setNotifyValue(bool notify)` (Future<bool>): Enables/disables notifications.
* **Streams:**
  * `lastValueStream` (Stream<List<int>>): Emits on read, write, and notify. Re-emits last value on listen.
  * `onValueReceived` (Stream<List<int>>): Emits on read and notify (matches iOS behavior).

### `ScanResult`
* `device` (BluetoothDevice): The discovered device.
* `advertisementData` (AdvertisementData): Contains `advName`, `txPowerLevel`, `manufacturerData`, `serviceUuids`, `serviceData`.
* `rssi` (int): Signal strength.

---

## 5. Migration & Deprecation Dictionary (Guardrails)

If asked to update old `flutter_blue` code, apply these transformations:

| Old `flutter_blue` API | New `flutter_blue_plus` API |
| :--- | :--- |
| `FlutterBlue.instance.X` | `FlutterBluePlus.X` (Static) |
| `device.id` | `device.remoteId` |
| `device.name` | `device.platformName` |
| `device.state` | `device.connectionState` |
| `FlutterBlue.instance.state` | `FlutterBluePlus.adapterState` |
| `characteristic.value` | `characteristic.lastValueStream` |
| `descriptor.value` | `descriptor.lastValueStream` |
| `characteristic.onValueChangedStream` | `characteristic.onValueReceived` |
| `scan()` | `startScan(oneByOne: true)` |
| `connectedDevices` (Old behavior) | `systemDevices` |

---

## 6. Advanced / Edge Cases

1. **MTU Negotiation:**
   * Android: FBP requests MTU 512 by default during `connect()`.
   * iOS: MTU is negotiated automatically by the OS.
   * To get current MTU: `device.mtuNow`.
2. **Long Writes:**
   * Use `allowLongWrite: true` in `characteristic.write()` to write up to 512 bytes regardless of MTU (requires `withoutResponse: false`).
3. **Concurrency:**
   * FBP uses internal Mutexes. Only **one** BLE operation (read/write/connect) can be in-flight at a time globally.
4. **Android Bonding:**
   * `device.createBond()` and `device.removeBond()` are available.
   * `device.bondState` stream tracks bonding status.
5. **Global Events API:**
   * `FlutterBluePlus.events` provides global streams for all devices (e.g., `FlutterBluePlus.events.onCharacteristicReceived`). Useful for state management architectures (Bloc/Riverpod) to listen to BLE events without passing `BluetoothDevice` instances everywhere.