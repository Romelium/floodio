# flutter_image_compress

## 1. Overview
`flutter_image_compress` is a highly efficient Flutter plugin that compresses images using native APIs (Objective-C/Kotlin) rather than Dart. It supports **Android, iOS, macOS, Web, and OpenHarmony**. 

It is primarily used to reduce image file sizes for network transmission while maintaining aspect ratios and acceptable quality.

## 2. Installation & Platform Setup

**Dependency:**
```yaml
dependencies:
  flutter_image_compress: ^2.4.0 # Use the latest version
```

**Platform-Specific Configurations:**
*   **Web:** Requires the `pica` JS library. The following script must be added to `<flutter_project>/web/index.html` inside the `<head>` or `<body>`:
    ```html
    <script src="https://cdn.jsdelivr.net/npm/pica@9.0.1/dist/pica.min.js"></script>
    ```
    *Note: File-based compression methods (`compressWithFile`, `compressAndGetFile`) will throw exceptions on the Web.*
*   **macOS:** Requires a minimum deployment target of `10.15`. Update `macOS Deployment Target` in Xcode and `platform :osx, '10.15'` in the `Podfile`.
*   **Android:** Requires Kotlin `1.5.21` or higher.

---

## 3. Core API Reference

All methods are static and accessed via the `FlutterImageCompress` class.

### 3.1. `compressWithFile` (File -> Memory)
Compresses an image from a file path and returns it as a byte array (`Uint8List`).
```dart
static Future<Uint8List?> compressWithFile(
  String path, {
  int minWidth = 1920,
  int minHeight = 1080,
  int inSampleSize = 1,
  int quality = 95,
  int rotate = 0,
  bool autoCorrectionAngle = true,
  CompressFormat format = CompressFormat.jpeg,
  bool keepExif = false,
  int numberOfRetries = 5,
})
```

### 3.2. `compressAndGetFile` (File -> File)
Compresses an image from a file path and saves it to a `targetPath`. Returns an `XFile` (from the `cross_file` package).
*Note: `targetPath` and `path` cannot be the same.*
```dart
static Future<XFile?> compressAndGetFile(
  String path,
  String targetPath, {
  int minWidth = 1920,
  int minHeight = 1080,
  int inSampleSize = 1,
  int quality = 95,
  int rotate = 0,
  bool autoCorrectionAngle = true,
  CompressFormat format = CompressFormat.jpeg,
  bool keepExif = false,
  int numberOfRetries = 5,
})
```

### 3.3. `compressWithList` (Memory -> Memory)
Compresses an image from a `Uint8List` and returns the compressed `Uint8List`.
```dart
static Future<Uint8List> compressWithList(
  Uint8List image, {
  int minWidth = 1920,
  int minHeight = 1080,
  int quality = 95,
  int rotate = 0,
  int inSampleSize = 1,
  bool autoCorrectionAngle = true,
  CompressFormat format = CompressFormat.jpeg,
  bool keepExif = false,
})
```

### 3.4. `compressAssetImage` (Asset -> Memory)
Compresses an image directly from the Flutter asset bundle.
```dart
static Future<Uint8List?> compressAssetImage(
  String assetName, {
  int minWidth = 1920,
  int minHeight = 1080,
  int quality = 95,
  int rotate = 0,
  bool autoCorrectionAngle = true,
  CompressFormat format = CompressFormat.jpeg,
  bool keepExif = false,
})
```

---

## 4. Parameter Details

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `minWidth` / `minHeight` | `int` | `1920` / `1080` | Constraints for scaling. The image will be scaled down to fit within these bounds while maintaining its aspect ratio. If the original image is smaller than these bounds, it will not be upscaled. |
| `quality` | `int` | `95` | Compression quality (0-100). Ignored on iOS if the format is PNG. |
| `rotate` | `int` | `0` | Degrees to rotate the image. |
| `autoCorrectionAngle`| `bool` | `true` | Automatically rotates the image based on its EXIF orientation data. |
| `format` | `CompressFormat`| `.jpeg` | Target format: `.jpeg`, `.png`, `.webp`, or `.heic`. |
| `keepExif` | `bool` | `false` | Retains EXIF data (except orientation). Only supported for JPEG format. |
| `inSampleSize` | `int` | `1` | **Android only.** Subsampling size (e.g., 2 means 1/2 width/height). |
| `numberOfRetries` | `int` | `5` | Number of retries for file operations (handles OutOfMemory errors on Android by doubling `inSampleSize` on retry). |

---

## 5. Platform & Format Compatibility Matrix

| Format | Android | iOS | Web | macOS | OpenHarmony | Notes |
| :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| **JPEG** | ✅ | ✅ | ✅ | ✅ | ✅ | Default format. |
| **PNG** | ✅ | ✅ | ✅ | ✅ | ✅ | Lossless; `quality` param may be ignored. |
| **WEBP** | ✅ | ✅ | ✅ | ❌ | ✅ | Fast on Android. Uses SDWebImageWebPCoder on iOS (slower). |
| **HEIC** | ✅ | ✅ | ❌ | ✅ | ✅ | Requires iOS 11+ and Android API 28+ (with hardware encoder). |

---

## 6. Usage Examples

### Example 1: Compress File to File (Common for Uploads)
```dart
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

Future<XFile?> compressImage(File file) async {
  final dir = await getTemporaryDirectory();
  final targetPath = '${dir.absolute.path}/temp_${DateTime.now().millisecondsSinceEpoch}.jpg';

  final XFile? compressedFile = await FlutterImageCompress.compressAndGetFile(
    file.absolute.path,
    targetPath,
    quality: 85,
    minWidth: 1024,
    minHeight: 1024,
    format: CompressFormat.jpeg,
  );
  
  return compressedFile;
}
```

### Example 2: Compress File to Memory (For UI Display)
```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

Future<Widget> getCompressedImageWidget(String filePath) async {
  Uint8List? imageBytes = await FlutterImageCompress.compressWithFile(
    filePath,
    minWidth: 800,
    minHeight: 800,
    quality: 90,
  );
  
  if (imageBytes == null) return Text('Compression failed');
  return Image.memory(imageBytes);
}
```

### Example 3: Safe Format Fallback (Handling Unsupported Formats)
```dart
Future<Uint8List?> safeCompress(String path) async {
  try {
    // Try HEIC first (saves more space)
    return await FlutterImageCompress.compressWithFile(
      path,
      format: CompressFormat.heic,
    );
  } on UnsupportedError catch (_) {
    // Fallback to JPEG if HEIC is not supported by the OS/Device
    return await FlutterImageCompress.compressWithFile(
      path,
      format: CompressFormat.jpeg,
    );
  }
}
```

---

## 7. Important Constraints & Edge Cases to Remember

1. **`XFile` vs `File`:** Since version 2.0.0, `compressAndGetFile` returns an `XFile` (from `cross_file`), **not** a `dart:io` `File`. To get the length or bytes, use `await xfile.length()` or `await xfile.readAsBytes()`.
2. **Web Limitations:** Do not create code using `compressWithFile` or `compressAndGetFile` if the target platform includes Web. Use `compressWithList` instead.
3. **Same Path Error:** In `compressAndGetFile`, the `path` and `targetPath` **cannot be identical**. The plugin will throw a `CompressError`.
4. **File Extensions:** The plugin validates file extensions in `targetPath`. If `format` is `CompressFormat.jpeg`, the `targetPath` must end in `.jpg` or `.jpeg`.
5. **EXIF Data:** Compression strips EXIF data by default. If `keepExif: true` is used, it only works for JPEGs, and it *still* strips the orientation tag to prevent double-rotation issues.