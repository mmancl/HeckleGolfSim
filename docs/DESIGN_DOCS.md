# HeckleLinks: Technical Design Document

This document outlines the architecture, data structures, JNI bindings, and gameplay rules implemented in HeckleLinks.

---

## 1. Hardware Ingestion Layer (Native Android BLE)

To support native Bluetooth Low Energy (BLE) on Android without third-party plugins, HeckleLinks maps Godot's C# environment directly to Android's JNI APIs using the built-in `JavaClassWrapper` and `JavaObject`.

### 1.1 Architecture & Callbacks
Android's BLE APIs require passing abstract class instances (`ScanCallback` and `BluetoothGattCallback`) to listen for events. Since Godot's `JavaClassWrapper.CreateProxy()` can only implement Java *interfaces*, we introduce a compiled Java helper `GodotBleHelper.java` under the custom Android build directory (`android/build/src/com/godot/game/GodotBleHelper.java`).

- **GodotBleHelper**: Implements concrete subclasses of `ScanCallback` and `BluetoothGattCallback`, forwarding the events to simple interfaces `ScanListener` and `GattListener`.
- **AndroidBluetoothGattClient (C#)**: Uses `JavaClassWrapper.CreateProxy` to map the C# client methods to the Java listeners.

### 1.2 Android Manifest Permissions
To scan, connect, and read BLE telemetry, the following permissions are declared in the Android export presets / AndroidManifest:
- `android.permission.BLUETOOTH`: Allows connection to paired devices (Android 11 and lower).
- `android.permission.BLUETOOTH_ADMIN`: Allows discovery and pairing (Android 11 and lower).
- `android.permission.BLUETOOTH_SCAN`: Allows discovering nearby devices (Android 12+).
- `android.permission.BLUETOOTH_CONNECT`: Allows communicating with discovered devices (Android 12+).
- `android.permission.ACCESS_FINE_LOCATION`: Required to scan for BLE beacons/monitors (Android 11 and lower).

---

## 2. Course Rendering & Caching Layer (OpenStreetMap)

HeckleLinks queries the OpenStreetMap (OSM) Overpass API using a bounding box or radius around specified latitude/longitude coordinates.

### 2.1 Overpass API Query
The map loader posts queries to `https://overpass-api.de/api/interpreter` fetching tags for:
- `leisure=golf_course`
- `golf=fairway`
- `golf=green`
- `golf=bunker`
- `golf=hole`
- `golf=tee`

### 2.2 3D Generation & Layering
1. 2D latitude/longitude nodes are converted to local meter coordinates relative to the course's centroid origin:
   - $Z = -(\text{lat} - \text{origin\_lat}) \times 111320.0$ (negative Z is North in Godot)
   - $X = (\text{lon} - \text{origin\_lon}) \times 111320.0 \times \cos(\text{origin\_lat} \times \frac{\pi}{180.0})$
2. 2D boundary polygons are triangulated using `Geometry2D.TriangulatePolygon()`.
3. High-quality 3D meshes are constructed using `ArrayMesh` and styled with a distinct, premium material palette.
4. Vertical offsets (Y heights) are applied to separate overlapping polygons and prevent z-fighting:
   - Green: $Y = 0.03$
   - Fairway: $Y = 0.02$
   - Bunker/Sand: $Y = 0.01$
   - Rough/Ground: $Y = 0.00$
5. `StaticBody3D` nodes and corresponding `CollisionShape3D` (using `ConcavePolygonShape3D`) are added to meshes. A metadata property `"surface_type"` is injected to enable automatic, physics-based surface detection under the rolling ball.

### 2.3 PackedScene Caching
- Generated course meshes and metadata are packed into a `PackedScene` and serialized to local storage: `user://courses/{safe_course_name}/course.tscn`
- Accompanying properties (pars, handicaps, tee coordinates) are serialized to: `user://courses/{safe_course_name}/course.json`
- The loader checks if these files exist before making outbound API calls, delivering instant subsequent load times.

---

## 3. Announcer & Heckler Rules Engine

The Announcer Engine acts as a C# singleton (`AnnouncerEngine.cs`) loaded as a Godot Autoload. It monitors ball movement and evaluates telemetry against predefined thresholds.

### 3.1 Telemetry Thresholds
- **Wormburner**: Launch angle $< 4^\circ$ (excluding putts).
- **Pop-up / Skyball**: Launch angle $> 30^\circ$ using a driver (ball speed $> 110$ mph).
- **Slice**: Offline distance $> 25$ yards to the right (positive) with a spin axis $> 12^\circ$.
- **Hook**: Offline distance $> 25$ yards to the left (negative) with a spin axis $< -12^\circ$.
- **Bomb**: Total distance $> 270$ yards.
- **Duff**: Total distance $< 20$ yards (excluding putts).

### 3.2 Voice Output (Text-to-Speech)
- C# wraps the Android TextToSpeech engine via `DisplayServer.TtsSpeak()`.
- Declares the `<queries>` element in the Android Manifest to ensure package visibility of TTS service providers.
- Filters and displays available system locales/genders in the Settings dropdown OptionButton.

---

## 4. Multiplayer Course Play & Golf Etiquette

Multiplayer Course Play is governed by `MultiplayerManager.gd` which implements standard USGA golf rules.

### 4.1 Play Order Rules
- **Tee-off Order (First Hole)**: Sequentially by player entry order.
- **Away Player Hits First**: Once all players have teed off, their horizontal distance to the hole pin is calculated. The player whose ball is furthest away becomes the active player and takes the next shot.
- **Honors (Next Hole)**: On subsequent holes, the player with the lowest score on the previous hole tees off first. Tied players maintain their relative order from the previous hole.
- **Hole Completion**: Players hole out when their ball enters the cup (distance to pin $< 0.15$ meters). The hole is complete when all players have holed out.

---

## 5. References & Online Sources

- **OpenStreetMap Golf Wiki**: [Key:golf Documentation](https://wiki.openstreetmap.org/wiki/Key:golf)
- **OpenStreetMap Hole Tagging**: [Tag:golf=hole Details](https://wiki.openstreetmap.org/wiki/Tag:golf%3Dhole)
- **USGA Playing Rules**: [Rule 6.4: Order of Play / Honors and Away Rules](https://www.usga.org/content/usga/home-page/rules/rules-2019/rules-of-golf/rule-6.html)
- **Godot Android Export & Custom Templates**: [Godot Android Plugin System](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html)
- **Godot Text-to-Speech API**: [DisplayServer class reference](https://docs.godotengine.org/en/stable/classes/class_displayserver.html#class-displayserver-method-tts-speak)
