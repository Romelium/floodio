# Floodio (Temporary Name)

An Android application that is essentially an offline resilient disaster information hub that centralizes critical crisis information such as emergency news, evacuation areas, and hazard markers, and then conveys this information through an battery friendly and efficient, "store and forward" network. In times of network failure, users who are temporarily able to access the internet will function as "mules" to send information to other users who are currently offline through device syncing (per 5 minutes or manual) via automatic Bluetooth Low Energy (News, areas, markers) and manual Wi-Fi Direct (offline maps, images, files) when they encounter each other. In order to stop false information from being disseminated during network failures, this application will utilize a "four-tier trust model" to filter users into Official, Admin-Trusted, Personally-Trusted, and Crowdsourced categories to prioritize verified information over unverified information.

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

## 3. Generate Code (Protobuf, Riverpod, & Drift)
You must generate code for the local database (`drift`), state management (`riverpod`), and data models (`protobuf`).

Since you have a `Makefile`, simply run:
```bash
make generate
```

*(If you are on Windows or don’t have `make` installed, run these three commands manually):*
```bash
mkdir -p lib/protos
protoc --dart_out=lib/protos -Iprotos protos/models.proto
dart run build_runner build --delete-conflicting-outputs
```

## 4. Run the Application
Once your device is listed in the connected devices, build and run the application:
```bash
flutter run
```
