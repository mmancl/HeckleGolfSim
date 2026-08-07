#!/usr/bin/env python3
"""
MediaPipe Pose Detection Server — Embedded Desktop Backend
Auto-started by Godot's PoseDetectionBridge for desktop/laptop testing.
Uses Google MediaPipe Tasks Vision Python SDK for accurate pose landmark detection.

Accepts JPEG frames via HTTP POST /pose, returns 33-landmark JSON response.
Model auto-downloads on first run (~30MB).
"""

import http.server
import json
import os
import signal
import sys
import threading

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


# ─── MediaPipe initialisation ───────────────────────────────────────────────────

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

# ─── HTTP handler ────────────────────────────────────────────────────────────────

class PoseHandler(http.server.BaseHTTPRequestHandler):
    """Handles /pose (POST) and /health (GET) endpoints."""

    def do_POST(self):
        if self.path != "/pose":
            self._send(404, {"error": "not found"})
            return

        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            self._send(200, {"detected": False, "landmarks": {}})
            return

        image_bytes = self.rfile.read(content_length)
        if not image_bytes:
            self._send(200, {"detected": False, "landmarks": {}})
            return

        try:
            result = self._detect(image_bytes)
            self._send(200, result)
        except Exception as exc:
            print(f"[PoseServer] Error: {exc}", file=sys.stderr)
            self._send(200, {"detected": False, "landmarks": {}, "error": str(exc)})

    def do_GET(self):
        if self.path == "/health":
            self._send(200, {"status": "ok", "model": MODEL_FILENAME})
        else:
            self._send(404, {"error": "not found"})

    # ── Internal helpers ─────────────────────────────────────────────────────

    @staticmethod
    def _detect(jpeg_bytes: bytes) -> dict:
        np_arr = np.frombuffer(jpeg_bytes, dtype=np.uint8)
        bgr = cv2.imdecode(np_arr, cv2.IMREAD_COLOR)
        if bgr is None:
            return {"detected": False, "landmarks": {}}

        rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        result = detector.detect(mp_image)

        if not result.pose_landmarks or len(result.pose_landmarks) == 0:
            return {"detected": False, "landmarks": {}}

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

        return {"detected": True, "landmarks": landmarks}

    def _send(self, code: int, data: dict):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Suppress per-request logging to keep console clean
        pass


# ─── Entry point ─────────────────────────────────────────────────────────────────

def main():
    server = http.server.HTTPServer(("127.0.0.1", PORT), PoseHandler)
    server.timeout = 1.0  # Allow periodic shutdown checks

    def _shutdown(sig, frame):
        print("\n[PoseServer] Shutting down...")
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    print(f"[PoseServer] Listening on http://127.0.0.1:{PORT}")
    print("[PoseServer] Endpoints:  POST /pose  |  GET /health")
    try:
        server.serve_forever()
    finally:
        server.server_close()
        print("[PoseServer] Stopped.")


if __name__ == "__main__":
    main()
