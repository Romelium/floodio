# flutter_ringtone_player

A simple ringtone, alarm & notification player plugin.

[![pub package](https://img.shields.io/pub/v/flutter_ringtone_player.svg)](https://pub.dartlang.org/packages/flutter_ringtone_player)
[![flutter](https://github.com/inway/flutter_ringtone_player/actions/workflows/flutter.yml/badge.svg)](https://github.com/inway/flutter_ringtone_player/actions/workflows/flutter.yml)

## Usage

Add following import to your code:

```dart
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
```

Then simply call this to play system default notification sound:

```dart
FlutterRingtonePlayer().playNotification();
```

There's also this generic method allowing you to specify in detail what kind of ringtone should be played:

```dart
FlutterRingtonePlayer().play(
  android: AndroidSounds.notification,
  ios: IosSounds.glass,
  looping: true, // Android only - API >= 28
  volume: 0.1, // Android only - API >= 28
  asAlarm: false, // Android only - all APIs
);
```

Also you can specify a custom ringtone from assets, or provide direct path to file that works for 
both Android and iOS:

```dart
FlutterRingtonePlayer().play(fromAsset: "assets/ringtone.wav");  
```

```dart
FlutterRingtonePlayer().play(fromFile: "assets/ringtone.wav");  
```

You can specify a platform specific ringtone and it will override the one from assets:
```dart
FlutterRingtonePlayer().play(  
 fromAsset: "assets/ringtone.wav", // will be the sound on Android
 ios: IosSounds.glass 			   // will be the sound on iOS
 );  
```

### .play() optional attributes

| Attribute       |  Description |
| --------------  | ------------ |
| `bool` looping  | Enables looping of ringtone. Requires `FlutterRingtonePlayer().stop();` to stop ringing. |
| `double` volume | Sets ringtone volume in range 0 to 1.0. |
| `bool` asAlarm  | Allows to ignore device's silent/vibration mode and play given sound anyway. |


To stop looped ringtone please use:

```dart
FlutterRingtonePlayer().stop();
```

Above works only on Android, and please note that by default Alarm & Ringtone sounds are looped.

## Default sounds

| Method           | Android | iOS |
| ---------------- | ------- | --- |
| playAlarm        | [RingtoneManager.TYPE_ALARM](https://developer.android.com/reference/android/media/RingtoneManager#TYPE_ALARM) | IosSounds.alarm |
| playNotification | [RingtoneManager.TYPE_NOTIFICATION](https://developer.android.com/reference/android/media/RingtoneManager#TYPE_NOTIFICATION) | IosSounds.triTone |
| playRingtone     | [RingtoneManager.TYPE_RINGTONE](https://developer.android.com/reference/android/media/RingtoneManager#TYPE_RINGTONE) | IosSounds.electronic |

### Note on iOS sounds

If you want to use any other sound on iOS you can always specify a valid Sound ID and manually construct [IosSound]:

```dart
FlutterRingtonePlayer().play(
  android: AndroidSounds.notification,
  ios: const IosSound(1023),
  looping: true,
  volume: 0.1,
);
```

# Context & API Documentation: `flutter_ringtone_player`

## 1. Overview
`flutter_ringtone_player` is a Flutter plugin used to play system default sounds (ringtones, alarms, notifications) as well as custom audio files from assets or local device storage. 

**Supported Platforms:** Android, iOS.
**Key Capabilities:**
- Play system default sounds.
- Play custom sounds from Flutter `assets/` or local file paths.
- Control volume and looping.
- Bypass device silent/vibrate mode on Android using the `asAlarm` flag.

---

## 2. Core API Reference

The primary class is `FlutterRingtonePlayer`. It exposes several methods to trigger audio playback.

### 2.1. Generic Play Method
The `play()` method is the most customizable way to trigger audio.

```dart
Future<void> play({
  AndroidSound? android,
  IosSound? ios,
  String? fromAsset,
  String? fromFile,
  double? volume,
  bool? looping,
  bool? asAlarm,
})
```
**Parameters:**
- `android` *(AndroidSound?)*: The system sound to play on Android.
- `ios` *(IosSound?)*: The system sound to play on iOS.
- `fromAsset` *(String?)*: Path to a Flutter asset (e.g., `"assets/sound.mp3"`). Overrides system sounds if provided, unless platform-specific fallbacks are defined.
- `fromFile` *(String?)*: Direct absolute path to a local file on the device.
- `volume` *(double?)*: Volume level from `0.0` to `1.0`. (Android API >= 28, iOS API >= 9).
- `looping` *(bool?)*: If `true`, the sound loops indefinitely until `stop()` is called.
- `asAlarm` *(bool?)*: **Android only.** If `true`, plays the sound using the Alarm audio stream, bypassing the device's silent/vibrate mode.

### 2.2. Convenience Methods
These methods wrap `play()` with pre-configured defaults for common use cases.

```dart
// Plays default alarm. Defaults: looping = true, asAlarm = true.
Future<void> playAlarm({double? volume, bool looping = true, bool asAlarm = true})

// Plays default notification. Defaults: looping = null, asAlarm = false.
Future<void> playNotification({double? volume, bool? looping, bool asAlarm = false})

// Plays default ringtone. Defaults: looping = true, asAlarm = false.
Future<void> playRingtone({double? volume, bool looping = true, bool asAlarm = false})
```

### 2.3. Stop Method
```dart
Future<void> stop()
```
- Stops any currently playing looped sound or media player.
- **Note:** This is primarily for Android. On iOS, system sounds cannot be programmatically stopped once triggered unless they are custom media files.

---

## 3. Sound Definitions (Enums/Constants)

### 3.1. `AndroidSounds`
Used with the `android:` parameter.
- `AndroidSounds.alarm` (System default alarm)
- `AndroidSounds.notification` (System default notification)
- `AndroidSounds.ringtone` (System default ringtone)

### 3.2. `IosSounds`
Used with the `ios:` parameter. Maps to iOS System Sound IDs.
- `IosSounds.newMail`
- `IosSounds.mailSent`
- `IosSounds.voicemail`
- `IosSounds.receivedMessage`
- `IosSounds.sentMessage`
- `IosSounds.alarm`
- `IosSounds.lowPower`
- `IosSounds.triTone` (Standard iOS notification)
- `IosSounds.chime`
- `IosSounds.glass`
- `IosSounds.horn`
- `IosSounds.bell`
- `IosSounds.electronic` (Standard iOS ringtone)

*Note: Custom iOS sound IDs can be passed manually via `const IosSound(int id)` (valid range: 1000-2000).*

---

## 4. Platform-Specific Rules & Limitations (Instructions)

When creating code using this package, adhere to the following constraints:

1. **iOS File Formats:** If using `fromAsset` or `fromFile` on iOS, the file extension **MUST** be one of: `.wav`, `.mp3`, `.aiff`, or `.caf`. The plugin will throw an error otherwise.
2. **Missing Source Error:** When calling `play()`, the user must provide at least one audio source (`fromAsset`, `fromFile`, or BOTH `android` and `ios`).
3. **Looping Cleanup:** If `looping: true` is used, you must be reminded to create UI logic (like a button) to call `FlutterRingtonePlayer().stop()`.
4. **Asset Declaration:** If creating code that uses `fromAsset`, remind the user to declare the asset in their `pubspec.yaml`.

---

## 5. Usage Examples (Snippets for Context)

### Example 1: Simple System Notification
```dart
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

// Plays the default notification sound for the respective platform
FlutterRingtonePlayer().playNotification();
```

### Example 2: Highly Configured Playback
```dart
FlutterRingtonePlayer().play(
  android: AndroidSounds.notification,
  ios: IosSounds.glass,
  looping: true, 
  volume: 0.8, 
  asAlarm: false, 
);
```

### Example 3: Playing a Custom Asset with Platform Fallback
```dart
FlutterRingtonePlayer().play(
  fromAsset: "assets/custom_sound.mp3", // Used on Android
  ios: IosSounds.electronic,            // Overrides asset on iOS
);
```

### Example 4: Playing a Local File
```dart
// Assuming `filePath` is obtained via path_provider or file picker
FlutterRingtonePlayer().play(
  fromFile: "/storage/emulated/0/Download/my_ringtone.mp3",
);
```

### Example 5: Alarm that bypasses Silent Mode (Android)
```dart
FlutterRingtonePlayer().playAlarm(
  asAlarm: true, // Forces playback through the alarm channel
  looping: true,
);

// Later, to stop the alarm:
// FlutterRingtonePlayer().stop();
```