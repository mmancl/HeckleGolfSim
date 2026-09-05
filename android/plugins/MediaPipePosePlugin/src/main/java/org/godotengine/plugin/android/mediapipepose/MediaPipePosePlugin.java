package org.godotengine.plugin.android.mediapipepose;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.ImageFormat;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.graphics.YuvImage;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Size;
import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.core.Delegate;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker.PoseLandmarkerOptions;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.MPImage;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Native Android Godot Plugin for local Google MediaPipe Pose Detection.
 * Supports direct camera capture via Camera2 API (bypassing Godot texture limits)
 * as well as external frame processing for WiFi streams.
 */
public class MediaPipePosePlugin extends GodotPlugin {
    private static final String TAG = "MediaPipePosePlugin";
    private static final String PLUGIN_NAME = "MediaPipePosePlugin";

    private PoseLandmarker poseLandmarker;
    private boolean isGpuActive = false;
    private long frameCount = 0;

    // Camera2 state
    private CameraDevice cameraDevice;
    private CameraCaptureSession captureSession;
    private ImageReader imageReader;
    private HandlerThread backgroundThread;
    private Handler backgroundHandler;
    private final AtomicBoolean isProcessingCameraFrame = new AtomicBoolean(false);
    private boolean cameraRunning = false;
    private int activeFacing = 0; // 0 = BACK, 1 = FRONT
    private int sensorOrientation = 0;
    private volatile boolean liveInferenceEnabled = false; // Default false to avoid choppiness on mobile

