package org.godotengine.plugin.android.mediapipepose;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Log;
import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker.PoseLandmarkerOptions;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.MPImage;

import org.json.JSONObject;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

/**
 * Native Android Godot Plugin for local Google MediaPipe Pose Detection.
 * Processes camera frames directly on mobile GPU/NPU using MediaPipe Tasks Vision SDK.
 */
public class MediaPipePosePlugin extends GodotPlugin {
    private static final String TAG = "MediaPipePosePlugin";
    private static final String PLUGIN_NAME = "MediaPipePosePlugin";
    private PoseLandmarker poseLandmarker;

    public MediaPipePosePlugin(Godot godot) {
        super(godot);
        initMediaPipe();
    }

    @NonNull
    @Override
    public String getPluginName() {
        return PLUGIN_NAME;
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("pose_result", String.class));
        return signals;
    }

    private synchronized void initMediaPipe() {
        if (poseLandmarker != null) return;
        try {
            BaseOptions baseOptions = BaseOptions.builder()
                .setModelAssetPath("pose_landmarker_lite.task")
                .build();

            PoseLandmarkerOptions options = PoseLandmarkerOptions.builder()
                .setBaseOptions(baseOptions)
                .setRunningMode(RunningMode.IMAGE)
                .setNumPoses(1)
                .setMinPoseDetectionConfidence(0.3f)
                .setMinPosePresenceConfidence(0.3f)
                .setMinTrackingConfidence(0.3f)
                .build();

            if (getActivity() != null) {
                poseLandmarker = PoseLandmarker.createFromOptions(getActivity(), options);
                Log.d(TAG, "MediaPipe PoseLandmarker initialized successfully.");
            }
        } catch (Exception e) {
            Log.e(TAG, "Failed to initialize MediaPipe PoseLandmarker: " + e.getMessage(), e);
        }
    }

    @UsedByGodot
    public void processFrame(byte[] jpegBytes) {
        if (jpegBytes == null || jpegBytes.length == 0) {
            emitSignal("pose_result", "{\"detected\":false}");
            return;
        }

        if (poseLandmarker == null) {
            initMediaPipe();
            if (poseLandmarker == null) {
                emitSignal("pose_result", "{\"detected\":false}");
                return;
            }
        }

        try {
            Bitmap bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.length);
            if (bitmap == null) {
                emitSignal("pose_result", "{\"detected\":false}");
                return;
            }

            MPImage mpImage = new BitmapImageBuilder(bitmap).build();
            PoseLandmarkerResult result = poseLandmarker.detect(mpImage);

            JSONObject json = new JSONObject();
            if (result == null || result.landmarks() == null || result.landmarks().isEmpty()) {
                json.put("detected", false);
            } else {
                json.put("detected", true);
                JSONObject landmarksObj = new JSONObject();
                List<NormalizedLandmark> landmarksList = result.landmarks().get(0);
                
                String[] lmNames = {
                    "nose", "left_eye_inner", "left_eye", "left_eye_outer",
                    "right_eye_inner", "right_eye", "right_eye_outer",
                    "left_ear", "right_ear", "mouth_left", "mouth_right",
                    "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
                    "left_wrist", "right_wrist", "left_pinky", "right_pinky",
                    "left_index", "right_index", "left_thumb", "right_thumb",
                    "left_hip", "right_hip", "left_knee", "right_knee",
                    "left_ankle", "right_ankle", "left_heel", "right_heel",
                    "left_foot_index", "right_foot_index"
                };

                for (int i = 0; i < Math.min(landmarksList.size(), lmNames.length); i++) {
                    NormalizedLandmark lm = landmarksList.get(i);
                    JSONObject lmObj = new JSONObject();
                    lmObj.put("x", lm.x());
                    lmObj.put("y", lm.y());
                    lmObj.put("z", lm.z());
                    float vis = 1.0f;
                    if (lm.visibility().isPresent()) {
                        vis = lm.visibility().get();
                    }
                    lmObj.put("visibility", vis);
                    landmarksObj.put(lmNames[i], lmObj);
                }
                json.put("landmarks", landmarksObj);
            }

            emitSignal("pose_result", json.toString());
        } catch (Exception e) {
            Log.e(TAG, "Error during processFrame pose detection: " + e.getMessage(), e);
            emitSignal("pose_result", "{\"detected\":false}");
        }
    }
}
