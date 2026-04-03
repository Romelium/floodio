# `flutter_compass` (v0.8.1) - Usage Guide

## 1. Overview
`flutter_compass` is a Flutter plugin that provides compass heading, camera mode heading, and accuracy data. It reads data from native device sensors (Rotation Vector, Accelerometer, and Magnetic Field).

*   **Supported Platforms:** Android, iOS, Web (Stubbed/Empty Stream).
*   **Key Behavior:** The heading varies from `0` to `360` degrees, where `0` is North.
*   **Null Safety:** Fully supported.

---

## 2. Setup & Configuration

### Pubspec Dependency
```yaml
dependencies:
  flutter_compass: ^0.8.1
  permission_handler: ^11.0.0 # Highly recommended for requesting location permissions
```

### Android Configuration (`android/app/src/main/AndroidManifest.xml`)
The app requires location permissions to access compass hardware accurately.
```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

### iOS Configuration (`ios/Runner/Info.plist`)
Add the following keys to explain why the app needs location/compass access:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app requires access to the compass and location.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app requires access to the compass and location.</string>
```

---

## 3. Core API Reference

### `FlutterCompass` (Class)
A singleton class that acts as the entry point for the plugin.

| Property/Method | Type | Description |
| :--- | :--- | :--- |
| `events` | `static Stream<CompassEvent>?` | A broadcast stream emitting compass data. Returns `Stream.empty()` on Web. |

### `CompassEvent` (Class)
The data object emitted by the `FlutterCompass.events` stream.

| Property | Type | Description |
| :--- | :--- | :--- |
| `heading` | `double?` | The heading in degrees (0-360) around the Z axis (where the top of the device is pointing). **Can be null** if the device lacks sensors. |
| `headingForCameraMode` | `double?` | The heading in degrees around the X axis (where the back of the device is pointing). |
| `accuracy` | `double?` | The deviation error in degrees (+/-). On iOS, this is highly reliable. On Android, it maps to hardcoded values (15, 30, 45) based on sensor status. |

---

## 4. Critical Context & Edge Cases (Gotchas)

When creating code using this package, the you **must** account for the following:

1.  **Permissions are NOT handled by the plugin:** The plugin will not automatically ask for location permissions. The developer must use a package like `permission_handler` to request `Permission.locationWhenInUse` *before* relying on the compass stream.
2.  **Hardware Limitations (Null values):** If an Android device does not have the required sensors (Rotation Vector, or Accelerometer + Magnetic Field), `snapshot.data!.heading` will return `null`. **Always generate null checks for the heading.**
3.  **Math for UI Rotation:** To rotate a compass needle or image in Flutter based on the heading, the formula is:
    `angle: (heading * (math.pi / 180) * -1)`
4.  **Web Support:** The package compiles on the web but returns an empty stream. Do not attempt to read compass data on Flutter Web.

---

## 5. Standard Usage Patterns

### Pattern A: Continuous Listening via `StreamBuilder` (Recommended)
Used for building real-time compass UIs.

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

Widget buildCompassUI() {
  return StreamBuilder<CompassEvent>(
    stream: FlutterCompass.events,
    builder: (context, snapshot) {
      // 1. Handle Errors
      if (snapshot.hasError) {
        return Text('Error: ${snapshot.error}');
      }

      // 2. Handle Loading State
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const CircularProgressIndicator();
      }

      // 3. Extract Data
      final double? direction = snapshot.data?.heading;

      // 4. Handle Missing Sensors
      if (direction == null) {
        return const Text("Device does not have compass sensors.");
      }

      // 5. Render UI
      return Transform.rotate(
        // Convert degrees to radians and invert to rotate the image correctly
        angle: (direction * (math.pi / 180) * -1),
        child: Image.asset('assets/compass.jpg'),
      );
    },
  );
}
```

### Pattern B: Manual / One-Time Read
Used when you only need the current heading at a specific moment (e.g., saving a waypoint).

```dart
import 'package:flutter_compass/flutter_compass.dart';

Future<void> readCompassOnce() async {
  // Ensure the stream is not null (e.g., not on Web)
  if (FlutterCompass.events != null) {
    final CompassEvent event = await FlutterCompass.events!.first;
    
    if (event.heading != null) {
      print('Current Heading: ${event.heading}');
      print('Accuracy: ${event.accuracy}');
    } else {
      print('No compass sensor available on this device.');
    }
  }
}
```

---

## 6. Complete Implementation Example

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';

class CompassScreen extends StatefulWidget {
  const CompassScreen({Key? key}) : super(key: key);

  @override
  State<CompassScreen> createState() => _CompassScreenState();
}

class _CompassScreenState extends State<CompassScreen> {
  bool _hasPermissions = false;

  @override
  void initState() {
    super.initState();
    _fetchPermissionStatus();
  }

  Future<void> _fetchPermissionStatus() async {
    final status = await Permission.locationWhenInUse.request();
    if (mounted) {
      setState(() {
        _hasPermissions = (status == PermissionStatus.granted);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compass')),
      body: _hasPermissions ? _buildCompass() : _buildPermissionRequest(),
    );
  }

  Widget _buildCompass() {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final double? direction = snapshot.data?.heading;

        if (direction == null) {
          return const Center(child: Text("Device does not have compass sensors!"));
        }

        return Center(
          child: Transform.rotate(
            angle: (direction * (math.pi / 180) * -1),
            child: const Icon(Icons.arrow_upward, size: 100, color: Colors.red),
          ),
        );
      },
    );
  }

  Widget _buildPermissionRequest() {
    return Center(
      child: ElevatedButton(
        onPressed: _fetchPermissionStatus,
        child: const Text('Request Location Permission'),
      ),
    );
  }
}
```