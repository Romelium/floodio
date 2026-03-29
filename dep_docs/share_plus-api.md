# `share_plus` (Android) - Reference Document

## 1. Overview
`share_plus` is a Flutter plugin that wraps the Android native `Intent.ACTION_SEND` and `Intent.ACTION_SEND_MULTIPLE` actions to invoke the system share sheet. It allows sharing plain text, URIs, and files (via `FileProvider`) to other installed Android applications.

**Plugin Version:** `^12.0.1`
**Architecture:** Federated plugin (uses `share_plus_platform_interface`).

## 2. Android System Requirements
Based on the `android/build.gradle` and `CHANGELOG.md`:
*   **Min SDK:** 19 (Android 4.4 KitKat)
*   **Compile SDK:** 34 (or `flutter.compileSdkVersion`)
*   **Java Version:** 17 (`JavaVersion.VERSION_17`)
*   **Kotlin Version:** 2.2.0
*   **Android Gradle Plugin (AGP):** >= 8.12.1
*   **Gradle Wrapper:** >= 8.13

## 3. Dart API Surface (Flutter Side)

The primary entry point is the singleton `SharePlus.instance.share()`. 
*(Note: The legacy `Share.share()`, `Share.shareUri()`, and `Share.shareXFiles()` methods are deprecated).*

### `SharePlus.instance.share(ShareParams params)`
Returns a `Future<ShareResult>`.

#### `ShareParams` (Android Mapping)
| Dart Property | Type | Android Native Mapping | Description |
| :--- | :--- | :--- | :--- |
| `text` | `String?` | `Intent.EXTRA_TEXT` | The main text body to share. |
| `uri` | `Uri?` | `Intent.EXTRA_TEXT` | Shared as plain text on Android. Cannot be used simultaneously with `text`. |
| `subject` | `String?` | `Intent.EXTRA_SUBJECT` | Used by email clients as the email subject. |
| `title` | `String?` | `Intent.EXTRA_TITLE` & Chooser Title | The title of the share sheet and the content title. |
| `files` | `List<XFile>?` | `Intent.EXTRA_STREAM` | Files to share. Mapped to `content://` URIs via `FileProvider`. |
| `fileNameOverrides` | `List<String>?` | N/A | Overrides the names of dynamically generated files (`XFile.fromData`). |
| `sharePositionOrigin` | `Rect?` | N/A | **Ignored on Android** (Used for iPad/macOS popovers). |
| `excludedCupertinoActivities`| `List<Enum>?`| N/A | **Ignored on Android** (iOS/macOS only). |

#### `ShareResult`
*   **`status` (`ShareResultStatus`)**: 
    *   `.success`: User selected an app.
    *   `.dismissed`: User closed the share sheet without selecting an app.
    *   `.unavailable`: Result tracking is not supported (e.g., Android API < 22).
*   **`raw` (`String`)**: The flattened `ComponentName` of the selected app (e.g., `com.whatsapp/.ContactPicker`). Empty if dismissed.

---

## 4. Android Native Implementation Details (Under the Hood)

Understanding the native Kotlin implementation is crucial for debugging Android-specific issues.

### 4.1 Intent Construction (`Share.kt`)
*   **Text/URI Only:** Uses `Intent.ACTION_SEND` with MIME type `"text/plain"`.
*   **Single File:** Uses `Intent.ACTION_SEND` with the file's MIME type.
*   **Multiple Files:** Uses `Intent.ACTION_SEND_MULTIPLE`.
    *   *MIME Type Reduction:* If multiple files have different MIME types, the plugin attempts to find a common base (e.g., `image/png` and `image/jpeg` becomes `image/*`). If no common base exists, it falls back to `*/*`.

### 4.2 File Handling & Permissions
*   **Cache Directory:** All shared files are copied to a dedicated cache folder: `context.cacheDir + "/share_plus"`.
*   **FileProvider:** The plugin declares a custom `ShareFileProvider` in `AndroidManifest.xml` with the authority `${applicationId}.flutter.share_provider`.
*   **URI Grants:** The plugin queries the `PackageManager` for all apps that can handle the `chooserIntent` and explicitly grants `FLAG_GRANT_READ_URI_PERMISSION` and `FLAG_GRANT_WRITE_URI_PERMISSION` to those specific packages.

