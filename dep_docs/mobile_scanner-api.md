
# `mobile_scanner` - Android API & Usage Guide

## 1. Overview & Native Stack
On Android, `mobile_scanner` is built on top of two primary Google libraries:
*   **CameraX:** Used for camera lifecycle management, preview rendering (`SurfaceProducer`), and image analysis.
*   **Google ML Kit Vision (Barcode Scanning):** Used for detecting and parsing barcodes from the camera feed or static images.

## 2. Android Setup & Configuration

### Minimum Requirements
*   **`compileSdk`**: 34 or higher (Plugin uses 36).
*   **`minSdkVersion`**: 23 or higher.
*   **Java Version**: Java 17 (`JavaVersion.VERSION_17`).
*   **Kotlin Version**: 1.9.0 or higher (Plugin uses 2.1.0).

### Permissions
The plugin automatically declares the following in its `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" android:required="false" />
```
*Note: The plugin handles runtime permission requests automatically when `MobileScannerController.start()` is called.*

### ML Kit Dependency: Bundled vs. Unbundled
By default, the plugin uses the **bundled** version of ML Kit (`com.google.mlkit:barcode-scanning`). This adds ~3MB to 10MB to the APK size but works immediately offline.

To use the **unbundled** version (downloads via Google Play Services, adding only ~600KB to the APK), add the following to the Android project's `android/gradle.properties`:
```properties
dev.steenbakker.mobile_scanner.useUnbundled=true
```

---

## 3. Core Dart API (Android Focus)

### `MobileScannerController`
The controller manages the camera state and configuration.

#### Android-Specific / Android-Supported Parameters:
*   **`cameraResolution`** (`Size?`): **[Android Only]** Attempts to match the requested resolution (e.g., `Size(1920, 1080)`). If null, CameraX defaults to 640x480.
*   **`autoZoom`** (`bool`): **[Android Only]** If `true`, ML Kit will instruct the camera to automatically zoom in on barcodes that are far away.
*   **`invertImage`** (`bool`): **[Android Only]** If `true`, inverts the colors of the camera frames before passing them to ML Kit. Required for scanning white-on-black barcodes (which ML Kit does not support natively). *Note: Incurs a slight performance cost due to Bitmap manipulation.*
*   **`lensType`** (`CameraLensType`): Selects the physical lens (`normal`, `wide`, `zoom`, `any`). On Android, this calculates the 35mm equivalent focal length to classify physical lenses on multi-camera devices.
*   **`returnImage`** (`bool`): If `true`, returns the JPEG byte array of the frame where the barcode was found.
*   **`detectionSpeed`** (`DetectionSpeed`):
    *   `noDuplicates`: Ignores consecutive identical barcodes.
    *   `normal`: Respects `detectionTimeoutMs` between scans.
    *   `unrestricted`: Scans every frame (may cause memory pressure).
*   **`detectionTimeoutMs`** (`int`): Milliseconds to wait between scans when speed is `normal`.

### `MobileScanner` (Widget)
The UI component that renders the CameraX `SurfaceProducer` texture.

#### Android-Supported Parameters:
*   **`scanWindow`** (`Rect?`): Restricts the scanning area. On Android, this is highly optimized; the plugin scales the `Rect` to the `ImageProxy` dimensions and checks if the barcode's `cornerPoints` fall entirely within the window.
*   **`tapToFocus`** (`bool`): If `true`, tapping the widget triggers CameraX `FocusMeteringAction` at the tapped coordinates.
*   **`useAppLifecycleState`** (`bool`): Automatically pauses/resumes the CameraX session based on Flutter app lifecycle.

---

## 4. Android Data Structures

### `BarcodeCapture`
Returned by the `controller.barcodes` stream.
*   `barcodes` (`List<Barcode>`): List of detected barcodes.
*   `image` (`Uint8List?`): JPEG bytes of the frame (if `returnImage: true`).
*   `size` (`Size`): The dimensions of the camera frame (e.g., 1920x1080).

