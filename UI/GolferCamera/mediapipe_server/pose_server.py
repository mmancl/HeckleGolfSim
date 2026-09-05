#!/usr/bin/env python3
"""
MediaPipe Pose Detection & System Camera Server — Embedded Backend
Auto-started by Godot's PoseDetectionBridge for desktop/laptop environments.
Uses Google MediaPipe Tasks Vision & OpenCV for local camera capture & pose tracking.

Endpoints:
  GET  /health           -> Server health & active camera state
  GET  /cameras          -> List available local system webcams
  POST /camera/select    -> Select/open camera index (e.g. {"index": 0})
  GET  /camera/capture   -> Capture frame from camera, run pose detection, return JPEG base64 + landmarks
  POST /pose             -> Accept external JPEG bytes, return pose landmarks JSON
"""

import base64
import http.server
import json
import os
import signal
import sys
import threading
import time
import urllib.parse


# ─── Model download ─────────────────────────────────────────────────────────────

MODEL_FILENAME = "pose_landmarker_full.task"
MODEL_DIR = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH = os.path.join(MODEL_DIR, MODEL_FILENAME)
MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/"
    "pose_landmarker/pose_landmarker_full/float16/latest/"
    "pose_landmarker_full.task"
)

PORT = 49154


def ensure_model():
    """Download the MediaPipe Pose Landmarker model if it doesn't exist."""
    if os.path.exists(MODEL_PATH):
        size_mb = os.path.getsize(MODEL_PATH) / (1024 * 1024)
        print(f"[PoseServer] Model found: {MODEL_FILENAME} ({size_mb:.1f} MB)")
        return
    print(f"[PoseServer] Downloading model: {MODEL_FILENAME} ...")
    import urllib.request
    urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    size_mb = os.path.getsize(MODEL_PATH) / (1024 * 1024)
    print(f"[PoseServer] Download complete ({size_mb:.1f} MB)")


ensure_model()

import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions
from mediapipe.tasks.python.vision import (
    PoseLandmarker,
    PoseLandmarkerOptions,
    RunningMode,
)

options = PoseLandmarkerOptions(
    base_options=BaseOptions(model_asset_path=MODEL_PATH),
    running_mode=RunningMode.IMAGE,
    num_poses=1,
    min_pose_detection_confidence=0.5,
    min_pose_presence_confidence=0.5,
    min_tracking_confidence=0.5,
    output_segmentation_masks=False,
)
detector = PoseLandmarker.create_from_options(options)
print("[PoseServer] MediaPipe PoseLandmarker initialised (full model).")

# Landmark indices used by the golf skeleton overlay
GOLF_LANDMARK_MAP = {
    "nose": 0,
    "left_shoulder": 11,
    "right_shoulder": 12,
    "left_elbow": 13,
    "right_elbow": 14,
    "left_wrist": 15,
    "right_wrist": 16,
    "left_hip": 23,
    "right_hip": 24,
    "left_knee": 25,
    "right_knee": 26,
    "left_ankle": 27,
    "right_ankle": 28,
}


def parse_landmarks(result) -> dict:
    if not result.pose_landmarks or len(result.pose_landmarks) == 0:
        return {}
    lms = result.pose_landmarks[0]
    landmarks = {}
    for name, idx in GOLF_LANDMARK_MAP.items():
        lm = lms[idx]
        landmarks[name] = {
            "x": round(lm.x, 6),
            "y": round(lm.y, 6),
            "z": round(lm.z, 6),
            "visibility": round(lm.visibility, 4),
        }
    return landmarks


# ─── Process Watchdog ─────────────────────────────────────────────────────────

def is_pid_alive(pid: int) -> bool:
    if pid <= 0:
        return True
    if os.name == "nt":
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            handle = kernel32.OpenProcess(0x1000 | 0x00100000, False, pid)
            if not handle:
                return False
            exit_code = ctypes.c_ulong()
            kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code))
            kernel32.CloseHandle(handle)
            return exit_code.value == 259
        except Exception:
            return False
    else:
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False


def start_parent_watchdog(parent_pid: int):
    if parent_pid <= 0:
        return

    def _watch():
        print(f"[PoseServer] Watchdog started for parent PID {parent_pid}")
        while True:
            time.sleep(2.0)
            if not is_pid_alive(parent_pid):
                print(f"[PoseServer] Parent process {parent_pid} terminated. Auto-shutting down...")
                camera_mgr.close()
                os._exit(0)

    t = threading.Thread(target=_watch, daemon=True)
    t.start()


# ─── Camera Manager ─────────────────────────────────────────────────────────────