    private static final String[] LANDMARK_NAMES = {
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

    public MediaPipePosePlugin(Godot godot) {
        super(godot);
        Log.i(TAG, "MediaPipePosePlugin plugin constructor called.");
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
        signals.add(new SignalInfo("camera_frame", byte[].class, String.class));
        return signals;
    }

    private Context getBestContext() {
        if (getActivity() != null) {
            Context appCtx = getActivity().getApplicationContext();
            if (appCtx != null) return appCtx;
            return getActivity();
        }
        return null;
    }

    private synchronized void initMediaPipe() {
        if (poseLandmarker != null) return;
        Context context = getBestContext();
        if (context == null) {
            Log.w(TAG, "initMediaPipe deferred: context is null");
            return;
        }

        String[] modelPaths = {"pose_landmarker_lite.task", "assets/pose_landmarker_lite.task"};
        Exception lastException = null;

        for (String modelPath : modelPaths) {
            // First attempt: GPU delegate
            try {
                Log.d(TAG, "Attempting GPU MediaPipe model initialization: " + modelPath);
                BaseOptions baseOptions = BaseOptions.builder()
                    .setModelAssetPath(modelPath)
                    .setDelegate(Delegate.GPU)
                    .build();

                PoseLandmarkerOptions options = PoseLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setRunningMode(RunningMode.IMAGE)
                    .setNumPoses(1)
                    .setMinPoseDetectionConfidence(0.3f)
                    .setMinPosePresenceConfidence(0.3f)
                    .setMinTrackingConfidence(0.3f)
                    .build();

                poseLandmarker = PoseLandmarker.createFromOptions(context, options);
                isGpuActive = true;
                Log.i(TAG, "MediaPipe PoseLandmarker initialized with GPU delegate successfully: " + modelPath);
                return;
            } catch (Exception e) {
                Log.w(TAG, "GPU delegate initialization failed for '" + modelPath + "': " + e.getMessage() + ". Retrying with CPU delegate...");
                lastException = e;
            }

            // Fallback attempt: CPU delegate
            try {
                BaseOptions baseOptions = BaseOptions.builder()
                    .setModelAssetPath(modelPath)
                    .setDelegate(Delegate.CPU)
                    .build();

                PoseLandmarkerOptions options = PoseLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setRunningMode(RunningMode.IMAGE)
                    .setNumPoses(1)
                    .setMinPoseDetectionConfidence(0.3f)
                    .setMinPosePresenceConfidence(0.3f)
                    .setMinTrackingConfidence(0.3f)
                    .build();

                poseLandmarker = PoseLandmarker.createFromOptions(context, options);
                isGpuActive = false;
                Log.i(TAG, "MediaPipe PoseLandmarker initialized with CPU delegate successfully: " + modelPath);
                return;
            } catch (Exception e) {
                lastException = e;
                Log.w(TAG, "Could not load MediaPipe model with CPU from '" + modelPath + "': " + e.getMessage());
            }
        }

        if (lastException != null) {
            Log.e(TAG, "Failed to initialize MediaPipe PoseLandmarker after trying all delegate and model paths.", lastException);
        }
    }

    @UsedByGodot
    public boolean isModelLoaded() {
        if (poseLandmarker == null) {
            initMediaPipe();
        }
        return poseLandmarker != null;
    }

    @UsedByGodot
    public boolean isGpuAccelerated() {
        return isGpuActive;
    }

    @UsedByGodot
    public void setLiveInferenceEnabled(boolean enabled) {
        liveInferenceEnabled = enabled;
        Log.i(TAG, "liveInferenceEnabled set to: " + enabled);
    }

    @UsedByGodot
    public boolean isLiveInferenceEnabled() {
        return liveInferenceEnabled;
    }

    // ─── Camera2 Native Direct Capture API ──────────────────────────────────────

    @UsedByGodot
    public boolean hasCamera() {
        return getCameraCount() > 0;
    }

    @UsedByGodot
    public int getCameraCount() {
        Context ctx = getBestContext();
        if (ctx == null) return 0;
        CameraManager manager = (CameraManager) ctx.getSystemService(Context.CAMERA_SERVICE);
        if (manager == null) return 0;
        try {
            return manager.getCameraIdList().length;
        } catch (CameraAccessException e) {
            Log.e(TAG, "Error querying camera count: " + e.getMessage());
            return 0;
        }
    }

    @UsedByGodot
    public boolean isCameraActive() {
        return cameraRunning;
    }

    @UsedByGodot
    public void startCamera(int facing) {
        if (cameraRunning) {
            stopCamera();
        }

        Context ctx = getBestContext();
        if (ctx == null) {
            Log.e(TAG, "startCamera failed: context is null");
            return;
        }

        if (ctx.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            Log.e(TAG, "startCamera failed: CAMERA permission not granted");
            emitSignal("pose_result", "{\"error\":\"Camera permission not granted\",\"detected\":false}");
            return;
        }

        if (poseLandmarker == null) {
            initMediaPipe();
        }

        activeFacing = facing;
        startBackgroundThread();

        CameraManager manager = (CameraManager) ctx.getSystemService(Context.CAMERA_SERVICE);
        if (manager == null) {
            Log.e(TAG, "CameraManager not available");
            return;
        }

        try {
            int targetLensFacing = (facing == 1) ? CameraCharacteristics.LENS_FACING_FRONT : CameraCharacteristics.LENS_FACING_BACK;
            String selectedCameraId = null;

            for (String cameraId : manager.getCameraIdList()) {
                CameraCharacteristics characteristics = manager.getCameraCharacteristics(cameraId);
                Integer lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING);
                if (lensFacing != null && lensFacing == targetLensFacing) {
                    selectedCameraId = cameraId;
                    Integer orient = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
                    sensorOrientation = (orient != null) ? orient : 0;
                    break;
                }
            }

            if (selectedCameraId == null && manager.getCameraIdList().length > 0) {
                selectedCameraId = manager.getCameraIdList()[0];
                CameraCharacteristics characteristics = manager.getCameraCharacteristics(selectedCameraId);
                Integer orient = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION);
                sensorOrientation = (orient != null) ? orient : 0;
            }

            if (selectedCameraId == null) {
                Log.e(TAG, "No suitable camera ID found");
                return;
            }

            CameraCharacteristics characteristics = manager.getCameraCharacteristics(selectedCameraId);
            StreamConfigurationMap map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            Size previewSize = chooseOptimalSize(map != null ? map.getOutputSizes(ImageFormat.YUV_420_888) : null, 640, 480);

            imageReader = ImageReader.newInstance(previewSize.getWidth(), previewSize.getHeight(), ImageFormat.YUV_420_888, 2);
            imageReader.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                @Override
                public void onImageAvailable(ImageReader reader) {
                    Image image = null;
                    try {
                        image = reader.acquireLatestImage();
                        if (image == null) return;

                        if (!isProcessingCameraFrame.compareAndSet(false, true)) {
                            image.close();
                            return;
                        }

                        final Image imgToProcess = image;
                        backgroundHandler.post(new Runnable() {
                            @Override
                            public void run() {
                                try {
                                    processCameraImage(imgToProcess);
                                } finally {
                                    imgToProcess.close();
                                    isProcessingCameraFrame.set(false);
                                }
                            }
                        });
                    } catch (Exception e) {
                        if (image != null) {
                            image.close();
                        }
                        isProcessingCameraFrame.set(false);
                    }
                }
            }, backgroundHandler);

            manager.openCamera(selectedCameraId, new CameraDevice.StateCallback() {
                @Override
                public void onOpened(@NonNull CameraDevice camera) {
                    cameraDevice = camera;
                    createCameraCaptureSession();
                }

                @Override
                public void onDisconnected(@NonNull CameraDevice camera) {
                    camera.close();
                    cameraDevice = null;
                    cameraRunning = false;
                }

                @Override
                public void onError(@NonNull CameraDevice camera, int error) {
                    Log.e(TAG, "CameraDevice error: " + error);
                    camera.close();
                    cameraDevice = null;
                    cameraRunning = false;
                }
            }, backgroundHandler);

            cameraRunning = true;
            Log.i(TAG, "startCamera requested for camera ID: " + selectedCameraId + " (" + previewSize.getWidth() + "x" + previewSize.getHeight() + ")");
        } catch (Exception e) {
            Log.e(TAG, "Failed to start camera: " + e.getMessage(), e);
            stopCamera();
        }
    }

    private void createCameraCaptureSession() {
        if (cameraDevice == null || imageReader == null) return;
        try {
            final CaptureRequest.Builder builder = cameraDevice.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
            builder.addTarget(imageReader.getSurface());
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);

            cameraDevice.createCaptureSession(Collections.singletonList(imageReader.getSurface()), new CameraCaptureSession.StateCallback() {
                @Override
                public void onConfigured(@NonNull CameraCaptureSession session) {
                    if (cameraDevice == null) return;
                    captureSession = session;
                    try {
                        captureSession.setRepeatingRequest(builder.build(), null, backgroundHandler);
                        Log.i(TAG, "Camera capture session configured successfully.");
                    } catch (Exception e) {
                        Log.e(TAG, "Failed to start repeating camera capture request: " + e.getMessage());
                    }
                }

                @Override
                public void onConfigureFailed(@NonNull CameraCaptureSession session) {
                    Log.e(TAG, "Camera capture session configuration failed.");
                }
            }, backgroundHandler);
        } catch (Exception e) {
            Log.e(TAG, "Error creating camera capture session: " + e.getMessage(), e);
        }
    }

    @UsedByGodot
    public void stopCamera() {
        cameraRunning = false;
        try {
            if (captureSession != null) {
                captureSession.stopRepeating();
                captureSession.close();
                captureSession = null;
            }
            if (cameraDevice != null) {
                cameraDevice.close();
                cameraDevice = null;
            }
            if (imageReader != null) {
                imageReader.close();
                imageReader = null;
            }
        } catch (Exception e) {
            Log.e(TAG, "Error closing camera resources: " + e.getMessage());
        }
        stopBackgroundThread();
        Log.i(TAG, "Native camera stopped.");
    }

    private Size chooseOptimalSize(Size[] choices, int preferredWidth, int preferredHeight) {
        if (choices == null || choices.length == 0) {
            return new Size(preferredWidth, preferredHeight);
        }
        for (Size size : choices) {
            if (size.getWidth() == preferredWidth && size.getHeight() == preferredHeight) {
                return size;
            }
        }
        // Pick size closest to preferred resolution under 1280x720
        Size best = choices[0];
        int minDiff = Integer.MAX_VALUE;
        for (Size size : choices) {
            if (size.getWidth() <= 1280 && size.getHeight() <= 720) {
                int diff = Math.abs(size.getWidth() - preferredWidth) + Math.abs(size.getHeight() - preferredHeight);
                if (diff < minDiff) {
                    minDiff = diff;
                    best = size;
                }
            }
        }
        return best;
    }

    private void startBackgroundThread() {
        if (backgroundThread != null) return;
        backgroundThread = new HandlerThread("MediaPipeCameraBackground");
        backgroundThread.start();
        backgroundHandler = new Handler(backgroundThread.getLooper());
    }

    private void stopBackgroundThread() {
        if (backgroundThread == null) return;
        backgroundThread.quitSafely();
        try {
            backgroundThread.join(500);
            backgroundThread = null;
            backgroundHandler = null;
        } catch (InterruptedException e) {
            Log.e(TAG, "Background thread interrupted during stop: " + e.getMessage());
        }
    }

    private void processCameraImage(Image image) {
        if (image == null) return;
        frameCount++;

        try {
            int width = image.getWidth();
            int height = image.getHeight();
            byte[] nv21 = yuv420ToNv21(image);

            YuvImage yuvImage = new YuvImage(nv21, ImageFormat.NV21, width, height, null);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            yuvImage.compressToJpeg(new Rect(0, 0, width, height), 70, out);
            byte[] initialJpeg = out.toByteArray();

            Bitmap bitmap = BitmapFactory.decodeByteArray(initialJpeg, 0, initialJpeg.length);
            if (bitmap == null) return;

            byte[] finalJpegBytes = initialJpeg;
            if (sensorOrientation != 0 || activeFacing == 1) {
                Matrix matrix = new Matrix();
                if (sensorOrientation != 0) {
                    matrix.postRotate(sensorOrientation);
                }
                if (activeFacing == 1) {
                    matrix.postScale(-1, 1); // Mirror front-facing camera
                }
                Bitmap rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), matrix, true);
                if (rotated != bitmap) {
                    bitmap.recycle();
                    bitmap = rotated;
                }
                ByteArrayOutputStream uprightOut = new ByteArrayOutputStream();
                bitmap.compress(Bitmap.CompressFormat.JPEG, 70, uprightOut);
                finalJpegBytes = uprightOut.toByteArray();
            }

            String jsonResult = "{\"detected\":false}";
            if (liveInferenceEnabled) {
                jsonResult = runPoseInference(bitmap);
                emitSignal("pose_result", jsonResult);
            }

            if (bitmap != null) {
                bitmap.recycle();
            }

            emitSignal("camera_frame", finalJpegBytes, jsonResult);
        } catch (Exception e) {
            Log.e(TAG, "Error processing camera image: " + e.getMessage(), e);
        }
    }

    private static byte[] yuv420ToNv21(Image image) {
        int width = image.getWidth();
        int height = image.getHeight();
        int ySize = width * height;
        int uvSize = width * height / 2;
        byte[] nv21 = new byte[ySize + uvSize];

        Image.Plane yPlane = image.getPlanes()[0];
        Image.Plane uPlane = image.getPlanes()[1];
        Image.Plane vPlane = image.getPlanes()[2];

        ByteBuffer yBuffer = yPlane.getBuffer();
        ByteBuffer uBuffer = uPlane.getBuffer();
        ByteBuffer vBuffer = vPlane.getBuffer();

        int yRowStride = yPlane.getRowStride();
        int yPixelStride = yPlane.getPixelStride();

        int pos = 0;
        if (yPixelStride == 1 && yRowStride == width) {
            yBuffer.get(nv21, 0, ySize);
            pos = ySize;
        } else {
            for (int row = 0; row < height; row++) {
                yBuffer.position(row * yRowStride);
                for (int col = 0; col < width; col++) {
                    nv21[pos++] = yBuffer.get();
                    if (yPixelStride > 1 && col < width - 1) {
                        yBuffer.position(yBuffer.position() + yPixelStride - 1);
                    }
                }
            }
        }

        int uvRowStride = vPlane.getRowStride();
        int uvPixelStride = vPlane.getPixelStride();
        int uvWidth = width / 2;
        int uvHeight = height / 2;

        for (int row = 0; row < uvHeight; row++) {
            for (int col = 0; col < uvWidth; col++) {
                int vIndex = row * uvRowStride + col * uvPixelStride;
                int uIndex = row * uPlane.getRowStride() + col * uPlane.getPixelStride();
                nv21[pos++] = vBuffer.get(vIndex);
                nv21[pos++] = uBuffer.get(uIndex);
            }
        }
        return nv21;
    }

    // ─── External Frame Processing API (WiFi Phone Stream & Viewport) ───────────

    @UsedByGodot
    public void processFrame(byte[] jpegBytes) {
        if (jpegBytes == null || jpegBytes.length == 0) {
            emitSignal("pose_result", "{\"detected\":false}");
            return;
        }

        frameCount++;

        if (poseLandmarker == null) {
            initMediaPipe();
            if (poseLandmarker == null) {
                if (frameCount % 60 == 1) {
                    Log.e(TAG, "processFrame skipped: PoseLandmarker is not initialized.");
                }
                emitSignal("pose_result", "{\"detected\":false}");
                return;
            }
        }

        try {
            if (frameCount % 60 == 1) {
                Log.d(TAG, "Processing camera frame #" + frameCount + " (bytes: " + jpegBytes.length + ")");
            }

            Bitmap bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.length);
            if (bitmap == null) {
                Log.e(TAG, "Failed to decode JPEG bytes into Bitmap");
                emitSignal("pose_result", "{\"detected\":false}");
                return;
            }

            String jsonResult = runPoseInference(bitmap);
            bitmap.recycle();
            emitSignal("pose_result", jsonResult);
        } catch (Exception e) {
            Log.e(TAG, "Error during processFrame pose detection: " + e.getMessage(), e);
            emitSignal("pose_result", "{\"detected\":false}");
        }
    }

    @UsedByGodot
    public String detectPoseFromJpeg(byte[] jpegBytes) {
        if (jpegBytes == null || jpegBytes.length == 0) {
            return "{\"detected\":false}";
        }

        frameCount++;

        if (poseLandmarker == null) {
            initMediaPipe();
            if (poseLandmarker == null) {
                return "{\"detected\":false}";
            }
        }

        try {
            Bitmap bitmap = BitmapFactory.decodeByteArray(jpegBytes, 0, jpegBytes.length);
            if (bitmap == null) {
                return "{\"detected\":false}";
            }

            String jsonResult = runPoseInference(bitmap);
            bitmap.recycle();
            return jsonResult;
        } catch (Exception e) {
            Log.e(TAG, "Error in detectPoseFromJpeg: " + e.getMessage(), e);
            return "{\"detected\":false}";
        }
    }

    @UsedByGodot
    public void processFrameRaw(byte[] rgbBytes, int width, int height) {
        if (rgbBytes == null || rgbBytes.length == 0 || width <= 0 || height <= 0) {
            emitSignal("pose_result", "{\"detected\":false}");
            return;
        }

        frameCount++;

        if (poseLandmarker == null) {
            initMediaPipe();
            if (poseLandmarker == null) {
                emitSignal("pose_result", "{\"detected\":false}");
                return;
            }
        }

        try {
            Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            ByteBuffer buffer = ByteBuffer.wrap(rgbBytes);
            bitmap.copyPixelsFromBuffer(buffer);

            String jsonResult = runPoseInference(bitmap);
            emitSignal("pose_result", jsonResult);
        } catch (Exception e) {
            Log.e(TAG, "Error during processFrameRaw: " + e.getMessage(), e);
            emitSignal("pose_result", "{\"detected\":false}");
        }
    }

    private String runPoseInference(Bitmap bitmap) {
        if (poseLandmarker == null || bitmap == null) {
            return "{\"detected\":false}";
        }

        try {
            MPImage mpImage = new BitmapImageBuilder(bitmap).build();
            PoseLandmarkerResult result = poseLandmarker.detect(mpImage);

            JSONObject json = new JSONObject();
            if (result == null || result.landmarks() == null || result.landmarks().isEmpty()) {
                json.put("detected", false);
            } else {
                json.put("detected", true);
                JSONObject landmarksObj = new JSONObject();
                List<NormalizedLandmark> landmarksList = result.landmarks().get(0);

                for (int i = 0; i < Math.min(landmarksList.size(), LANDMARK_NAMES.length); i++) {
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
                    landmarksObj.put(LANDMARK_NAMES[i], lmObj);
                }
                json.put("landmarks", landmarksObj);

                if (frameCount % 60 == 1) {
                    Log.d(TAG, "Pose detected successfully with " + landmarksList.size() + " landmarks!");
                }
            }
            return json.toString();
        } catch (Exception e) {
            Log.e(TAG, "Error during runPoseInference: " + e.getMessage(), e);
            return "{\"detected\":false}";
        }
    }

    @Override
    public void onMainPause() {
        super.onMainPause();
        if (cameraRunning) {
            stopCamera();
        }
    }

    @Override
    public void onMainDestroy() {
        super.onMainDestroy();
        if (cameraRunning) {
            stopCamera();
        }
        if (poseLandmarker != null) {
            try {
                poseLandmarker.close();
                poseLandmarker = null;
            } catch (Exception e) {
                Log.e(TAG, "Error closing poseLandmarker: " + e.getMessage());
            }
        }
    }
}
