### **PoC Scope & Success Criteria**
The PoC will **not** be a fully polished app. It will focus on proving the riskiest technical assumptions:
1.  **Device A** creates a "Hazard Marker" offline.
2.  **Device A** cryptographically signs it (Trust Model).
3.  **Device A** automatically discovers **Device B** via BLE.
4.  **Devices A & B** automatically upgrade to a Wi-Fi Direct connection to sync the data.
5.  **Device B** verifies the signature, displays the marker, and successfully receives a larger file (e.g., an offline map tile).

---

### **Phase 1: Architecture & Foundation (Week 1)**
**Goal:** Set up the Flutter project, state management, and local database.

*   **Tech Stack Selection:**
    *   **State Management:** `flutter_riverpod` (ideal for handling asynchronous network states).
    *   **Local Database:** `drift` (SQLite - highly reactive, pairs perfectly with Riverpod).
    *   **Serialization:** `protobuf` (Protocol Buffers to keep payloads tiny and efficient).
*   **Tasks:**
    1.  Initialize the Flutter project (target: Android).
    2.  Define the Protobuf schemas (`.proto` files) for `HazardMarker`, `NewsItem`, and `SyncManifest`.
    3.  Set up the Drift database to store these items, including metadata like `timestamp`, `senderId`, `trustTier`, and `signature`.

### **Phase 2: The Four-Tier Trust Model (Week 2)**
**Goal:** Implement local cryptography to prove data authenticity without the internet.

*   **Tech Stack:** `cryptography` package (supports Ed25519 digital signatures).
*   **Tasks:**
    1.  **Key Generation:** On app install, generate an Ed25519 public/private key pair for the user.
    2.  **Tier 1 & 2 (Official/Admin):** Hardcode a "Server Public Key" into the app. Create a script to sign a dummy "Official News Alert" with the Server Private Key.
    3.  **Tier 3 (Personally-Trusted):** Build a UI mechanism to manually mark a sender as "Trusted" directly from their messages, saving their Public Key to a local SQLite table.
    4.  **Verification Logic:** Write a utility class that intercepts incoming data. If the signature matches the Server Key -> Tag as *Official*. If it matches a saved key in the trusted list -> Tag as *Personally-Trusted*. Otherwise -> Tag as *Crowdsourced*.

### **Phase 3: P2P Networking & Auto-Discovery (Weeks 3 & 4)**
**Goal:** Establish device-to-device communication using BLE for *discovery* and Wi-Fi Direct for *transfer*.

*   **Tech Stack:** `flutter_p2p_connection`, `permission_handler`. *(Note: `flutter_p2p_connection` handles the BLE discovery and Wi-Fi Direct handoff under the hood, eliminating the need for manual GATT server management).*
*   **Tasks:**
    1.  **Strict Permissions:** Implement robust permission requests. For Android 12+, you **must** request `BLUETOOTH_ADVERTISE`, `BLUETOOTH_SCAN`, and `BLUETOOTH_CONNECT`. For Android 13+, you **must** request `NEARBY_WIFI_DEVICES`.
    2.  **The "BLE-to-Wi-Fi Upgrade" Auto-Sync:**
        *   **The Host (Device A):** Uses `flutter_p2p_connection` to call `createGroup(advertise: true)`. This creates a Wi-Fi Direct hotspot AND automatically advertises its presence via BLE.
        *   **The Client (Device B):** Uses `startScan()` to scan for nearby BLE devices advertising this specific P2P service.
        *   **The Connection:** When Device B discovers Device A, it calls `connectWithDevice()`. The plugin automatically passes the Wi-Fi credentials over BLE and connects them via Wi-Fi Direct.
    3.  **Data Transfer:** Once connected via Wi-Fi, use the plugin's WebSocket (`broadcastText`) to exchange Protobuf payloads, and the HTTP server (`broadcastFile`) to transfer a dummy 5MB offline map tile.

### **Phase 4: Store, Forward & Sync Logic (Week 5)**
**Goal:** Implement the "Data Mule" logic to prevent infinite loops and network flooding.

*   **Tasks:**
    1.  **The Sync Handshake (High-Water Marks):** When Device A and B connect, they shouldn't send everything. They first exchange a lightweight `SyncManifest` (e.g., "I have Official news up to Timestamp X, and Crowdsourced news up to Timestamp Y").
    2.  **Delta Sync:** Device A compares the manifest and sends *only* the Protobuf payloads that Device B is missing.
    3.  **Loop Prevention:** Instead of sending a massive list of every `message_id` ever seen, use the Timestamp High-Water Mark approach or implement a simple **Bloom Filter** to quickly check if a device already has a specific payload before transmitting it.

### **Phase 5: UI & Field Testing (Week 6)**
**Goal:** Build a functional interface to visualize the data and test with physical devices.

*   **Tech Stack:** `flutter_map` (for offline vector/raster maps).
*   **Tasks:**
    1.  **Map UI:** Implement a basic map. For the PoC, cache a small bounding box of OpenStreetMap tiles locally.
    2.  **Feed UI:** A simple list view showing News and Hazards, color-coded by Trust Tier (e.g., Blue = Official, Green = Trusted, Grey = Crowdsourced). Riverpod will automatically update this UI as Drift processes incoming syncs.
    3.  **Field Test:** 
        *   Install the APK on 3 physical Android phones.
        *   Turn on Airplane Mode (turn Bluetooth/Wi-Fi back on, but no internet).
        *   Phone A creates a hazard. Phone A walks to Phone B (auto-syncs). Phone B walks to Phone C (auto-syncs). 
        *   Verify Phone C sees Phone A's hazard and verifies the signature.

---

### **Crucial Flutter-Specific Advice for this Project**

1.  **Do Not Use Emulators for Networking:** Emulators do not support BLE or Wi-Fi Direct properly. You **must** develop and debug using at least two physical Android devices connected via USB or Wireless Debugging.
2.  **Why We Avoided Pure BLE Data Transfer:** BLE characteristics have strict MTU limits (typically 23 to 512 bytes). A signed Hazard Marker (ID, Lat, Lng, Type, Timestamp, PubKey, 64-byte Signature) pushes this limit, and chunking data over BLE in Flutter is highly unstable. The "BLE-to-Wi-Fi Upgrade" pattern solves this elegantly.
3.  **Background Execution (Post-PoC):** Flutter pauses Dart code execution when the app is minimized. For the PoC, test with the screens *on*. For production, you will use `flutter_background_service`. **Note:** Android 14 (SDK 34) requires you to declare a specific `foregroundServiceType` in your `AndroidManifest.xml` (e.g., `dataSync` or `connectedDevice`) for the background service to run legally.