class CameraManager:
    def __init__(self):
        self.lock = threading.Lock()
        self.cap = None
        self.active_index = -1

    def scan_cameras(self) -> list:
        cams = []
        # Check indices 0..3 using standard VideoCapture (fast MSMF on Windows)
        for i in range(4):
            cap = cv2.VideoCapture(i)
            if cap.isOpened():
                ret, _ = cap.read()
                if ret:
                    cams.append({"index": i, "name": f"System Camera {i}"})
                cap.release()
            else:
                if i >= 1 and len(cams) == 0:
                    break
        return cams

    def select_camera(self, index: int) -> bool:
        with self.lock:
            if self.active_index == index and self.cap is not None and self.cap.isOpened():
                return True
            if self.cap is not None:
                self.cap.release()
                self.cap = None
                self.active_index = -1

            if index < 0:
                return True

            cap = cv2.VideoCapture(index)
            if cap is not None and cap.isOpened():
                self.cap = cap
                self.active_index = index
                print(f"[PoseServer] Activated system camera {index}")
                return True
            else:
                print(f"[PoseServer] Failed to open system camera {index}")
                return False

    def capture_and_process(self, detect: bool = False) -> dict:
        with self.lock:
            if self.cap is None or not self.cap.isOpened():
                return {"detected": False, "landmarks": {}, "image_base64": "", "error": "No active camera"}

            ret, frame = self.cap.read()
            if not ret or frame is None:
                return {"detected": False, "landmarks": {}, "image_base64": "", "error": "Frame read failed"}

            # Resize if large to ensure smooth 30 FPS transmission
            h, w = frame.shape[:2]
            if w > 960:
                new_w = 640
                new_h = int(h * (640.0 / w))
                frame = cv2.resize(frame, (new_w, new_h))

            landmarks = {}
            detected = False
            if detect:
                # Run MediaPipe PoseLandmarker only when explicitly requested
                rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
                result = detector.detect(mp_image)
                landmarks = parse_landmarks(result)
                detected = len(landmarks) > 0

            # Encode frame to JPEG and base64
            encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 75]
            _, jpg_buffer = cv2.imencode('.jpg', frame, encode_param)
            b64_str = base64.b64encode(jpg_buffer).decode('ascii')

            return {
                "detected": detected,
                "landmarks": landmarks,
                "image_base64": b64_str,
                "camera_index": self.active_index,
            }

    def close(self):
        with self.lock:
            if self.cap is not None:
                self.cap.release()
                self.cap = None
                self.active_index = -1


camera_mgr = CameraManager()


# ─── HTTP Handler ───────────────────────────────────────────────────────────────

class PoseHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/pose":
            content_length = int(self.headers.get("Content-Length", 0))
            if content_length == 0:
                self._send(200, {"detected": False, "landmarks": {}})
                return
            image_bytes = self.rfile.read(content_length)
            if not image_bytes:
                self._send(200, {"detected": False, "landmarks": {}})
                return
            try:
                result = self._detect_raw(image_bytes)
                self._send(200, result)
            except Exception as exc:
                print(f"[PoseServer] Error processing frame: {exc}", file=sys.stderr)
                self._send(200, {"detected": False, "landmarks": {}, "error": str(exc)})
        elif parsed.path == "/camera/select":
            content_length = int(self.headers.get("Content-Length", 0))
            idx = 0
            if content_length > 0:
                body = self.rfile.read(content_length)
                try:
                    data = json.loads(body)
                    idx = data.get("index", 0)
                except Exception:
                    pass
            ok = camera_mgr.select_camera(idx)
            self._send(200, {"status": "ok" if ok else "error", "index": camera_mgr.active_index})
        else:
            self._send(404, {"error": "not found"})

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if path == "/health":
            self._send(200, {
                "status": "ok",
                "model": MODEL_FILENAME,
                "camera_active": camera_mgr.active_index >= 0,
                "camera_index": camera_mgr.active_index
            })
        elif path == "/cameras":
            cams = camera_mgr.scan_cameras()
            self._send(200, {"cameras": cams})
        elif path == "/camera/select":
            idx = int(query.get("index", [0])[0])
            ok = camera_mgr.select_camera(idx)
            self._send(200, {"status": "ok" if ok else "error", "index": camera_mgr.active_index})
        elif path == "/camera/capture" or path == "/camera/frame":
            detect = query.get("detect", ["0"])[0] in ("1", "true", "True")
            res = camera_mgr.capture_and_process(detect=detect)
            self._send(200, res)
        else:
            self._send(404, {"error": "not found"})

    @staticmethod
    def _detect_raw(jpeg_bytes: bytes) -> dict:
        np_arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
        bgr = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if bgr is None:
            return {"detected": False, "landmarks": {}}
        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = detector.detect(mp_image)
        landmarks = parse_landmarks(result)
        return {"detected": len(landmarks) > 0, "landmarks": landmarks}

    def _send(self, code: int, data: dict):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        try:
            self.wfile.flush()
        except Exception:
            pass

    def log_message(self, fmt, *args):
        pass


def main():
    import argparse
    parser = argparse.ArgumentParser(description="MediaPipe Pose & Camera Server")
    parser.add_argument("--parent-pid", type=int, default=0, help="Parent process ID to monitor")
    args, _ = parser.parse_known_args()

    if args.parent_pid > 0:
        start_parent_watchdog(args.parent_pid)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), PoseHandler)
    server.daemon_threads = True
    server.timeout = 1.0

    def _shutdown(sig, frame):
        print("\n[PoseServer] Shutting down...", flush=True)
        camera_mgr.close()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    print(f"[PoseServer] Listening on http://127.0.0.1:{PORT}", flush=True)
    print("[PoseServer] Endpoints: GET /cameras | POST /camera/select | GET /camera/capture | POST /pose | GET /health", flush=True)
    try:
        server.serve_forever()
    finally:
        camera_mgr.close()
        server.server_close()
        print("[PoseServer] Stopped.", flush=True)


if __name__ == "__main__":
    main()

