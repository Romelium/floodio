# 📱 Pretty QR Code 3.6.0 - Android Integration & API Reference

## 1. Overview
`pretty_qr_code` is a highly customizable Flutter package for rendering QR codes. It allows for advanced styling including custom shapes (dots, smooth, squares), gradient brushes, embedded center images (logos), and exporting QR codes to the Android file system.

## 2. Android Setup & Permissions

To use the basic rendering features, no special Android permissions are required. However, if your application needs to **save/export** the generated QR code to the Android device's storage, you must configure the `AndroidManifest.xml`.

### `android/app/src/main/AndroidManifest.xml`
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.your.package.name">
    
    <!-- Required if fetching embedded logos from the network -->
    <uses-permission android:name="android.permission.INTERNET"/>
    
    <!-- Required for saving QR codes to Android local storage (Android 9 and below) -->
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>

    <application>
        ...
    </application>
</manifest>
```

---

## 3. Core API Reference

### `PrettyQrView` (Main Widget)
The primary widget used to display the QR code.
*   **`PrettyQrView.data(...)`**: Recommended constructor for direct string-to-QR rendering.
    *   `data` *(String)*: The text/URL to encode.
    *   `errorCorrectLevel` *(int)*: Error correction level (e.g., `QrErrorCorrectLevel.H` for high, recommended when embedding images).
    *   `decoration` *(PrettyQrDecoration)*: Styling configuration.
    *   `errorBuilder` *(Widget Function)*: Handles encoding errors.
*   **`PrettyQrView(...)`**: Constructor used when you pre-compute the `QrImage` object (recommended for performance).

### `PrettyQrDecoration`
Defines the visual appearance of the QR code.
*   `shape` *(PrettyQrShape)*: The geometric style of the QR modules.
*   `image` *(PrettyQrDecorationImage)*: An image/logo to embed inside the QR code.
*   `background` *(Color)*: Background color of the QR code.
*   `quietZone` *(PrettyQrQuietZone)*: The padding/margin around the QR code (e.g., `PrettyQrQuietZone.standard`).

### `PrettyQrShape` (Implementations)
*   **`PrettyQrSmoothSymbol`**: Rounded, liquid-like connected modules.
*   **`PrettyQrSquaresSymbol`**: Standard squares, with an optional `rounding` parameter (0.0 to 1.0).
*   **`PrettyQrDotsSymbol`**: Circular dots.
*   **`PrettyQrCustomShape`**: Allows mixing shapes (e.g., dots for data, smooth for finder patterns).
*   *Note: `PrettyQrRoundedSymbol` is DEPRECATED. Use `PrettyQrSquaresSymbol` instead.*

### `PrettyQrBrush`
Used to color the shapes.
*   `PrettyQrBrush.solid(Color)`: Solid color.
*   `PrettyQrBrush.gradient(Gradient)`: Applies a Flutter `LinearGradient`, `RadialGradient`, etc.

### `PrettyQrDecorationImage`
*   `image` *(ImageProvider)*: e.g., `AssetImage('assets/logo.png')`.
*   `position` *(PrettyQrDecorationImagePosition)*: `.embedded` (center cut out), `.foreground` (overlay), `.background` (underneath).
*   `padding` *(EdgeInsets)*: Padding around the embedded image.

---

## 4. Usage Examples (Flutter / Dart)

### Example A: Basic QR Code
```dart
import 'package:pretty_qr_code/pretty_qr_code.dart';

PrettyQrView.data(
  data: 'https://flutter.dev',
  errorCorrectLevel: QrErrorCorrectLevel.M,
  decoration: const PrettyQrDecoration(
    shape: PrettyQrSquaresSymbol(color: Colors.black),
  ),
);
```

### Example B: Advanced Styling (Gradient, Logo, Smooth Shape)
```dart
PrettyQrView.data(
  data: 'https://android.com',
  errorCorrectLevel: QrErrorCorrectLevel.H, // High error correction needed for logos
  decoration: const PrettyQrDecoration(
    shape: PrettyQrSmoothSymbol(
      color: PrettyQrBrush.gradient(
        gradient: LinearGradient(
          colors: [Colors.blue, Colors.green],
        ),
      ),
    ),
    image: PrettyQrDecorationImage(
      image: AssetImage('assets/android_logo.png'),
      position: PrettyQrDecorationImagePosition.embedded,
      padding: EdgeInsets.all(8),
    ),
    quietZone: PrettyQrQuietZone.standard,
  ),
);
```

### Example C: Custom Mixed Shapes
```dart
PrettyQrView.data(
  data: 'Mixed Shapes',
  decoration: const PrettyQrDecoration(
    shape: PrettyQrShape.custom(
      PrettyQrDotsSymbol(color: Colors.black), // Main data modules
      finderPattern: PrettyQrSmoothSymbol(color: Colors.blue), // The 3 corner squares
      alignmentPatterns: PrettyQrSquaresSymbol(color: Colors.red), // Smaller alignment squares
    ),
  ),
);
```

---

## 5. Android Specific: Exporting & Saving QR Codes

To save a generated QR code to the Android device's storage, use the `toImageAsBytes` extension on `QrImage`. 

*Requires the `path_provider` package to access Android directories.*

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

Future<String?> saveQrCodeToAndroid(BuildContext context, String data) async {
  // 1. Generate QR Code Data
  final qrCode = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.H,
  );
  final qrImage = QrImage(qrCode);

  // 2. Define Decoration
  const decoration = PrettyQrDecoration(
    shape: PrettyQrSmoothSymbol(color: Colors.black),
    quietZone: PrettyQrQuietZone.standard,
  );

  // 3. Convert to Image Bytes
  final bytes = await qrImage.toImageAsBytes(
    size: 512, // Pixel size of the output image
    format: dart:ui.ImageByteFormat.png,
    decoration: decoration,
    configuration: createLocalImageConfiguration(context),
  );

  if (bytes == null) return null;

  // 4. Get Android External Storage Directory
  final directory = await getExternalStorageDirectory(); // Android specific
  if (directory == null) return null;

  // 5. Write to File
  final file = File('${directory.path}/exported_qr.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());

  return file.path; // Returns the absolute path on the Android device
}
```

---

## 6. Best Practices

1.  **Do NOT use `PrettyQr` widget:** It is deprecated. Always use `PrettyQrView` or `PrettyQrView.data`.
2.  **Do NOT use `PrettyQrRoundedSymbol`:** It is deprecated. Use `PrettyQrSquaresSymbol(rounding: X)` instead.
3.  **Performance Optimization:** If the QR code data does not change frequently, do NOT instantiate `QrCode` and `QrImage` directly inside the `build()` method. Generate `QrImage` in `initState()` or a state management controller, and pass it to `PrettyQrView(qrImage: myQrImage)`.
4.  **Error Correction for Logos:** If `PrettyQrDecorationImage` is used, you MUST set `errorCorrectLevel: QrErrorCorrectLevel.H` (High - 30% recovery) to ensure the QR code remains scannable despite the center being covered by the image.
5.  **Web/Nested Image Warning:** If the Flutter app is compiled for Web alongside Android, note that nested images (`PrettyQrDecorationImage`) require the CanvasKit or Skwasm renderer. HTML renderer may fail to clip the image properly.