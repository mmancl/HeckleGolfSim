# Native Android MediaPipe Pose Plugin for Godot 4

This plugin enables **on-device, GPU-accelerated Google MediaPipe Pose AI Landmark Detection** directly inside HeckleGolfSim on Android devices without requiring a PC or external server.

---

## 🛠️ Folder Structure

```
android/plugins/MediaPipePosePlugin/
├── MediaPipePosePlugin.gdap        # Godot plugin configuration
├── MediaPipePosePlugin.aar         # Compiled plugin binary
├── build.gradle                    # Android Gradle build file
└── src/main/java/org/godotengine/plugin/android/mediapipepose/
    └── MediaPipePosePlugin.java    # Java plugin bridge
```

---

## 🚀 How to Build & Enable on Android

### Step 1: Build the `.aar` Library
Run Gradle from the plugin directory or root Android project:
```bash
./gradlew assembleRelease
```
Copy the compiled `MediaPipePosePlugin-release.aar` to:
`android/plugins/MediaPipePosePlugin/MediaPipePosePlugin.aar`

### Step 2: Download MediaPipe Task Model
Download the official Google MediaPipe Pose Landmarker model:
- **Model file**: `pose_landmarker_lite.task` (or `pose_landmarker_full.task`)
- **Download URL**: https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
- **Location**: Place inside `android/build/assets/pose_landmarker_lite.task` (or project root `assets/`).

### Step 3: Enable in Godot Export Settings
1. In Godot IDE: **Project -> Export -> Android**.
2. Check **Use Custom Build**.
3. Under **Plugins**, check **MediaPipe Pose Plugin**.
4. Export the APK!

---

## 🎯 Verification
Upon launch on an Android device:
- `Engine.has_singleton("MediaPipePosePlugin")` will evaluate to `true`.
- The app uses local GPU acceleration to detect 33 MediaPipe body landmarks at 30+ FPS!
