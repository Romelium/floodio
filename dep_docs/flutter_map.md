# 🗺️ `flutter_map` v8.2.2 - Developer Reference

## 1. 🚨 CRITICAL GUIDE (READ FIRST)
`flutter_map` underwent massive architectural changes between v5 and v8. **DO NOT** generate code using the following deprecated or removed APIs.

| ❌ OUTDATED / REMOVED API | ✅ MODERN v8.2.2 EQUIVALENT |
| :--- | :--- |
| `MapOptions(center: X, zoom: Y)` | `MapOptions(initialCenter: X, initialZoom: Y)` |
| `MapOptions(maxBounds: bounds)` | `MapOptions(cameraConstraint: CameraConstraint.contain(bounds: bounds))` |
| `MapOptions(interactiveFlags: X)` | `MapOptions(interactionOptions: InteractionOptions(flags: X))` |
| `Marker(builder: (ctx) => Widget)` | `Marker(child: Widget)` |
| `Marker(anchorPos: AnchorPos.align(...))` | `Marker(alignment: Alignment.topCenter)` |
| `TileLayer(tileSize: 256)` | `TileLayer(tileDimension: 256)` |
| `Polygon(labelPlacement: ...)` | `Polygon(labelPlacementCalculator: PolygonLabelPlacementCalculator.polylabel())` |
| `Polyline(isDotted: true)` | `Polyline(pattern: const StrokePattern.dotted())` |
| `Polyline(isDashed: true)` | `Polyline(pattern: const StrokePattern.dashed(segments: [20, 10]))` |
| `TileLayer(backgroundColor: ...)` | `MapOptions(backgroundColor: ...)` |
| *Using `cached_network_image` for tiles* | **Not needed.** `NetworkTileProvider` has built-in caching. |
| *Using `flutter_map_cancellable_tile_provider`* | **Not needed.** `NetworkTileProvider` aborts obsolete requests natively. |

---

## 2. Core Architecture & Setup

`flutter_map` uses a `Stack`-based architecture. The map is composed of a base `FlutterMap` widget containing a list of `children` (Layers) rendered from bottom to top.

**Required Dependencies:**
```yaml
dependencies:
  flutter_map: ^8.2.2
  latlong2: ^0.9.1 # Required for LatLng, Distance, and coordinate math
```

**Minimal Boilerplate:**
```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

FlutterMap(
  mapController: MapController(), // Optional
  options: const MapOptions(
    initialCenter: LatLng(51.509364, -0.128928),
    initialZoom: 9.2,
  ),
  children: [
    TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.app', // REQUIRED to avoid OSM blocks
    ),
    RichAttributionWidget(
      attributions: [TextSourceAttribution('OpenStreetMap contributors')],
    ),
  ],
)
```

---

## 3. Map Configuration (`MapOptions`)

`MapOptions` defines the immutable rules and initial state of the map.

### 3.1 Initial State & Constraints
*   `initialCenter`: `LatLng` (Default: `LatLng(50.5, 30.51)`).
*   `initialZoom`: `double` (Default: `13.0`).
*   `initialRotation`: `double` (Default: `0.0`).
*   `initialCameraFit`: `CameraFit?`. If provided, overrides center/zoom to fit specific bounds on load.
*   `minZoom` / `maxZoom`: `double?`. Absolute zoom limits.
*   `cameraConstraint`: `CameraConstraint`. Restricts panning.
    *   `CameraConstraint.unconstrained()` (Default)
    *   `CameraConstraint.contain(bounds: LatLngBounds(...))`
    *   `CameraConstraint.containCenter(bounds: LatLngBounds(...))`
    *   `CameraConstraint.containLatitude(90, -90)`
*   `crs`: `Crs` (Default: `Epsg3857()`). Coordinate Reference System.
*   `keepAlive`: `bool` (Default: `false`). Prevents map reset in `ListView`s.

### 3.2 Interactivity (`InteractionOptions`)
Controls gestures and keyboard/mouse inputs.
```dart
interactionOptions: const InteractionOptions(
  // Flags (bitwise operations supported)
  flags: InteractiveFlag.all & ~InteractiveFlag.rotate, 
  
  // Keyboard controls (Desktop/Web)
  keyboardOptions: KeyboardOptions(
    enableArrowKeysPanning: true,
    enableWASDPanning: true,
    enableQERotating: true,
    enableRFZooming: true,
  ),
  
  // Mouse rotation (Desktop/Web)
  cursorKeyboardRotationOptions: CursorKeyboardRotationOptions(),
)
```
*Available Flags:* `drag`, `flingAnimation`, `pinchMove`, `pinchZoom`, `doubleTapZoom`, `doubleTapDragZoom`, `scrollWheelZoom`, `rotate`, `all`, `none`.

