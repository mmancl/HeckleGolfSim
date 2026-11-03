#!/usr/bin/env python3
"""
Dedicated Putting Camera MJPEG Streaming Server
------------------------------------------------
Provides low-latency, high-framerate (30 FPS) MJPEG video streaming for local USB
webcams on desktop without any pose detection or MediaPipe overhead.

Endpoints:
  GET  /health           -> Server health & active camera index
  GET  /cameras          -> List available local webcams
  POST /camera/select    -> Select/open camera index (e.g. {"index": 0})
  GET  /camera/select    -> Select/open camera index via query param (e.g. ?index=0)
  GET  /video            -> Multipart MJPEG stream (multipart/x-mixed-replace)
  GET  /mjpegfeed        -> Alias for /video
  GET  /shot.jpg         -> Single JPEG snapshot
  GET  /shutdown         -> Gracefully shutdown server
"""

import sys
import os
import time
import json
import base64
import signal
import threading
import http.server
import urllib.parse

PORT = 49155

try:
    import cv2
except ImportError:
    print("[PuttingCamServer] FATAL: opencv-python (cv2) is required. Install via: pip install opencv-python", file=sys.stderr)
    sys.exit(1)


# ─── Parent Process Watchdog ────────────────────────────────────────────────
def start_parent_watchdog(parent_pid: int):
    """Monitors parent PID and exits if parent terminates."""
    def _watch():
        while True:
            time.sleep(2.0)
            try:
                if os.name == "nt":
                    import ctypes
                    SYNCHRONIZE = 0x00100000
                    handle = ctypes.windll.kernel32.OpenProcess(SYNCHRONIZE, False, parent_pid)
                    if handle == 0:
                        break
                    ctypes.windll.kernel32.CloseHandle(handle)
                else:
                    os.kill(parent_pid, 0)
            except (OSError, ProcessLookupError, PermissionError):
                break
        print(f"[PuttingCamServer] Parent process {parent_pid} terminated. Exiting.", flush=True)
        camera_mgr.close()
        os._exit(0)

    t = threading.Thread(target=_watch, daemon=True)
    t.start()


# ─── Camera Manager ─────────────────────────────────────────────────────────
class CameraManager:
    def __init__(self):
        self.lock = threading.Lock()
        self.cap = None
        self.active_index = -1
        self._running = False
        self._bg_thread = None
        self._last_frame = None
        self._last_ts_ns = 0
        self._frame_id = 0

    def scan_cameras(self) -> list:
        cams = []
        with self.lock:
            active_idx = self.active_index
            active_opened = self.cap is not None and self.cap.isOpened()

        for i in range(4):
            if active_opened and i == active_idx:
                cams.append({"index": i, "name": f"System Camera {i} (Active)"})
                continue

            cap = None
            if os.name == "nt":
                cap = cv2.VideoCapture(i, cv2.CAP_DSHOW)
                if not cap.isOpened():
                    cap.release()
                    cap = cv2.VideoCapture(i, cv2.CAP_MSMF)
                if not cap.isOpened():
                    cap.release()
                    cap = cv2.VideoCapture(i)
            else:
                cap = cv2.VideoCapture(i)

            if cap.isOpened():
                ret, _ = cap.read()
                if ret:
                    cams.append({"index": i, "name": f"System Camera {i}"})
                cap.release()
            else:
                cap.release()
                if i >= 1 and len(cams) == 0:
                    break
        return cams

    def _capture_worker(self):
        while self._running:
            with self.lock:
                cap = self.cap
            if cap is None or not cap.isOpened():
                time.sleep(0.01)
                continue
            ret, frame = cap.read()
            if ret and frame is not None:
                ts = time.monotonic_ns()
                with self.lock:
                    self._last_frame = frame
                    self._last_ts_ns = ts
                    self._frame_id += 1
            else:
                time.sleep(0.005)

    def select_camera(self, index: int) -> bool:
        with self.lock:
            if self.active_index == index and self.cap is not None and self.cap.isOpened():
                return True
            self._running = False
            if self.cap is not None:
                self.cap.release()
                self.cap = None
            self.active_index = -1
            self._last_frame = None

            if index < 0:
                print("[PuttingCamServer] Released system camera (camera deactivated)")
                return True

            cap = None
            if os.name == "nt":
                cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)
                if not cap.isOpened():
                    cap.release()
                    cap = cv2.VideoCapture(index, cv2.CAP_MSMF)
                if not cap.isOpened():
                    cap.release()
                    cap = cv2.VideoCapture(index)
            else:
                cap = cv2.VideoCapture(index)

            if cap is not None and cap.isOpened():
                # Force MJPG compression and 640x480 @ 30 FPS to prevent USB 2.0 bandwidth throttling
                try:
                    cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))
                except Exception:
                    pass
                try:
                    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
                    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
                    cap.set(cv2.CAP_PROP_FPS, 30)
                except Exception:
                    pass
                cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

                self.cap = cap
                self.active_index = index
                self._running = True
                self._bg_thread = threading.Thread(target=self._capture_worker, daemon=True)
                self._bg_thread.start()
                print(f"[PuttingCamServer] Activated system camera {index} (MJPEG 640x480 @ 30 FPS)", flush=True)
                return True
            else:
                if cap is not None:
                    cap.release()
                print(f"[PuttingCamServer] Failed to open system camera {index}", flush=True)
                return False

    def close(self):
        with self.lock:
            self._running = False
            if self.cap is not None:
                self.cap.release()
                self.cap = None
            self.active_index = -1
            self._last_frame = None


