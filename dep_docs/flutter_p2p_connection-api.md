# Context & Usage Document: `flutter_p2p_connection`

## 1. High-Level Architecture & Concepts
This plugin enables offline Peer-to-Peer (P2P) communication between devices.
*   **Supported Platforms:** **Android ONLY** (iOS/Desktop not currently supported).
*   **Discovery Layer (BLE):** Uses Bluetooth Low Energy. The Host acts as a GATT Server advertising a custom service. The Client scans for this service, connects, and reads the Wi-Fi SSID and PSK (Pre-Shared Key) from GATT characteristics.
*   **Network Layer (Wi-Fi Direct):** Uses Android's `LocalOnlyHotspot` (API 26+) or legacy Wi-Fi configurations to create a local network.
*   **Transport Layer (WebSockets & HTTP):** 
    *   **Signaling/Text:** A WebSocket server runs on the Host. Clients connect to it. Used for text messages, client lists, and file metadata.
    *   **File Transfer:** **Both** Host and Client run local HTTP servers (`HttpServer`). When a device shares a file, it sends metadata via WebSocket. The receiving device uses `http.Client` to download the file directly from the sender's HTTP server using byte-range requests (supports resuming).

## 2. Android Setup Requirements
When generating code, ensure to have the following in `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Internet for WebSocket/HTTP communication -->
<uses-permission android:name="android.permission.INTERNET" />
<!-- Storage -->
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" />
<!-- Location (Required for Wi-Fi/BLE scanning on Android) -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<!-- Nearby Devices (Android 13+) -->
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES" android:usesPermissionFlags="neverForLocation" tools:targetApi="tiramisu" />
<!-- Wi-Fi -->
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<!-- Bluetooth (Legacy) -->
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<!-- Bluetooth (Android 12+) -->
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" tools:targetApi="s" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" tools:targetApi="s" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" tools:targetApi="s" />
<!-- Hardware Features -->
<uses-feature android:name="android.hardware.wifi" android:required="true" />
<uses-feature android:name="android.hardware.bluetooth" android:required="true" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

---

## 3. Core API Reference

### 3.1 Shared Base (`FlutterP2pConnectionBase`)
Both `FlutterP2pHost` and `FlutterP2pClient` inherit these utility methods for permissions and services.
*   **Permissions:**
    *   `Future<bool> checkP2pPermissions()` / `askP2pPermissions()`
    *   `Future<bool> checkBluetoothPermissions()` / `askBluetoothPermissions()`
    *   `Future<bool> checkStoragePermission()` / `askStoragePermission()`
*   **Services (Hardware Toggles):**
    *   `Future<bool> checkLocationEnabled()` / `enableLocationServices()`
    *   `Future<bool> checkWifiEnabled()` / `enableWifiServices()`
    *   `Future<bool> checkBluetoothEnabled()` / `enableBluetoothServices()`

### 3.2 Host API (`FlutterP2pHost`)
Used by the device creating the network.
*   **Instantiation:**
    *   `FlutterP2pHost({String? serviceUuid, bool? bondingRequired, bool? encryptionRequired, String? username})`
*   **Lifecycle:**
    *   `Future<void> initialize()` *(Note: Configuration is passed in the constructor, not here)*
    *   `Future<void> dispose()`
*   **Network Management:**
    *   `Future<HotspotHostState> createGroup({bool advertise = true, Duration timeout = const Duration(seconds: 60)})`: Creates Wi-Fi hotspot, starts WebSocket/HTTP servers, and optionally advertises via BLE.
    *   `Future<void> removeGroup()`: Tears down network and servers.
*   **Data Transfer:**
    *   `Future<void> broadcastText(String text, {List<String>? excludeClientIds})`
    *   `Future<bool> sendTextToClient(String text, String clientId)`
    *   `Future<P2pFileInfo?> broadcastFile(File file, {List<String>? excludeClientIds})`
    *   `Future<P2pFileInfo?> sendFileToClient(File file, String clientId)`
    *   `Future<bool> downloadFile(String fileId, String saveDirectory, {String? customFileName, bool? deleteOnError, Function(FileDownloadProgressUpdate)? onProgress, int? rangeStart, int? rangeEnd})`
*   **Streams (State & Data):**
    *   `Stream<HotspotHostState> streamHotspotState()`
    *   `Stream<List<P2pClientInfo>> streamClientList()`
    *   `Stream<String> streamReceivedTexts()`
    *   `Stream<List<HostedFileInfo>> streamSentFilesInfo()`
    *   `Stream<List<ReceivableFileInfo>> streamReceivedFilesInfo()`

### 3.3 Client API (`FlutterP2pClient`)
Used by devices joining the network.
*   **Instantiation:**
    *   `FlutterP2pClient({String? serviceUuid, bool? bondingRequired, bool? encryptionRequired, String? username})`
*   **Lifecycle:**
    *   `Future<void> initialize()`
    *   `Future<void> dispose()`
*   **Discovery & Connection:**
    *   `Future<StreamSubscription<List<BleDiscoveredDevice>>> startScan(void Function(List<BleDiscoveredDevice>)? onData, {Function? onError, void Function()? onDone, bool? cancelOnError, Duration timeout = const Duration(seconds: 15)})`
    *   `Future<void> stopScan()`
    *   `Future<void> connectWithDevice(BleDiscoveredDevice device, {Duration timeout = const Duration(seconds: 20)})`: Connects via BLE, gets credentials, connects to Wi-Fi, connects to WebSocket.
    *   `Future<void> connectWithCredentials(String ssid, String psk, {Duration timeout = const Duration(seconds: 60)})`: Manual connection (e.g., via QR code).
    *   `Future<void> disconnect()`
*   **Data Transfer:** Same signatures as Host (`broadcastText`, `sendFileToClient`, `downloadFile`, etc.)
*   **Streams (State & Data):**
    *   `Stream<HotspotClientState> streamHotspotState()`
    *   *(All other streams are identical to Host)*

---

## 4. Data Models

*   **`HotspotHostState`**: `{ bool isActive, String? ssid, String? preSharedKey, String? hostIpAddress, int? failureReason }`
*   **`HotspotClientState`**: `{ bool isActive, String? hostSsid, String? hostGatewayIpAddress, String? hostIpAddress }`
*   **`BleDiscoveredDevice`**: `{ String deviceAddress, String deviceName }`
*   **`P2pClientInfo`**: `{ String id, String username, bool isHost }`
*   **`ReceivableFileInfo`**: Represents a file available to download. Contains `P2pFileInfo info`, `ReceivableFileState state` (idle, downloading, completed, error), `double downloadProgressPercent`, and `String? savePath`.
*   **`HostedFileInfo`**: Represents a file currently being served by this device. Contains `P2pFileInfo info`, `String localPath`, and `List<String> recipientIds`.
*   **`FileDownloadProgressUpdate`**: `{ String fileId, double progressPercent, int bytesDownloaded, int totalSize, String savePath }`

---

## 5. Standard Implementation Workflows 

### Workflow 1: Host Initialization & Group Creation
```dart
// Configuration (like serviceUuid) is passed to the constructor
final host = FlutterP2pHost(
  username: "Player 1",
  serviceUuid: "0f0540bd-4a04-46d0-b90d-b0447453ec3a", // Optional custom UUID
);