### 4.3 Share Result Tracking (`SharePlusPendingIntent.kt` & `ShareSuccessManager.kt`)
*   **API Requirement:** Tracking the share result requires Android API 22 (`LOLLIPOP_MR1`).
*   **Mechanism:** 
    1. The plugin creates a `PendingIntent` pointing to a custom `BroadcastReceiver` (`SharePlusPendingIntent`).
    2. This `PendingIntent` is passed to `Intent.createChooser()`.
    3. When the user selects a target app, the Android OS fires the `PendingIntent`, passing `Intent.EXTRA_CHOSEN_COMPONENT`.
    4. The `BroadcastReceiver` extracts the `ComponentName` and stores it.
    5. The `ShareSuccessManager` listens for `onActivityResult` (Activity Code `0x5873`) to know when the share sheet is closed, then retrieves the stored component name and sends it back to Flutter via the `MethodChannel`.
*   **Deadlock Prevention:** If a new `share()` call is made while an existing one is pending, the plugin automatically returns `ShareResult.unavailable` for the previous call to prevent Dart-side deadlocks.

---

## 5. Usage Examples (Dart)

### Sharing Text
```dart
import 'package:share_plus/share_plus.dart';

final result = await SharePlus.instance.share(
  ShareParams(
    text: 'Check out this link: https://flutter.dev',
    subject: 'Flutter Link', // Used if user selects an Email app
    title: 'Share Flutter',  // Share sheet title
  ),
);

if (result.status == ShareResultStatus.success) {
  print('Shared to: ${result.raw}'); // e.g., "com.twitter.android/.composer.ComposerActivity"
}
```

### Sharing Files (Local Paths)
```dart
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';

final params = ShareParams(
  text: 'Here are the logs',
  files: [
    XFile('/storage/emulated/0/Download/log1.txt'),
    XFile('/storage/emulated/0/Download/log2.txt'),
  ],
);

await SharePlus.instance.share(params);
```

### Sharing In-Memory Data (e.g., generated PDFs, Images)
```dart
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'dart:typed_data';

Uint8List pdfBytes = await generatePdf();

final params = ShareParams(
  files: [
    XFile.fromData(
      pdfBytes,
      mimeType: 'application/pdf',
    ),
  ],
  // CRITICAL: XFile.fromData ignores the 'name' parameter on Android. 
  // You MUST use fileNameOverrides to set the file extension, otherwise 
  // target apps won't know how to handle the file.
  fileNameOverrides: ['report.pdf'], 
);

await SharePlus.instance.share(params);
```

---

## 6. Known Android-Specific Limitations & Quirks

1.  **Facebook / Meta Apps (Messenger, Instagram, Facebook):**
    *   *Issue:* When sharing **Files + Text**, Meta apps often strip or ignore the `EXTRA_TEXT` field due to their own SDK restrictions. Only the file will appear in the composer.
    *   *Workaround:* None via standard Intents. Developers must use the native Facebook Sharing SDK if text+image sharing to FB is strictly required.
2.  **Cache Bloat (`XFile.fromData`):**
    *   *Issue:* When sharing data from memory, `share_plus` writes a temporary file to the app's cache directory (`.../caches/share_plus`). 
    *   *Behavior:* The plugin clears this specific folder *before* every new share action (`clearShareCacheFolder()`). However, if the app is closed, the last shared file remains in the cache until the OS clears it or the app shares again.
3.  **File Name Overrides:**
    *   When using `XFile.fromData`, the `name` property of `XFile` is ignored by the underlying `cross_file` package on Android. Developers **must** use `ShareParams.fileNameOverrides` to ensure the file has the correct extension when passed to the Android `FileProvider`.
4.  **Result Tracking on Older Devices:**
    *   On Android devices running API 21 or lower, `ShareResult.status` will always return `ShareResultStatus.unavailable` because `Intent.EXTRA_CHOSEN_COMPONENT` is not supported by the OS.