### 3.3 Callbacks
*   `onTap(TapPosition tapPosition, LatLng point)`
*   `onSecondaryTap(TapPosition tapPosition, LatLng point)`
*   `onLongPress(TapPosition tapPosition, LatLng point)`
*   `onPositionChanged(MapCamera camera, bool hasGesture)`
*   `onMapEvent(MapEvent event)`
*   `onMapReady()`

---

## 4. Map Control & State

The architecture separates **mutation** (`MapController`) from **reading state** (`MapCamera`).

### 4.1 `MapController` (Mutation)
Used to programmatically move the map.
*   `move(LatLng center, double zoom, {Offset offset})`
*   `rotate(double degree)`
*   `rotateAroundPoint(double degree, {Offset? offset})`
*   `fitCamera(CameraFit cameraFit)`
    *   *Example:* `mapController.fitCamera(CameraFit.bounds(bounds: myBounds, padding: EdgeInsets.all(16)))`
*   `mapEventStream`: `Stream<MapEvent>` emitting pan, zoom, and rotation events.

### 4.2 `MapCamera` (Reading State)
Accessed via `mapController.camera` or `MapCamera.of(context)`.
*   **Properties:** `center`, `zoom`, `rotation`, `visibleBounds` (`LatLngBounds`), `pixelOrigin`, `nonRotatedSize`.
*   **Methods:**
    *   `latLngToScreenOffset(LatLng)`: Converts coordinate to screen `Offset`.
    *   `screenOffsetToLatLng(Offset)`: Converts screen `Offset` to `LatLng`.
    *   `projectAtZoom(LatLng)` / `unprojectAtZoom(Offset)`.

---

## 5. Layers API

Layers are rendered bottom-to-top in the `children` list.

### 5.1 `TileLayer`
Renders raster map tiles.
```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.app', // REQUIRED
  fallbackUrl: 'https://backup.server.com/{z}/{x}/{y}.png',
  tileDimension: 256,
  retinaMode: RetinaMode.isHighDensity(context), // For high-res displays
  tileProvider: NetworkTileProvider(), // Default. Has built-in caching & aborts obsolete requests.
  tileUpdateTransformer: TileUpdateTransformers.debounce(const Duration(milliseconds: 20)), // Throttles requests during fast pans
)
```

### 5.2 `MarkerLayer`
Renders Flutter widgets at geographic coordinates.
```dart
MarkerLayer(
  markers: [
    Marker(
      point: const LatLng(51.5, -0.09),
      width: 40,
      height: 40,
      alignment: Alignment.topCenter, // Pin points to the exact coordinate
      rotate: true, // Keeps marker upright when map rotates
      child: const Icon(Icons.location_pin, color: Colors.red, size: 40),
    ),
  ],
)
```

### 5.3 `PolylineLayer`
Renders lines (LineStrings).
```dart
PolylineLayer(
  polylines: [
    Polyline(
      points: [LatLng(51.5, -0.09), LatLng(53.34, -6.26)],
      color: Colors.blue,
      strokeWidth: 4.0,
      useStrokeWidthInMeter: false,
      // Patterns:
      // pattern: const StrokePattern.solid(),
      // pattern: const StrokePattern.dotted(spacingFactor: 1.5),
      pattern: const StrokePattern.dashed(segments: [20, 10]), 
    ),
  ],
)
```

### 5.4 `PolygonLayer`
Renders filled shapes.
```dart
PolygonLayer(
  // useAltRendering: true, // Optional: Use Canvas.drawVertices for complex polygons
  // invertedFill: Colors.black54, // Optional: Fills the outside of the polygons instead
  polygons: [
    Polygon(
      points: [LatLng(51.5, -0.09), LatLng(53.34, -6.26), LatLng(48.85, 2.35)],
      holePointsList: [ /* List of LatLng lists to cut out holes */ ],
      color: Colors.purple.withValues(alpha: 0.5),
      borderColor: Colors.yellow,
      borderStrokeWidth: 4,
      label: 'My Polygon',
      labelStyle: const TextStyle(color: Colors.white),
      // Label Placement Algorithms:
      // .centroid(), .simpleCentroid(), .simpleMultiWorldCentroid(), .polylabel()
      labelPlacementCalculator: const PolygonLabelPlacementCalculator.polylabel(),
    ),
  ],
)
```