Future<void> startHosting() async {
  await host.initialize(); // No arguments here
  
  // 1. Check Permissions & Services (Crucial step)
  if (!await host.checkP2pPermissions()) await host.askP2pPermissions();
  if (!await host.checkBluetoothPermissions()) await host.askBluetoothPermissions();
  if (!await host.checkLocationEnabled()) await host.enableLocationServices();
  if (!await host.checkWifiEnabled()) await host.enableWifiServices();

  // 2. Listen to state
  host.streamHotspotState().listen((state) {
    if (state.isActive) {
      print("Hotspot Active! SSID: ${state.ssid}, PSK: ${state.preSharedKey}");
    }
  });

  // 3. Create Group (Advertises via BLE automatically)
  try {
    await host.createGroup(advertise: true);
  } catch (e) {
    print("Failed to create group: $e");
  }
}
```

### Workflow 2: Client Discovery & Connection
```dart
// Configuration must match the Host if using custom UUIDs
final client = FlutterP2pClient(
  username: "Player 2",
  serviceUuid: "0f0540bd-4a04-46d0-b90d-b0447453ec3a", 
);

Future<void> joinNetwork() async {
  await client.initialize(); // No arguments here
  
  // 1. Check Permissions & Services (Same as Host)
  // ... permission checks ...

  // 2. Start BLE Scan
  await client.startScan((devices) async {
    if (devices.isNotEmpty) {
      final targetDevice = devices.first;
      await client.stopScan(); // Stop scanning before connecting
      
      // 3. Connect to Device
      try {
        await client.connectWithDevice(targetDevice);
        print("Connected successfully!");
      } catch (e) {
        print("Connection failed: $e");
      }
    }
  });
}
```

### Workflow 3: File Transfer (Sending & Receiving)
```dart
// SENDING (Works on both Host and Client)
Future<void> sendAFile(File myFile) async {
  // Broadcast to everyone
  await p2pInstance.broadcastFile(myFile);
  
  // OR send to specific client
  // await p2pInstance.sendFileToClient(myFile, "client_id_here");
}

// RECEIVING (Works on both Host and Client)
void setupFileReceiver() {
  p2pInstance.streamReceivedFilesInfo().listen((receivableFiles) {
    for (var file in receivableFiles) {
      if (file.state == ReceivableFileState.idle) {
        // Automatically start download when a file is announced
        p2pInstance.downloadFile(
          file.info.id,
          '/storage/emulated/0/Download/', // Ensure storage permissions!
          onProgress: (progress) {
            print("Downloading ${file.info.name}: ${progress.progressPercent}%");
          }
        ).then((success) {
          print(success ? "Download complete!" : "Download failed.");
        });
      }
    }
  });
}
```

---

## 6. Generation Rules & Caveats

1.  **Constructor vs Initialize:** `serviceUuid`, `bondingRequired`, `encryptionRequired`, and `username` are passed to the **constructor** of `FlutterP2pHost` or `FlutterP2pClient`. The `initialize()` method takes no arguments.
2.  **Always enforce permission checks:** Before calling `createGroup`, `startScan`, or `connectWithDevice`, generate code that checks and requests P2P, Bluetooth, and Location permissions.
3.  **Always enforce service checks:** Ensure Wi-Fi, Bluetooth, and Location hardware are turned on using the provided `check...Enabled()` and `enable...Services()` methods.
4.  **Android Only:** If asked for iOS support, this plugin relies on Android's `WifiManager.LocalOnlyHotspot` and Wi-Fi Direct APIs, which do not have direct equivalents on iOS.
5.  **File Paths:** When generating file download code, use standard Android paths (e.g., `/storage/emulated/0/Download/`) or use the `path_provider` package. Remind yourself about Android Scoped Storage rules.
6.  **Initialization:** `initialize()` MUST be called before any other method on `FlutterP2pHost` or `FlutterP2pClient`.
7.  **Disposal:** Always generate a `dispose()` method in `StatefulWidget`s to call `host.dispose()` or `client.dispose()` to prevent memory leaks and lingering native network configurations.