### `Barcode`
*   `rawValue` (`String?`): The UTF-8 decoded string.
*   `rawDecodedBytes` (`BarcodeBytes?`): On Android, this returns a `DecodedBarcodeBytes` object containing the `Uint8List` of the raw payload (without header/padding).
*   `corners` (`List<Offset>`): 4 points representing the bounding box. On Android, this maps directly to ML Kit's `cornerPoints`.
*   `format` (`BarcodeFormat`): e.g., `qrCode`, `code128`, `pdf417`.
*   `type` (`BarcodeType`): e.g., `url`, `wifi`, `contactInfo`.

---

## 5. Advanced Android Methods

### `analyzeImage(String path)`
Analyzes a static image file from the Android file system.
```dart
final BarcodeCapture? capture = await controller.analyzeImage(imageFile.path);
```
*Native Implementation:* Uses `InputImage.fromFilePath()` on Android.

### `switchCamera(SwitchCameraOption option)`
Switches the active camera.
*   `ToggleDirection()`: Switches between front and back.
*   `ToggleLensType()`: Cycles through `normal` -> `wide` -> `zoom`.
*   `SelectCamera(facingDirection, lensType)`: Explicit selection.

### `getSupportedLenses()`
Returns a `Set<CameraLensType>`.
*Native Implementation:* Iterates through Android's `CameraManager`, checks `CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS` and `SENSOR_INFO_PHYSICAL_SIZE`, and calculates the 35mm equivalent to classify lenses as Wide (<20mm), Normal (20-35mm), or Zoom (>35mm).

---

## 6. Usage Examples

### Basic Implementation
```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class BasicScanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MobileScanner(
        onDetect: (BarcodeCapture capture) {
          final String? code = capture.barcodes.first.rawValue;
          print('Scanned: $code');
        },
      ),
    );
  }
}
```

### Advanced Android-Optimized Implementation
```dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class AdvancedAndroidScanner extends StatefulWidget {
  @override
  State<AdvancedAndroidScanner> createState() => _AdvancedAndroidScannerState();
}

class _AdvancedAndroidScannerState extends State<AdvancedAndroidScanner> with WidgetsBindingObserver {
  late final MobileScannerController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    controller = MobileScannerController(
      autoStart: false,
      // Android specific optimizations
      cameraResolution: const Size(1920, 1080),
      autoZoom: true, 
      invertImage: false, // Set to true if scanning inverted QR codes
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 500,
      returnImage: true,
    );
    
    controller.start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!controller.value.hasCameraPermission) return;
    // Handle CameraX lifecycle manually
    if (state == AppLifecycleState.resumed) {
      controller.start();
    } else if (state == AppLifecycleState.inactive) {
      controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MobileScanner(
        controller: controller,
        tapToFocus: true, // Enables CameraX tap-to-focus
        scanWindow: const Rect.fromLTWH(100, 200, 200, 200), // Hardware optimized on Android
        onDetect: (capture) {
          // Handle capture
        },
      ),
    );
  }
}
```

---

## 7. Native Android Implementation Details

If debugging native Android issues, keep the following in mind:

1.  **Texture Rotation:** Android `SurfaceProducer` does not always handle crop and rotation automatically. The Dart side uses an `AndroidSurfaceProducerDelegate` and a `RotatedPreview` widget to manually rotate the Flutter `Texture` based on `sensorOrientationDegrees` and `DeviceOrientation`.
2.  **Orientation Listener:** The plugin uses `DisplayManager.DisplayListener` instead of raw sensor data. This ensures the scanner respects the Android system's rotation lock and Flutter's `SystemChrome.setPreferredOrientations`.
3.  **Image Inversion:** When `invertImage` is true, the native code converts the CameraX `ImageProxy` to a `Bitmap`, applies a `ColorMatrixColorFilter` to invert the RGB channels, and passes the new Bitmap to ML Kit.
4.  **Image Return:** When `returnImage` is true, the native code processes the image inside a Kotlin Coroutine (`Dispatchers.IO`) to prevent blocking the main UI thread while compressing the Bitmap to a JPEG byte array.
5.  **CameraX Logging:** The plugin explicitly configures `ProcessCameraProvider` to set the minimum logging level to `Log.ERROR` to prevent CameraX from spamming the Android Logcat with informational messages.