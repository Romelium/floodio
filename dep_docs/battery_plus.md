# Context & API Documentation: `battery_plus`

## 1. Package Metadata
*   **Package Name:** `battery_plus`
*   **Version:** `7.0.0`
*   **Description:** A Flutter plugin to access various information about the device's battery state (full, charging, discharging), battery level, and power save mode.
*   **Architecture:** Singleton pattern. Instantiating `Battery()` multiple times returns the same instance.

## 2. Platform Support & Requirements
When creating code or setup instructions, ensure the environment meets these minimum requirements:

| Platform | Supported | Minimum Version / Notes |
| :--- | :---: | :--- |
| **Android** | ✅ | API 21+, **Java 17**, **Kotlin 2.2.0**, **AGP >= 8.12.1**, **Gradle >= 8.13** |
| **iOS** | ✅ | iOS 12.0+ |
| **macOS** | ✅ | macOS 10.14+ |
| **Web** | ✅ | Uses `package:web` (WASM supported) |
| **Linux** | ✅ | |
| **Windows** | ✅ | |

*Note: `isInBatterySaveMode` is currently only implemented on Android, iOS, macOS, and Windows.*

---

## 3. Core API Reference

### Class: `Battery`
The main entry point for the plugin. 
```dart
import 'package:battery_plus/battery_plus.dart';

final Battery battery = Battery(); // Singleton instance
```

### Methods & Properties

| Return Type | Getter | Description |
| :--- | :--- | :--- |
| `Future<int>` | `batteryLevel` | Returns the current battery level as a percentage (0 to 100). |
| `Future<BatteryState>` | `batteryState` | Returns the current state of the battery (e.g., charging, discharging). |
| `Future<bool>` | `isInBatterySaveMode`| Returns `true` if the device is currently in low-power/battery-save mode. |
| `Stream<BatteryState>` | `onBatteryStateChanged`| A stream that fires whenever the battery state changes. |

### Enum: `BatteryState`
Represents the current physical state of the battery.
*   `BatteryState.charging`: Device is plugged in and actively charging.
*   `BatteryState.full`: Device is plugged in and battery is at 100%.
*   `BatteryState.discharging`: Device is unplugged and running on battery.
*   `BatteryState.connectedNotCharging`: Device is plugged in but not actively charging (e.g., thermal throttling or battery protection features).
*   `BatteryState.unknown`: State cannot be determined (e.g., batteryless systems).

---

## 4. Usage Patterns & Code Snippets

### Pattern 1: One-time asynchronous reads
When needs to check the battery status on demand (e.g., on a button press).

```dart
import 'package:battery_plus/battery_plus.dart';

Future<void> checkBatteryStatus() async {
  final battery = Battery();

  // 1. Get Battery Level
  final int level = await battery.batteryLevel;
  print('Battery level is $level%');

  // 2. Get Battery State
  final BatteryState state = await battery.batteryState;
  print('Current state: ${state.name}');

  // 3. Check Power Save Mode
  final bool isPowerSave = await battery.isInBatterySaveMode;
  print('Power save mode active: $isPowerSave');
}
```

### Pattern 2: Listening to Battery State Changes (StatefulWidget)
Use this pattern when creating UI that needs to react to the charger being plugged in or unplugged. **Always include `StreamSubscription` cancellation in the `dispose` method.**

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';

class BatteryMonitorWidget extends StatefulWidget {
  const BatteryMonitorWidget({super.key});

  @override
  State<BatteryMonitorWidget> createState() => _BatteryMonitorWidgetState();
}

class _BatteryMonitorWidgetState extends State<BatteryMonitorWidget> {
  final Battery _battery = Battery();
  BatteryState? _batteryState;
  StreamSubscription<BatteryState>? _batteryStateSubscription;

  @override
  void initState() {
    super.initState();
    
    // Get initial state
    _battery.batteryState.then((state) {
      setState(() => _batteryState = state);
    });

    // Listen for subsequent changes
    _batteryStateSubscription = _battery.onBatteryStateChanged.listen((BatteryState state) {
      setState(() {
        _batteryState = state;
      });
    });
  }

  @override
  void dispose() {
    // CRITICAL: Always cancel the stream subscription to prevent memory leaks
    _batteryStateSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text('Current Battery State: ${_batteryState?.name ?? "Loading..."}');
  }
}
```

---

## 5. Implementation Directives & Edge Cases

1.  **Android Build Errors:** If Android build errors after adding version `7.0.0`, update their `android/build.gradle` and `android/settings.gradle` to use **Kotlin 2.2.0** and **AGP 8.12.1+**.
2.  **Singleton Awareness:** Do not create complex dependency injection setups for the `Battery` class unless requested. `Battery()` is already a factory constructor returning a singleton.
3.  **Context.mounted Check:** If creating code where battery properties are awaited inside a UI callback (like `onPressed`), always wrap the subsequent UI updates (like `showDialog` or `ScaffoldMessenger`) in an `if (context.mounted)` check.
4.  **Power Save Mode Limitations:** If asks for power save mode on Linux or Web, `isInBatterySaveMode` is only supported on Android, iOS, macOS, and Windows.
5.  **Android Manufacturer Quirks:** The plugin handles custom power-saving implementations for Xiaomi, Huawei, and Samsung under the hood. Does not need to write custom platform channels for these devices.