### 5.5 `CircleLayer`
Renders circles.
```dart
CircleLayer(
  circles: [
    CircleMarker(
      point: const LatLng(51.5, -0.09),
      radius: 1000, // 1000 meters
      useRadiusInMeter: true, // If false, radius is in logical pixels
      color: Colors.green.withValues(alpha: 0.5),
      borderColor: Colors.black,
      borderStrokeWidth: 2,
    ),
  ],
)
```

### 5.6 `OverlayImageLayer`
Overlays an image stretched across geographic bounds.
```dart
OverlayImageLayer(
  overlayImages: [
    OverlayImage(
      bounds: LatLngBounds(LatLng(51.5, -0.09), LatLng(48.85, 2.35)),
      opacity: 0.8,
      imageProvider: const NetworkImage('https://example.com/image.jpg'),
    ),
    // RotatedOverlayImage is also available for skewed images requiring 3 corners
  ],
)
```

### 5.7 `Scalebar`
Displays a dynamic scale bar.
```dart
Scalebar(
  alignment: Alignment.bottomLeft,
  length: ScalebarLength.m,
)
```

---

## 6. Hit Detection (Tapping Vector Shapes)

`PolygonLayer`, `PolylineLayer`, and `CircleLayer` support hit detection.

**Implementation Pattern:**
```dart
// 1. Define a notifier in your StatefulWidget
final LayerHitNotifier<String> _hitNotifier = ValueNotifier(null);

// 2. Wrap the layer in a GestureDetector
GestureDetector(
  onTap: () {
    final hitResult = _hitNotifier.value;
    if (hitResult != null && hitResult.hitValues.isNotEmpty) {
      print('Tapped shape: ${hitResult.hitValues.first}');
      print('Geographic coordinate of tap: ${hitResult.coordinate}');
    }
  },
  child: PolygonLayer(
    hitNotifier: _hitNotifier, // 3. Pass the notifier to the layer
    polygons: [
      Polygon(
        hitValue: 'Zone A', // 4. Assign a hitValue to the shape
        points: [ /* ... */ ],
        color: Colors.blue,
      ),
    ],
  ),
)
```

---

## 7. Attribution

Most tile servers legally require attribution. Place this at the end of the `children` list.

**`RichAttributionWidget` (Modern, Collapsible):**
```dart
RichAttributionWidget(
  alignment: AttributionAlignment.bottomRight,
  animationConfig: const ScaleRAWA(), // Or FadeRAWA()
  attributions: [
    TextSourceAttribution(
      'OpenStreetMap contributors',
      onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
    ),
    LogoSourceAttribution(
      Image.asset('assets/mapbox-logo.png'),
      tooltip: 'Mapbox',
    ),
  ],
)
```

**`SimpleAttributionWidget` (Classic, Static):**
```dart
SimpleAttributionWidget(
  source: const Text('OpenStreetMap contributors'),
  onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
)
```

---

## 8. Advanced Features & Utilities

### 8.1 Multi-World Support (Infinite Panning)
By default, `flutter_map` repeats the map horizontally. If you draw a `Polyline` or `Polygon` that crosses the anti-meridian (180° / -180°), or if you want a shape to only appear in *one* specific world copy, use the `drawInSingleWorld` property.
```dart
PolygonLayer(
  drawInSingleWorld: true, // Prevents the polygon from repeating across infinite worlds
  polygons: [ ... ],
)
```

### 8.2 Custom Tile Builders (e.g., Dark Mode)
You can manipulate tiles as they render using `TileLayer.tileBuilder`.
```dart
TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.app',
  tileBuilder: (context, tileWidget, tile) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        -1,  0,  0, 0, 255, // Invert Red
         0, -1,  0, 0, 255, // Invert Green
         0,  0, -1, 0, 255, // Invert Blue
         0,  0,  0, 1,   0, // Alpha
      ]),
      child: tileWidget,
    );
  },
)
```

### 8.3 Calculating Bounds from Points
```dart
final points = [LatLng(51.5, -0.09), LatLng(48.85, 2.35)];
final bounds = LatLngBounds.fromPoints(points);

mapController.fitCamera(
  CameraFit.bounds(
    bounds: bounds,
    padding: const EdgeInsets.all(20),
  ),
);
```

---

# 🗺️ `flutter_map` API & Usage Documentation (v8.2.2)

