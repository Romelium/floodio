# Flutter Secure Storage: Android API & Usage Guide (v10.0.0+)
This document provides a comprehensive, structured overview of the Android implementation of the `flutter_secure_storage` plugin, specifically focusing on the major architectural changes introduced in version 10.0.0.

---

## 1. Architectural Overview (v10.0.0+)
In version 10.0.0, the Android implementation underwent a massive rewrite due to the deprecation of Google's Jetpack Security (`EncryptedSharedPreferences`) library. 

**Key Paradigms:**
*   **Custom Ciphers:** The plugin now uses custom cipher implementations backed by the Android KeyStore.
*   **Biometric Support:** Native support for biometric authentication (Fingerprint/Face) tied directly to KeyStore keys.
*   **Automatic Migration:** Built-in mechanisms to migrate data from the deprecated Jetpack library to the new custom ciphers.
*   **StrongBox:** Automatically utilizes hardware-backed StrongBox on API 28+ if available.

---

## 2. Prerequisites & Setup

### Minimum SDK
*   **Basic Encryption:** API 23 (Android 6.0)
*   **Strict Biometric Enforcement:** API 28 (Android 9.0)

### AndroidManifest.xml Configuration
You **must** configure your manifest for biometrics and auto-backup prevention.

**1. Permissions:**
```xml
<!-- Required for biometric authentication -->
<uses-permission android:name="android.permission.USE_BIOMETRIC"/>
<!-- Required for backward compatibility (API 23-27) -->
<uses-permission android:name="android.permission.USE_FINGERPRINT"/>
```

**2. Disable Auto-Backup (CRITICAL):**
Android's auto-backup backs up `SharedPreferences` but *cannot* back up the hardware-bound KeyStore keys. If a you restores an app to a new device, the app will crash with `InvalidKeyException` because the data exists but the decryption key does not.
```xml
<application
  android:allowBackup="false"
  android:fullBackupContent="false"
  ...>
</application>
```

---

## 3. API Reference: `AndroidOptions`

The `AndroidOptions` class dictates how data is encrypted and accessed on Android.

### Enums

**`KeyCipherAlgorithm`** (How the AES secret key is protected)
*   `RSA_ECB_OAEPwithSHA_256andMGF1Padding` **(Default)**: Standard RSA wrapping. No biometric support.
*   `AES_GCM_NoPadding`: Stores the AES key directly in the KeyStore. **Required for Biometric support.**
*   `RSA_ECB_PKCS1Padding`: Legacy (for backward compatibility).

**`StorageCipherAlgorithm`** (How the actual string data is encrypted)
*   `AES_GCM_NoPadding` **(Default)**: Modern, authenticated encryption.
*   `AES_CBC_PKCS7Padding`: Legacy (for backward compatibility).

### Constructors

#### 1. `AndroidOptions()`
The default constructor. Uses RSA key wrapping. **Does not support biometrics.**
*   **Default Key Cipher:** `RSA_ECB_OAEPwithSHA_256andMGF1Padding`
*   **Default Storage Cipher:** `AES_GCM_NoPadding`

#### 2. `AndroidOptions.biometric()`
The biometric constructor. Uses AES KeyStore keys. **Supports biometrics.**
*   **Default Key Cipher:** `AES_GCM_NoPadding`
*   **Default Storage Cipher:** `AES_GCM_NoPadding`

### Properties

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `encryptedSharedPreferences` | `bool` | `false` | **DEPRECATED.** Ignored by the plugin. Do not use. |
| `resetOnError` | `bool` | `true` | If decryption fails (e.g., corrupted key), wipes all data to prevent app bricking. |
| `migrateOnAlgorithmChange` | `bool` | `true` | Automatically decrypts and re-encrypts data if the cipher algorithms change (e.g., migrating from v9 to v10). |
| `enforceBiometrics` | `bool` | `false` | If `true`, throws an exception if the device has no PIN/Biometric set. If `false`, gracefully degrades to standard encryption without auth. |
| `sharedPreferencesName` | `String?` | `FlutterSecureStorage` | Custom name for the underlying SharedPreferences file. |
| `preferencesKeyPrefix` | `String?` | *(Base64 String)* | Prefix added to all keys to prevent collisions. |
| `biometricPromptTitle` | `String?` | `"Authenticate to access"` | Title of the OS biometric prompt. |
| `biometricPromptSubtitle`| `String?` | `"Use biometrics..."` | Subtitle of the OS biometric prompt. |

