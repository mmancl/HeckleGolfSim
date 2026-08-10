# Native Android MediaPipe Pose Plugin for Godot 4

This plugin enables **on-device, GPU-accelerated Google MediaPipe Pose AI Landmark Detection** directly inside HeckleGolfSim on Android devices without requiring a PC or external server.

---

## 🛠️ Folder Structure

```
android/plugins/MediaPipePosePlugin/
├── MediaPipePosePlugin.gdap        # Godot plugin configuration
├── MediaPipePosePlugin.aar         # Compiled plugin binary (~5 MB with task model)
├── build.gradle                    # Android Gradle build file
├── assets/                         # Packaged assets (pose_landmarker_lite.task)
└── src/
    └── main/
        ├── assets/                 # Task model source folder (pose_landmarker_lite.task)
        ├── AndroidManifest.xml
        └── java/org/godotengine/plugin/android/mediapipepose/
            └── MediaPipePosePlugin.java # Native Android Java plugin
```

---

## 🚀 How to Rebuild the `.aar` Library

### Step 1: Ensure Model Task File is Present
Ensure `pose_landmarker_lite.task` is located in `android/plugins/MediaPipePosePlugin/src/main/assets/pose_landmarker_lite.task` (and `android/plugins/MediaPipePosePlugin/assets/pose_landmarker_lite.task`).

If missing, download it from Google:
```bash
# Model file: pose_landmarker_lite.task (~5.7 MB)
# URL: https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/latest/pose_landmarker_lite.task
```

### Step 2: Build with Gradle
Run the Gradle build command using the wrapper from `android/build`:

**On Windows (PowerShell / CMD):**
```cmd
cd android\build
gradlew.bat -p ..\plugins\MediaPipePosePlugin assembleRelease
```

**On Linux / macOS:**
```bash
cd android/build
./gradlew -p ../plugins/MediaPipePosePlugin assembleRelease
```

### Step 3: Copy Output AAR to Plugin Directory
Copy the built library from the Gradle output path to the root plugin directory:

**Windows (PowerShell):**
```powershell
Copy-Item 'android/plugins/MediaPipePosePlugin/build/outputs/aar/MediaPipePosePlugin-release.aar' 'android/plugins/MediaPipePosePlugin/MediaPipePosePlugin.aar' -Force
```

**Linux / macOS:**
```bash
cp android/plugins/MediaPipePosePlugin/build/outputs/aar/MediaPipePosePlugin-release.aar android/plugins/MediaPipePosePlugin/MediaPipePosePlugin.aar
```

> ⚠️ **Verification:** Verify that `MediaPipePosePlugin.aar` is approximately **~5 MB** in size. If it is only ~4.5 KB, the model file was not bundled into the AAR.

---

## ⚙️ Enabling in Godot Android Export

1. Open **Godot IDE** -> **Project -> Export -> Android**.
2. Ensure **Use Custom Build** is enabled.
3. Under **Plugins**, check **MediaPipe Pose Plugin**.
4. Export the APK!

---

## 🎯 Verification & On-Device Logs

Upon launching on an Android device with camera connected:
- `Engine.has_singleton("MediaPipePosePlugin")` will evaluate to `true`.
- Open a terminal and view real-time logs via `adb`:
  ```bash
  adb logcat | grep -i "MediaPipePose"
  ```
- Look for `MediaPipe PoseLandmarker initialized successfully` and `Pose detected successfully`.

