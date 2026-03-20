While native Android (Kotlin) is traditionally preferred for deep background hardware access, building this Proof of Concept (PoC) in **Flutter** is entirely possible and will drastically speed up your UI development. 

To overcome Flutter's hardware limitations, we will rely heavily on the **Google Nearby Connections API** (via the `nearby_connections` Flutter package), which abstracts the complex switching between BLE and Wi-Fi Direct into a single, manageable API.

Here is a **6-Week Development Plan** to build a functional PoC for Android using Flutter.

---

### **PoC Scope & Success Criteria**
The PoC will **not** be a fully polished app. It will focus on proving the riskiest technical assumptions:
1.  **Device A** creates a "Hazard Marker" offline.
2.  **Device A** cryptographically signs it (Trust Model).
3.  **Device A** automatically discovers **Device B** via BLE and syncs the data.
4.  **Device B** verifies the signature and displays the marker.
5.  **Device B** connects to **Device C** via Wi-Fi Direct to transfer a larger file (e.g., an offline map tile).

---

### **Phase 1: Architecture & Foundation (Week 1)**
**Goal:** Set up the Flutter project, state management, and local database.

*   **Tech Stack Selection:**
    *   **State Management:** `flutter_riverpod` (ideal for handling asynchronous network states).
    *   **Local Database:** `isar` or `drift` (SQLite).
    *   **Serialization:** `protobuf` (Protocol Buffers to keep BLE payloads tiny).
*   **Tasks:**
    1.  Initialize the Flutter project (target: Android).
    2.  Define the Protobuf schemas (`.proto` files) for `HazardMarker`, `NewsItem`, and `SyncPayload`.
    3.  Set up the local database to store these items, including metadata like `timestamp`, `senderId`, and `signature`.

### **Phase 2: The Four-Tier Trust Model (Week 2)**
**Goal:** Implement local cryptography to prove data authenticity without the internet.

*   **Tech Stack:** `cryptography` package (supports Ed25519 digital signatures).
*   **Tasks:**
    1.  **Key Generation:** On app install, generate a public/private key pair for the user.
    2.  **Tier 1 & 2 (Official/Admin):** Hardcode a "Server Public Key" into the app. Create a script to sign a dummy "Official News Alert" with the Server Private Key.
    3.  **Tier 3 (Personally-Trusted):** Build a simple QR code generator/scanner (`mobile_scanner` package) so two phones can scan each other's Public Keys.
    4.  **Verification Logic:** Write a utility class that intercepts incoming data. If the signature matches the Server Key -> Tag as *Official*. If it matches a scanned key -> Tag as *Personally-Trusted*. Otherwise -> Tag as *Crowdsourced*.

### **Phase 3: P2P Networking (Weeks 3 & 4)**
**Goal:** Establish device-to-device communication. *This is the most challenging phase.*

*   **Tech Stack:** `nearby_connections` package.
*   **Tasks:**
    1.  **Permissions:** Implement robust permission requests (Location, Bluetooth Scan/Connect/Advertise, Nearby Wi-Fi Devices). Use the `permission_handler` package.
    2.  **Strategy Configuration:** 
        *   Use `Strategy.P2P_CLUSTER` (allows a device to connect to multiple devices simultaneously, creating a mesh-like topology).
    3.  **BLE Auto-Sync (Background/Foreground):**
        *   Set up the app to continuously *Advertise* and *Discover*.
        *   When a device is found, automatically request a connection.
        *   *Note for PoC:* Keep the app in the foreground to avoid Android's Doze mode for now. Background execution can be tackled post-PoC using `flutter_background_service`.
    4.  **Wi-Fi Direct Manual Sync:**
        *   Create a UI button: "Send Offline Map".
        *   Use `Strategy.P2P_STAR` (high bandwidth) to send a dummy 5MB file to a connected peer.

### **Phase 4: Store, Forward & Sync Logic (Week 5)**
**Goal:** Implement the "Data Mule" logic to prevent infinite loops and network flooding.

*   **Tasks:**
    1.  **The Sync Handshake:** When Device A and B connect, they shouldn't send *everything*. They should first exchange a lightweight "Manifest" (e.g., "I have messages up to timestamp X").
    2.  **Delta Sync:** Device A sends only the Protobuf payloads that Device B is missing.
    3.  **Loop Prevention:** Maintain a `seen_message_ids` table in the database. If Device B receives a message ID it already has, it drops it.
    4.  **Time-To-Live (TTL):** Write a background worker that deletes "Crowdsourced" data older than 24 hours to save storage.

### **Phase 5: UI & Field Testing (Week 6)**
**Goal:** Build a functional interface to visualize the data and test with physical devices.

*   **Tech Stack:** `flutter_map` (for offline vector/raster maps).
*   **Tasks:**
    1.  **Map UI:** Implement a basic map. For the PoC, you can cache a small bounding box of OpenStreetMap tiles locally.
    2.  **Feed UI:** A simple list view showing News and Hazards, color-coded by Trust Tier (e.g., Blue = Official, Green = Trusted, Grey = Crowdsourced).
    3.  **Field Test:** 
        *   Install the APK on 3 physical Android phones.
        *   Turn on Airplane Mode (turn Bluetooth/Wi-Fi back on, but no internet).
        *   Phone A creates a hazard. Phone A walks to Phone B (syncs). Phone B walks to Phone C (syncs). 
        *   Verify Phone C sees Phone A's hazard.

---

### **Crucial Flutter-Specific Advice for this Project**

1.  **Do Not Use Emulators for Networking:** Emulators do not support BLE or Wi-Fi Direct properly. You **must** develop and debug using at least two physical Android devices connected via USB or Wireless Debugging.
2.  **Background Execution:** Flutter pauses Dart code execution when the app is minimized. For the PoC, test with the screens *on*. For production, you will need to write a native Android Foreground Service (using Kotlin) that handles the `nearby_connections` logic and writes directly to the local database, waking up the Flutter UI only when necessary.
3.  **Payload Size:** The `nearby_connections` API `sendPayload` method has a `BYTES` payload type (max 32KB) which is sent over BLE/Bluetooth Classic, and a `FILE` payload type which automatically upgrades the connection to Wi-Fi Direct. Use `BYTES` for your 5-minute auto-syncs.