## Table of Contents
1. [Getting Started](#1-getting-started)
2. [Core Components](#2-core-components)
   - [FlutterMap](#fluttermap)
   - [MapOptions](#mapoptions)
   - [MapController & MapCamera](#mapcontroller--mapcamera)
3. [Interactivity & Gestures](#3-interactivity--gestures)
4. [Layers API](#4-layers-api)
   - [TileLayer & Providers](#tilelayer)
   - [MarkerLayer](#markerlayer)
   - [PolylineLayer](#polylinelayer)
   - [PolygonLayer](#polygonlayer)
   - [CircleLayer](#circlelayer)
   - [OverlayImageLayer](#overlayimagelayer)
   - [Scalebar](#scalebar)
5. [Hit Detection (Tapping Shapes)](#5-hit-detection)
6. [Attribution](#6-attribution)
7. [Advanced Features](#7-advanced-features)

---

## 1. Getting Started

### Basic Boilerplate
```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

Widget buildMap() {
  return FlutterMap(
    options: const MapOptions(
      initialCenter: LatLng(51.509364, -0.128928), // London
      initialZoom: 9.2,
    ),
    children: [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.app', // REQUIRED
      ),
      RichAttributionWidget(
        attributions: [
          TextSourceAttribution('OpenStreetMap contributors'),
        ],
      ),
    ],
  );
}
```

---

## 2. Core Components

### `FlutterMap`
The root widget. It acts as a `Stack`, rendering `children` (Layers) from bottom to top.

| Property | Type | Description |
| :--- | :--- | :--- |
| `options` | `MapOptions` | Configures the map's initial state, constraints, and callbacks. |
| `children` | `List<Widget>` | The layers to render (e.g., `TileLayer`, `MarkerLayer`). |
| `mapController` | `MapController?` | Optional controller to programmatically move/rotate the map. |

### `MapOptions`
Defines the rules and initial state of the map.

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `initialCenter` | `LatLng` | `LatLng(50.5, 30.51)` | The starting coordinate. |
| `initialZoom` | `double` | `13.0` | The starting zoom level. |
| `initialRotation` | `double` | `0.0` | The starting rotation in degrees. |
| `initialCameraFit` | `CameraFit?` | `null` | Fits the camera to bounds/coordinates on load (overrides center/zoom). |
| `minZoom` / `maxZoom` | `double?` | `null` | Absolute zoom limits for the map. |
| `cameraConstraint` | `CameraConstraint` | `unconstrained()` | Restricts panning (e.g., `CameraConstraint.contain(bounds: ...)`). |
| `interactionOptions` | `InteractionOptions` | `InteractionOptions()` | Configures gestures, flags, and keyboard controls. |
| `keepAlive` | `bool` | `false` | Prevents the map from resetting when scrolled out of view in a `ListView`. |
| `crs` | `Crs` | `Epsg3857()` | Coordinate Reference System. |

**Callbacks:**
*   `onTap(TapPosition, LatLng)`
*   `onSecondaryTap(TapPosition, LatLng)`
*   `onLongPress(TapPosition, LatLng)`
*   `onPositionChanged(MapCamera, bool hasGesture)`
*   `onMapEvent(MapEvent)`
*   `onMapReady()`

### `MapController` & `MapCamera`
The `MapController` is used to mutate the map state, while the `MapCamera` reads the current state.

**`MapController` Methods:**
*   `move(LatLng center, double zoom, {Offset offset, String? id})`: Pans and zooms the map.
*   `rotate(double degree, {String? id})`: Rotates the map (0° is North).
*   `rotateAroundPoint(double degree, {Offset? offset})`: Rotates around a specific screen offset.
*   `fitCamera(CameraFit cameraFit)`: Adjusts the viewport to fit specific bounds.
    *   *Example:* `mapController.fitCamera(CameraFit.bounds(bounds: myBounds, padding: EdgeInsets.all(16)))`
*   `mapEventStream`: A `Stream<MapEvent>` emitting pan, zoom, and rotation events.

**`MapCamera` Properties/Methods:**
Accessed via `mapController.camera` or `MapCamera.of(context)`.
*   `center`, `zoom`, `rotation`, `visibleBounds`, `pixelOrigin`.
*   `latLngToScreenOffset(LatLng)`: Converts a coordinate to a screen `Offset`.
*   `screenOffsetToLatLng(Offset)`: Converts a screen `Offset` to a `LatLng`.

---

## 3. Interactivity & Gestures

Configured via `MapOptions.interactionOptions` using the `InteractionOptions` class.

### `InteractiveFlag`
Bitwise flags to enable/disable specific gestures.
```dart
InteractionOptions(
  // Enable all EXCEPT rotation
  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
)
```
*Available Flags:* `drag`, `flingAnimation`, `pinchMove`, `pinchZoom`, `doubleTapZoom`, `doubleTapDragZoom`, `scrollWheelZoom`, `rotate`, `all`, `none`.

### `KeyboardOptions` & `CursorKeyboardRotationOptions`
Allows desktop users to control the map with the keyboard.
```dart
InteractionOptions(
  keyboardOptions: const KeyboardOptions(
    enableArrowKeysPanning: true,
    enableWASDPanning: true,
    enableQERotating: true,
    enableRFZooming: true,
  ),
  cursorKeyboardRotationOptions: CursorKeyboardRotationOptions(
    isKeyTrigger: (key) => key == LogicalKeyboardKey.alt, // Hold Alt + Drag to rotate
  ),
)
```

---

## 4. Layers API

Layers are standard Flutter widgets placed in the `children` array. They are rendered bottom-to-top.

### `TileLayer`
Renders raster map tiles (PNG/JPG/WebP) from a server or local storage.

| Property | Type | Description |
| :--- | :--- | :--- |
| `urlTemplate` | `String?` | e.g., `'https://tile.openstreetmap.org/{z}/{x}/{y}.png'` |
| `userAgentPackageName` | `String` | **Required.** e.g., `'com.example.app'`. Prevents blocks from OSM. |
| `fallbackUrl` | `String?` | URL to use if the primary URL fails. Disables memory caching if set. |
| `tileDimension` | `int` | Size of tiles in pixels. Defaults to `256`. |
| `tileProvider` | `TileProvider` | Defaults to `NetworkTileProvider()`. |
| `retinaMode` | `bool?` | Set to `RetinaMode.isHighDensity(context)` to request `@2x` tiles or simulate them. |
| `wmsOptions` | `WMSTileLayerOptions?` | Configuration for WMS servers (mutually exclusive with `urlTemplate`). |
| `tileUpdateTransformer` | `TileUpdateTransformer` | Throttles/debounces tile requests. Defaults to `ignoreTapEvents`. |

**Tile Providers:**
*   `NetworkTileProvider()`: Default. Fetches from the web. Includes built-in caching (`BuiltInMapCachingProvider`) and aborts obsolete in-flight requests automatically.
*   `AssetTileProvider()`: Loads tiles from the `pubspec.yaml` assets.
*   `FileTileProvider()`: Loads tiles from the local device file system (Not supported on Web).

### `MarkerLayer`
Renders Flutter widgets at specific geographical coordinates.

```dart
MarkerLayer(
  markers: [
    Marker(
      point: const LatLng(51.5, -0.09),
      width: 40,
      height: 40,
      alignment: Alignment.topCenter, // Aligns the bottom of the widget to the coordinate
      rotate: true, // Counter-rotates to keep the marker upright when the map rotates
      child: const Icon(Icons.location_pin, size: 40, color: Colors.red),
    ),
  ],
)
```

### `PolylineLayer`
Renders lines (LineStrings) on the map.

```dart
PolylineLayer(
  polylines: [
    Polyline(
      points: [LatLng(51.5, -0.09), LatLng(53.3498, -6.2603)],
      color: Colors.blue,
      strokeWidth: 4.0,
      pattern: const StrokePattern.dashed(segments: [20, 10]), // 20px line, 10px gap
      // pattern: const StrokePattern.dotted(spacingFactor: 1.5),
      // pattern: const StrokePattern.solid(),
    ),
  ],
)
```

### `PolygonLayer`
Renders filled shapes on the map.

```dart
PolygonLayer(
  // Optional: Use alternative rendering pathway for complex polygons
  // useAltRendering: true, 
  polygons: [
    Polygon(
      points: [LatLng(51.5, -0.09), LatLng(53.34, -6.26), LatLng(48.85, 2.35)],
      holePointsList: [ /* List of LatLng lists to cut out holes */ ],
      color: Colors.purple.withValues(alpha: 0.5),
      borderColor: Colors.yellow,
      borderStrokeWidth: 4,
      label: 'My Polygon',
      labelStyle: const TextStyle(color: Colors.white),
      labelPlacementCalculator: const PolygonLabelPlacementCalculator.polylabel(),
    ),
  ],
)
```
*Note on `labelPlacementCalculator`: Options include `.centroid()`, `.simpleCentroid()`, `.simpleMultiWorldCentroid()`, and `.polylabel()` (most accurate but computationally expensive).*

### `CircleLayer`
Renders circles with a specific radius.

```dart
CircleLayer(
  circles: [
    CircleMarker(
      point: const LatLng(51.5, -0.09),
      radius: 1000, // 1000 meters
      useRadiusInMeter: true, // If false, radius is in logical pixels
      color: Colors.green.withValues(alpha: 0.5),
      borderColor: Colors.black,
      borderStrokeWidth: 2,
    ),
  ],
)
```

### `OverlayImageLayer`
Overlays an image stretched across geographic bounds.

```dart
OverlayImageLayer(
  overlayImages: [
    OverlayImage(
      bounds: LatLngBounds(LatLng(51.5, -0.09), LatLng(48.85, 2.35)),
      opacity: 0.8,
      imageProvider: const NetworkImage('https://example.com/image.jpg'),
    ),
    // Or use RotatedOverlayImage for skewed/rotated images requiring 3 corners
  ],
)
```

### `Scalebar`
Displays a dynamic scale bar (e.g., "500 km" / "100 m").
```dart
Scalebar(
  alignment: Alignment.bottomLeft,
  length: ScalebarLength.m,
)
```

---

## 5. Hit Detection (Tapping Shapes)

`PolygonLayer`, `PolylineLayer`, and `CircleLayer` support hit detection. This allows you to detect when a user taps on a specific shape.

**Implementation Steps:**
1. Create a `LayerHitNotifier`.
2. Assign a `hitValue` to your shapes.
3. Wrap the layer in a `GestureDetector`.

```dart
// 1. Define the notifier in your State
final LayerHitNotifier<String> _hitNotifier = ValueNotifier(null);

// 2. Build the layer
GestureDetector(
  onTap: () {
    final hitResult = _hitNotifier.value;
    if (hitResult != null && hitResult.hitValues.isNotEmpty) {
      print('Tapped on: ${hitResult.hitValues.first}');
      print('At coordinate: ${hitResult.coordinate}');
    }
  },
  child: PolygonLayer(
    hitNotifier: _hitNotifier,
    polygons: [
      Polygon(
        hitValue: 'Zone A', // 3. Assign the hit value
        points: [ /* ... */ ],
        color: Colors.blue,
      ),
    ],
  ),
)
```

---

## 6. Attribution

Most tile servers (like OpenStreetMap) legally require attribution. `flutter_map` provides two built-in widgets for this, which should be placed at the end of the `children` list.

### `RichAttributionWidget` (Recommended)
A modern, collapsible popup box.
```dart
RichAttributionWidget(
  alignment: AttributionAlignment.bottomRight,
  animationConfig: const ScaleRAWA(), // Or FadeRAWA()
  attributions: [
    TextSourceAttribution(
      'OpenStreetMap contributors',
      onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
    ),
    LogoSourceAttribution(
      Image.asset('assets/mapbox-logo.png'),
      tooltip: 'Mapbox',
    ),
  ],
)
```

### `SimpleAttributionWidget`
A classic, always-visible text box.
```dart
SimpleAttributionWidget(
  source: const Text('OpenStreetMap contributors'),
  onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
)
```

---

## 7. Advanced Features

### Multi-World Support
By default, `flutter_map` repeats the map horizontally (longitude wrapping). 
If you draw a `Polyline` or `Polygon` that crosses the anti-meridian (180° / -180°), or if you want a shape to only appear in *one* specific world copy, use the `drawInSingleWorld` property.
```dart
PolygonLayer(
  drawInSingleWorld: true, // Prevents the polygon from repeating across infinite worlds
  polygons: [ ... ],
)
```

### Tile Update Transformers
You can throttle or debounce tile network requests during rapid map movements (like flinging) to save bandwidth and improve performance.
```dart
TileLayer(
  urlTemplate: '...',
  // Debounce tile loads by 20ms
  tileUpdateTransformer: TileUpdateTransformers.debounce(const Duration(milliseconds: 20)),
)
```

### Coordinate Reference Systems (CRS)
`flutter_map` supports different projections. Set via `MapOptions(crs: ...)`.
*   `Epsg3857()`: Default. Spherical Mercator (used by Google Maps, OSM).
*   `Epsg4326()`: Equirectangular projection.
*   `CrsSimple()`: Flat grid, useful for indoor mapping or game maps.
*   `Proj4Crs.fromFactory(...)`: Custom projections using the `proj4dart` package.