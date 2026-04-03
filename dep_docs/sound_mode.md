# sound_mode

A Flutter plugin for detecting and controlling the ringer mode (Normal, Silent, Vibrate) on Android devices.  
Also supports detecting ringer mode status on iOS (read-only).

---

## Features

- Detect the current ringer mode on Android and iOS
- Toggle between **Normal**, **Silent**, and **Vibrate** modes (Android only)
- Request and manage **Do Not Disturb** permissions on Android 6.0 (API 23) and above

---

## Installation

Add `sound_mode` to your [`pubspec.yaml`](https://flutter.dev/docs/development/packages-and-plugins/using-package) file:

```yaml
dependencies:
  sound_mode: ^3.1.1
```

Then run:

```bash
flutter pub get
```

---

## Android Setup

### Permissions

To allow the app to change ringer mode on Android 6.0+, you need to request **Do Not Disturb access**.  
Add the following permission to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />
```

Place this inside the `<manifest>` tag, not inside `<application>`.

---

## Usage

### Get current ringer mode

```dart
import 'package:sound_mode/sound_mode.dart';

String ringerStatus = await SoundMode.ringerModeStatus;
print(ringerStatus);
```

### Change ringer mode (Android only)

```dart
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

try {
  await SoundMode.setSoundMode(RingerModeStatus.silent);
} on PlatformException {
  print('Please enable the required permissions');
}
```

### Handling Do Not Disturb Access (Android 6.0+)

To change the ringer mode on devices running Android 6.0 (API level 23) and above, your app must have **Do Not Disturb access** (also known as Notification Policy Access). Without this, calls to `setSoundMode()` will fail.

#### 1. Add permission to AndroidManifest.xml

Make sure the following permission is declared:

```xml
<uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />
```

#### 2. Check and request permission at runtime

Use the plugin's built-in `PermissionHandler` to check if access is granted, and open the system settings page if needed:

```dart
import 'package:sound_mode/permission_handler.dart';

bool isGranted = await PermissionHandler.permissionsGranted;

if (!isGranted) {
  // This will open the system settings where the user can manually grant access
  await PermissionHandler.openDoNotDisturbSetting();
}
```

---

## iOS Support

> **Warning:** iOS support is currently **experimental and unreliable**.  
> Reading the ringer mode status may **not work consistently** across all devices and OS versions.  
> This feature also does **not work on iOS simulators** — only real devices.

We're actively looking for contributors to help improve iOS support.  
If you have experience with iOS native development or want to help debug the current implementation, feel free to [open an issue](https://github.com/your-repo-link/issues) or submit a pull request.

### Example (iOS)

A short delay is recommended before reading the ringer status for more reliable results:

```dart
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

RingerModeStatus ringerStatus = RingerModeStatus.unknown;

Future.delayed(const Duration(seconds: 1), () async {
try {
ringerStatus = await SoundMode.ringerModeStatus;
} catch (err) {
ringerStatus = RingerModeStatus.unknown;
}
print(ringerStatus);
});
```

---

## RingerModeStatus Values

| Value                      | Description                      |
|---------------------------|----------------------------------|
| `RingerModeStatus.unknown` | Unknown or unsupported status   |
| `RingerModeStatus.normal`  | Device is in Normal mode        |
| `RingerModeStatus.silent`  | Device is in Silent mode        |
| `RingerModeStatus.vibrate` | Device is in Vibrate mode       |

# Context & API Reference: `sound_mode` (Flutter Plugin)

## 1. Package Metadata
- **Package Name:** `sound_mode`
- **Version:** `3.1.1`
- **Dart SDK:** `>=2.12.0 <4.0.0` (Null-safe)
- **Platform Support:** 
  - **Android:** Read and Write (Full support)
  - **iOS:** Read-only (Experimental, does not work on simulators)
- **Method Channel:** `method.channel.audio`

## 2. Core Capabilities
This plugin allows Flutter applications to:
1. Read the current device ringer mode (Normal, Silent, Vibrate).
2. Change the device ringer mode (Android only).
3. Check and request "Do Not Disturb" (DND) / Notification Policy Access permissions required to change sound modes on Android 6.0 (API 23) and above.

---

## 3. Setup Requirements (Instructions for Project Configuration)

When generating setup instructions for a user, always include the following Android requirement.

**Android (`android/app/src/main/AndroidManifest.xml`):**
Must include the `ACCESS_NOTIFICATION_POLICY` permission outside the `<application>` tag.
```xml
<uses-permission android:name="android.permission.ACCESS_NOTIFICATION_POLICY" />
```

**iOS:**
No specific `Info.plist` permissions are required, but the feature is experimental and requires a physical device.

---

## 4. API Reference

### 4.1 Enums
**`RingerModeStatus`**
Represents the current sound profile of the device.
```dart
enum RingerModeStatus { 
  unknown, 
  normal, 
  silent, 
  vibrate 
}
```

### 4.2 Class: `SoundMode`
The primary class for interacting with the device's sound profile.

| Method Signature | Description | Exceptions |
| :--- | :--- | :--- |
| `static Future<RingerModeStatus> get ringerModeStatus` | Gets the current device's sound mode. | Returns `RingerModeStatus.unknown` on failure. |
| `static Future<RingerModeStatus> setSoundMode(RingerModeStatus profile)` | Sets the device's sound mode. (Android Only). | Throws `PlatformException` if DND permissions are not granted on Android 6.0+. |

### 4.3 Class: `PermissionHandler`
Used to manage Android "Do Not Disturb" access, which is strictly required to use `setSoundMode`.

| Method Signature | Description |
| :--- | :--- |
| `static Future<bool?> get permissionsGranted` | Checks if the app has DND access. Returns `true` if granted or if API < 23. |
| `static Future<void> openDoNotDisturbSetting()` | Opens the Android system settings page for the user to manually grant DND access. |

---

## 5. Standard Usage Patterns (Code Generation Templates)

When generating Dart code using this package, adhere to the following patterns.

### Pattern A: Reading the Current Sound Mode
*Note: For iOS reliability, it is recommended to wrap the call in a slight delay if called immediately on app startup.*

```dart
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

Future<RingerModeStatus> fetchCurrentSoundMode() async {
  try {
    // Optional delay for iOS reliability
    await Future.delayed(const Duration(milliseconds: 500));
    return await SoundMode.ringerModeStatus;
  } catch (e) {
    return RingerModeStatus.unknown;
  }
}
```

### Pattern B: Safely Setting the Sound Mode (Android)
*Rule: Always check permissions before attempting to set the sound mode. Catch `PlatformException` as a fallback.*

```dart
import 'package:flutter/services.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/permission_handler.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

Future<void> changeSoundMode(RingerModeStatus targetMode) async {
  // 1. Check Permissions
  bool? isGranted = await PermissionHandler.permissionsGranted;
  
  if (isGranted != true) {
    // 2. Prompt user to open settings if permission is missing
    await PermissionHandler.openDoNotDisturbSetting();
    return; // Exit early, user needs to grant permission manually
  }

  // 3. Set the mode
  try {
    RingerModeStatus newStatus = await SoundMode.setSoundMode(targetMode);
    print("Successfully changed to: $newStatus");
  } on PlatformException catch (e) {
    print("Failed to set sound mode. DND permission might still be missing: $e");
  }
}
```

---

## 6. Guardrails & Known Limitations

1. **Do NOT use `setSoundMode` for iOS.** The plugin only supports reading the status on iOS. Setting the status will result in a `MissingPluginException` or `NotImplemented` error.
2. **iOS Simulators:** Reading the sound mode on iOS **does not work on simulators**. It requires a physical iOS device.
3. **Permission Handling:** The plugin cannot programmatically force DND permissions. It can only open the settings screen via `PermissionHandler.openDoNotDisturbSetting()` for the user to toggle manually.
4. **State Management:** The plugin does not provide a stream/listener for sound mode changes. To detect changes made outside the app, the app must actively poll `SoundMode.ringerModeStatus` (e.g., using `WidgetsBindingObserver` on app resume).