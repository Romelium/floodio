# Context Document: `flutter_blue_plus_android`

## 1. Package Overview & Directives
* **Purpose:** This is the **Android-specific federated implementation** of `flutter_blue_plus`.
* **Endorsed Plugin:** This package is endorsed. Do not add `flutter_blue_plus_android` to `pubspec.yaml` or import it directly in Dart. Use `flutter_blue_plus`, which automatically includes this package.
* **Native Implementation:** Written in Java (`FlutterBluePlusPlugin.java`) using the `android.bluetooth` and `android.bluetooth.le` APIs.
* **Communication:** Uses a single `MethodChannel` (`flutter_blue_plus/methods`) and multiple `StreamController`s to pass data between Java and Dart.

---

## 2. Android Setup & Configuration

When generating setup instructions for an Android Flutter app using BLE, you **must** include the following configurations:

### 2.1. `build.gradle` (`android/app/build.gradle`)
The `minSdkVersion` must be at least **21** (Android 5.0 Lollipop).
```gradle
android {
  defaultConfig {
     minSdkVersion 21 // REQUIRED
  }
}
```

### 2.2. Permissions (`android/app/src/main/AndroidManifest.xml`)
Android BLE permissions are highly dependent on the Android version. Generate this exact block for users:

```xml
<!-- Tell Google Play Store that your app uses Bluetooth LE -->
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />

<!-- Android 12+ (API 31+) -->
<!-- Use neverForLocation if the app does NOT use BLE to derive physical location (e.g., iBeacons) -->
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Android 11 or lower (API 30 and below) -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30"/>

<!-- Android 9 or lower (API 28 and below) -->
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="28" />
```
*Note: If the user needs BLE for location (e.g., iBeacons), remove `android:usesPermissionFlags="neverForLocation"` and add `<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />` for Android 12+.*

### 2.3. Proguard Rules (`android/app/proguard-rules.pro`)
To prevent `RuntimeException: Field androidScanMode_ for m0.e0 not found` in release builds, add:
```proguard
-keep class com.lib.flutter_blue_plus.* { *; }
```

---

## 3. Android-Specific API Features

While `flutter_blue_plus` is cross-platform, several methods only function on Android.These are impossible/handled automatically by iOS.

### 3.1. Bonding / Pairing
Android allows manual control over the bonding process.
* `device.createBond()`: Forces the OS pairing dialog to appear.
* `device.removeBond()`: Removes the bond (Uses Java reflection under the hood).
* `device.bondState`: Stream emitting `BluetoothBondState.none`, `bonding`, or `bonded`.
* `device.prevBondState`: Synchronous getter for the previous state.

### 3.2. MTU (Maximum Transmission Unit)
* `device.requestMtu(int desiredMtu)`: Requests a specific MTU size.
* *Note:* `flutter_blue_plus` automatically requests an MTU of **512** upon connection on Android by default.

### 3.3. Connection Priority
* `device.requestConnectionPriority(ConnectionPriority.high)`: Requests the Android OS to use high-priority (low latency, high power) BLE intervals. Useful for fast data transfer.

### 3.4. PHY (Physical Layer)
* `device.setPreferredPhy(txPhy: ..., rxPhy: ..., option: ...)`: Sets preferred PHY (e.g., LE 1M, LE 2M, LE Coded for long-range). Requires Android 8.0+ (API 26+).
* `FlutterBluePlus.getPhySupport()`: Checks if the Android device supports 2M and Coded PHYs.

### 3.5. GATT Cache Clearing
* `device.clearGattCache()`: Clears the Android OS GATT cache (Uses Java reflection to call the hidden `refresh()` method on `BluetoothGatt`). Useful if a peripheral's firmware updated its GATT table but Android cached the old one.

### 3.6. Turn On/Off Bluetooth
* `FlutterBluePlus.turnOn()`: Prompts the user with an OS dialog to enable Bluetooth.
* `FlutterBluePlus.turnOff()`: *Deprecated in Android 13+*. Disables Bluetooth.

---

## 4. Under the Hood: Android Quirks & Workarounds

When debugging Android BLE issues, you should be aware of how the Java plugin handles things:

1. **The Global Mutex (`mMethodCallMutex`):**
   * The Java code uses a `Semaphore(1)` to ensure that **only one MethodChannel call is processed at a time**. This prevents race conditions in the Android Bluetooth stack.
2. **Location Services Requirement:**
   * On Android 11 and below, BLE scanning **requires** Location Services (GPS) to be turned on globally on the phone. The plugin checks this via `LocationManager`.
3. **Scan Limits:**
   * Android OS restricts apps to **5 scans per 30 seconds**. If exceeded, Android silently blocks scanning.
4. **Unexpected Connections:**
   * Android has a race condition where calling `disconnect()` right as a connection is establishing might be ignored. The Java plugin implements a workaround (`handleUnexpectedConnectionEvents`) to catch this and force-close the `BluetoothGatt` object.
5. **GATT 133 Error (`GATT_ERROR`):**
   * This is the most common Android BLE error. It is a generic failure. The plugin maps this to `android-code: 133`. It is advised to:
     1. Catch the error and retry the connection.
     2. Ensure `device.disconnect()` is called properly to free up GATT resources.
     3. Try `device.clearGattCache()`.
6. **Services Changed Characteristic (0x2A05):**
   * The Android plugin automatically listens to the GAP Services Changed characteristic. If triggered, it emits to `onServicesReset`, prompting the Dart side to require a new `discoverServices()` call.

---

## 5. Error Handling (Android Specifics)

The plugin maps Android `BluetoothGatt` and `BluetoothStatusCodes` to Dart exceptions.

**Common Android Error Codes to recognize:**
* `8` (`GATT_INSUFFICIENT_AUTHORIZATION`): Needs bonding/pairing.
* `15` (`GATT_INSUFFICIENT_ENCRYPTION`): Needs bonding/pairing.
* `133` (`GATT_ERROR`): Generic Android BLE stack failure.
* `257` (`GATT_FAILURE`): Generic failure.
* `13106`: The request code used by the plugin when asking the user to turn on Bluetooth via `Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)`.

**Permission Errors:**
If the plugin throws an error containing `"Permission ... required"`, request permissions at runtime using a package like `permission_handler`, as `flutter_blue_plus` does *not* request permissions automatically (it only checks if they are granted).