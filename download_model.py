#!/usr/bin/env python3
"""
Downloads the MediaPipe Pose Landmarker Full model (~30MB).
Run this ONCE before first use:
    python download_model.py

The model is saved to the mediapipe_server directory for use by pose_server.py.
For Android, copy the model to android/build/src/main/assets/.
"""

import os
import urllib.request
import sys
import shutil

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/"
    "pose_landmarker/pose_landmarker_full/float16/latest/"
    "pose_landmarker_full.task"
)
MODEL_FILENAME = "pose_landmarker_full.task"

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
SERVER_DIR = os.path.join(SCRIPT_DIR, "UI", "GolferCamera", "mediapipe_server")
ANDROID_ASSETS_DIR = os.path.join(SCRIPT_DIR, "android", "build", "src", "main", "assets")


def download_model(dest_path: str) -> None:
    if os.path.exists(dest_path):
        size_mb = os.path.getsize(dest_path) / (1024 * 1024)
        print(f"  ✓ Already exists: {dest_path} ({size_mb:.1f} MB)")
        return

    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    print(f"  ⬇ Downloading to: {dest_path}")
    print(f"    URL: {MODEL_URL}")

    def progress_hook(block_num, block_size, total_size):
        downloaded = block_num * block_size
        if total_size > 0:
            pct = min(100, downloaded * 100 // total_size)
            bar = "█" * (pct // 3) + "░" * (33 - pct // 3)
            sys.stdout.write(f"\r    [{bar}] {pct}%  ({downloaded // 1024 // 1024}MB / {total_size // 1024 // 1024}MB)")
            sys.stdout.flush()

    urllib.request.urlretrieve(MODEL_URL, dest_path, reporthook=progress_hook)
    size_mb = os.path.getsize(dest_path) / (1024 * 1024)
    print(f"\n  ✓ Downloaded: {size_mb:.1f} MB")


def main():
    print("=" * 60)
    print("MediaPipe Pose Landmarker Model Downloader")
    print("=" * 60)

    # 1. Download for desktop (Python server)
    desktop_path = os.path.join(SERVER_DIR, MODEL_FILENAME)
    print(f"\n📁 Desktop (Python server):")
    download_model(desktop_path)

    # 2. Copy for Android assets
    android_path = os.path.join(ANDROID_ASSETS_DIR, MODEL_FILENAME)
    print(f"\n📱 Android (APK assets):")
    if os.path.exists(desktop_path) and not os.path.exists(android_path):
        os.makedirs(ANDROID_ASSETS_DIR, exist_ok=True)
        shutil.copy2(desktop_path, android_path)
        print(f"  ✓ Copied to: {android_path}")
    elif os.path.exists(android_path):
        size_mb = os.path.getsize(android_path) / (1024 * 1024)
        print(f"  ✓ Already exists: {android_path} ({size_mb:.1f} MB)")
    else:
        download_model(android_path)

    print("\n✅ Done! Model ready for both desktop and Android.")
    print("=" * 60)


if __name__ == "__main__":
    main()