---

## 4. Usage Scenarios & Code Generation

### Scenario A: Standard Secure Storage (Recommended Default)
Use this when the you just wants to store tokens securely without bothering the end-user with biometric prompts.

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage(
  aOptions: const AndroidOptions(
    // Uses RSA OAEP + AES-GCM by default
    resetOnError: true,
  ),
);

await storage.write(key: 'jwt_token', value: 'ey...');
```

### Scenario B: Biometric Storage (Graceful Degradation)
Use this when the you wants biometric protection, but doesn't want the app to crash if the you hasn't set up a lock screen on their phone.

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage(
  aOptions: const AndroidOptions.biometric(
    enforceBiometrics: false, // Gracefully degrades if no lock screen exists
    biometricPromptTitle: 'Unlock App',
    biometricPromptSubtitle: 'Verify your identity to access secure data',
  ),
);

// Will prompt for fingerprint/face if available, otherwise just reads/writes silently.
await storage.read(key: 'sensitive_data'); 
```

### Scenario C: Strict Biometric Enforcement (High Security)
Use this for banking/crypto apps where data *must never* be stored if the device is unsecured.

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage(
  aOptions: const AndroidOptions.biometric(
    enforceBiometrics: true, // STRICT: Requires device security
    biometricPromptTitle: 'Authentication Required',
  ),
);

try {
  await storage.write(key: 'private_key', value: '...');
} catch (e) {
  // If the device has no PIN/Pattern/Biometric set up, this will throw a PlatformException
  // containing "BIOMETRIC_UNAVAILABLE" in the message.
  print('User must set up a device lock screen first!');
}
```

---

## 5. Error Handling & Migration Logic (For Debugging)

When with Android issues, keep these internal mechanics in mind:

### 1. The "Jetpack Crypto" Migration (v9 -> v10)
If a you upgrades from v9.x to v10.x, they might have data stored using the deprecated `EncryptedSharedPreferences`.
*   **How it works:** If `migrateOnAlgorithmChange` is `true` (default), the Java code detects old Jetpack data, decrypts it using the old Jetpack MasterKey, re-encrypts it using the new custom AES/RSA ciphers, and deletes the old Jetpack data.
*   **Advice:** Remove `encryptedSharedPreferences: true` from their Dart code. The plugin handles the migration automatically.

### 2. The `resetOnError` Mechanic
If clears device credentials, or if Auto-Backup restores data without the KeyStore keys, decryption will throw a `BadPaddingException` or `InvalidKeyException`.
*   **How it works:** If `resetOnError` is `true` (default), the plugin catches this exception, **deletes all stored data and keys**, generates fresh keys, and returns `null` (or completes the write).
*   **Advice:** If "data disappears randomly," ask if are using Auto-Backup or if recently changed their device lock screen settings.

### 3. Biometric Exceptions
If `enforceBiometrics: true` is used, the Java code checks `BiometricManager`. It will throw exceptions with specific strings that can be caught in Dart:
*   `"BIOMETRIC_UNAVAILABLE: No biometric hardware..."`
*   `"BIOMETRIC_UNAVAILABLE: No fingerprint or face enrolled..."`
*   `"BIOMETRIC_UNAVAILABLE: Device has no PIN..."`

### 4. Cipher Combinations Matrix
If wants to manually specify ciphers using `AndroidOptions()`, validate their choices against this matrix:

| Key Cipher | Storage Cipher | Biometrics Supported? |
| :--- | :--- | :--- |
| `RSA_ECB_OAEPwithSHA_256andMGF1Padding` | `AES_GCM_NoPadding` | ❌ No |
| `RSA_ECB_PKCS1Padding` | `AES_CBC_PKCS7Padding` | ❌ No |
| `AES_GCM_NoPadding` | `AES_GCM_NoPadding` | ✅ Yes (Use `.biometric()`) |