camera_mgr = CameraManager()


# ─── HTTP Handler ───────────────────────────────────────────────────────────
class PuttingCameraHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/camera/select":
            content_length = int(self.headers.get("Content-Length", 0))
            idx = -1
            if content_length > 0:
                body = self.rfile.read(content_length)
                try:
                    data = json.loads(body)
                    if "index" in data:
                        idx = int(data["index"])
                except Exception:
                    pass
            ok = camera_mgr.select_camera(idx)
            self._send_json(200, {"status": "ok" if ok else "error", "index": camera_mgr.active_index})
        else:
            self._send_json(404, {"error": "not found"})

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        if path == "/health":
            self._send_json(200, {
                "status": "ok",
                "service": "putting_camera",
                "pid": os.getpid(),
                "camera_active": camera_mgr.active_index >= 0,
                "camera_index": camera_mgr.active_index
            })
        elif path == "/cameras":
            cams = camera_mgr.scan_cameras()
            self._send_json(200, {"cameras": cams})
        elif path == "/camera/select":
            idx = int(query.get("index", [0])[0])
            ok = camera_mgr.select_camera(idx)
            self._send_json(200, {"status": "ok" if ok else "error", "index": camera_mgr.active_index})
        elif path == "/shot.jpg" or path == "/frame":
            # Single JPEG snapshot
            with camera_mgr.lock:
                frame = camera_mgr._last_frame
            if frame is None:
                self.send_response(503)
                self.end_headers()
                return
            h, w = frame.shape[:2]
            if w > 640:
                frame = cv2.resize(frame, (640, int(h * (640.0 / w))))
            encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 60]
            ret, jpg = cv2.imencode('.jpg', frame, encode_param)
            if not ret:
                self.send_response(500)
                self.end_headers()
                return
            jpg_bytes = jpg.tobytes()
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(jpg_bytes)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(jpg_bytes)
        elif path == "/video" or path == "/mjpeg" or path == "/mjpegfeed":
            # Multipart continuous MJPEG stream (30 FPS)
            self.send_response(200)
            self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
            self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
            self.send_header("Pragma", "no-cache")
            self.send_header("Connection", "close")
            self.end_headers()

            last_id = -1
            encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 60]
            try:
                while True:
                    with camera_mgr.lock:
                        frame = camera_mgr._last_frame
                        frame_id = camera_mgr._frame_id
                        running = camera_mgr._running

                    if not running or frame is None:
                        time.sleep(0.01)
                        continue

                    if frame_id != last_id:
                        last_id = frame_id
                        h, w = frame.shape[:2]
                        if w > 640:
                            frame = cv2.resize(frame, (640, int(h * (640.0 / w))))
                        ret, jpg = cv2.imencode('.jpg', frame, encode_param)
                        if ret:
                            jpg_bytes = jpg.tobytes()
                            header = (
                                b"--frame\r\n"
                                b"Content-Type: image/jpeg\r\n"
                                b"Content-Length: " + str(len(jpg_bytes)).encode("ascii") + b"\r\n\r\n"
                            )
                            self.wfile.write(header + jpg_bytes + b"\r\n")
                            self.wfile.flush()
                    time.sleep(0.01)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        elif path == "/shutdown":
            camera_mgr.close()
            self._send_json(200, {"status": "shutting down"})
            threading.Thread(target=lambda: (time.sleep(0.2), os._exit(0))).start()
        else:
            self._send_json(404, {"error": "not found"})

    def _send_json(self, code: int, data: dict):
        body = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Dedicated Putting Camera MJPEG Server")
    parser.add_argument("--port", type=int, default=PORT, help="Server port (default: 49155)")
    parser.add_argument("--parent-pid", type=int, default=0, help="Parent process ID to monitor")
    args, _ = parser.parse_known_args()

    if args.parent_pid > 0:
        start_parent_watchdog(args.parent_pid)

    port = args.port
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), PuttingCameraHandler)
    server.daemon_threads = True

    def _shutdown(sig, frame):
        print("\n[PuttingCamServer] Shutting down...", flush=True)
        camera_mgr.close()
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, _shutdown)
    signal.signal(signal.SIGINT, _shutdown)

    print(f"[PuttingCamServer] Listening on http://127.0.0.1:{port}", flush=True)
    print(f"[PuttingCamServer] Stream endpoint: http://127.0.0.1:{port}/video", flush=True)
    try:
        server.serve_forever()
    finally:
        camera_mgr.close()
        server.server_close()
        print("[PuttingCamServer] Stopped.", flush=True)


if __name__ == "__main__":
    main()
