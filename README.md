# Floodio (Temporary Name)

An Android application that is essentially an offline resilient disaster information hub that centralizes critical crisis information such as emergency news, evacuation areas, and hazard markers, and then conveys this information through an battery friendly and efficient, "store and forward" network. In times of network failure, users who are temporarily able to access the internet will function as "mules" to send information to other users who are currently offline through device syncing (per 5 minutes or manual) via automatic Bluetooth Low Energy and Wi-Fi Direct (News, areas, markers, offline maps, images, files) when they encounter each other. In order to stop false information from being disseminated during network failures, this application will utilize a "four-tier trust model" to filter users into Official, Admin-Trusted, Personally-Trusted, and Crowdsourced categories to prioritize verified information over unverified information.

**Note on P2P Syncing:** The terms "Host" and "Client" in the app only refer to how the Wi-Fi Direct connection is established. Once connected, data synchronization is fully **bidirectional**—both devices share and receive missing reports, maps, and files equally.

## 1. Prerequisites tools and libraries installed on your system:
*   **Flutter SDK** (Version 3.38.4 or higher, as specified in your `pubspec.yaml`).
*   **Protocol Buffers Compiler (`protoc`)**: This is used to compile your `.proto` files. 
    *   *Mac:* `brew install protobuf`
    *   *Linux:* `sudo apt install protobuf-compiler`
    *   *Windows:* Download from the [Protobuf GitHub releases](https://github.com/protocolbuffers/protobuf/releases) and add it to your PATH.
*   **A Physical Android Device**: Connected to your computer with **USB Debugging enabled**.

## 2. Install Dependencies
Open your terminal and navigate to the project directory and run:
```bash
flutter pub get
```

## 3. Generate / Regenerate Code (Protobuf, Riverpod, & Drift)
You must generate code for the local database (`drift`), state management (`riverpod`), and data models (`protobuf`) before running the app for the first time, **and whenever you modify `.proto` files or files annotated with `@riverpod` / `@DriftDatabase`**.

Since you have a `Makefile`, simply run:
```bash
make generate
```

*(If you are on Windows or don’t have `make` installed, run these three commands manually):*
```bash
mkdir -p lib/protos
protoc --dart_out=lib/protos -Iprotos protos/models.proto

# To build once:
dart run build_runner build --delete-conflicting-outputs

# Or to watch for changes continuously:
# dart run build_runner watch --delete-conflicting-outputs
```

## 4. Run the Application
Once the generated files are built and your device is listed in the connected devices, build and run the application in a seperate terminal:
```bash
flutter run
```
