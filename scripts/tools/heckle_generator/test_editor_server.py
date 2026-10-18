#!/usr/bin/env python3
"""
Test script to verify Heckle Audio Editor backend endpoints.
"""
import urllib.request
import json
import threading
import time
import os
import sys

from heckle_editor import HeckleEditorHandler, HTTPServer, TARGET_JSON_PATHS

def run_tests():
    port = 8999
    server = HTTPServer(('127.0.0.1', port), HeckleEditorHandler)
    t = threading.Thread(target=server.serve_forever, daemon=True)
    t.start()
    time.sleep(0.5)

    base_url = f"http://127.0.0.1:{port}"

    try:
        # 1. Test HTML
        html_resp = urllib.request.urlopen(f"{base_url}/").read().decode("utf-8")
        assert "Heckle Audio & Commentary Editor" in html_resp, "HTML title missing"
        print("[PASS] GET / served HTML successfully.")

        # 2. Test /api/data
        data_resp = json.loads(urllib.request.urlopen(f"{base_url}/api/data").read().decode("utf-8"))
        assert "categories" in data_resp, "categories missing from /api/data"
        cat_count = len(data_resp["categories"])
        prompt_count = data_resp["stats"]["total_prompts"]
        assert cat_count == 18, f"Expected 18 categories, got {cat_count}"
        assert prompt_count == 770, f"Expected 770 prompts, got {prompt_count}"
        print(f"[PASS] GET /api/data returned {cat_count} categories and {prompt_count} prompts.")

        # 3. Test /api/audio
        audio_url = f"{base_url}/api/audio?path=res://assets/audio/heckler/under_par/under_par_0.wav"
        with urllib.request.urlopen(audio_url) as resp:
            audio_data = resp.read()
            mime = resp.headers.get("Content-Type")
            assert len(audio_data) > 0, "Audio data empty"
            assert mime in ("audio/wav", "audio/x-wav"), f"Wrong mime: {mime}"
        print(f"[PASS] GET /api/audio served {len(audio_data)} bytes of WAV audio ({mime}).")

        # 4. Test POST /api/save roundtrip
        save_payload = {
            "description": data_resp["description"],
            "categories": data_resp["categories"]
        }
        req = urllib.request.Request(
            f"{base_url}/api/save",
            data=json.dumps(save_payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )
        with urllib.request.urlopen(req) as resp:
            save_result = json.loads(resp.read().decode("utf-8"))
            assert save_result["success"] is True, "Save returned success=False"
            assert len(save_result["saved_paths"]) == 2, f"Expected 2 saved paths, got {save_result['saved_paths']}"
        print("[PASS] POST /api/save successfully saved and synchronized both files.")

        print("\nALL BACKEND ENDPOINT TESTS PASSED SUCCESSFULLY!")
    finally:
        server.shutdown()
        for p in TARGET_JSON_PATHS:
            bak = p + ".bak"
            if os.path.exists(bak):
                try:
                    os.remove(bak)
                except Exception:
                    pass

if __name__ == "__main__":
    run_tests()
