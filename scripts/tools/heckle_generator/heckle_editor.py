#!/usr/bin/env python3
"""
Heckle Audio & Qualifier Editor
A standalone web-based GUI mini-app for reviewing, auditioning, and editing golf heckle audio,
qualifiers (score_type, tree_hit_type, strokes, gir, birdie_chance, tee_shot, close_to_pin),
and enabling/disabling audio lines.

Saves updates back to both:
  - assets/audio/heckler/heckle_prompts.json (Runtime Godot file)
  - scripts/tools/heckle_generator/heckle_prompts.json (Voice generator file)
"""

import os
import sys
import json
import socket
import argparse
import webbrowser
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
import mimetypes

# Determine workspace root and target JSON files
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", ".."))

TARGET_JSON_PATHS = [
    os.path.join(PROJECT_ROOT, "assets", "audio", "heckler", "heckle_prompts.json"),
    os.path.join(SCRIPT_DIR, "heckle_prompts.json"),
]

ALLOWED_QUALIFIERS = {
    "score_type": {
        "type": "enum",
        "description": "Allowed score relative to par (e.g. birdie, eagle, bogey)",
        "values": [
            "birdie",
            "eagle",
            "albatross",
            "hole_in_one",
            "double_bogey",
            "triple_bogey",
            "over_bogey",
            "under_par"
        ]
    },
    "game_mode": {
        "type": "enum",
        "description": "Target game mode (course_play, range, minigames)",
        "values": ["course_play", "range", "minigames"]
    },
    "min_score_relative_to_par": {
        "type": "int",
        "description": "Minimum strokes over par required (e.g. 15 or 20 for blowout heckles)",
        "placeholder": "e.g. 20"
    },
    "max_score_relative_to_par": {
        "type": "int",
        "description": "Maximum strokes over par allowed (e.g. 5)",
        "placeholder": "e.g. 5"
    },
    "score_status": {
        "type": "enum",
        "description": "Current player score status",
        "values": ["over_par", "under_par", "even_par"]
    },
    "overall_score": {
        "type": "enum",
        "description": "Overall round score relative to par",
        "values": ["over_par", "under_par", "even_par"]
    },
    "hole_range": {
        "type": "enum",
        "description": "Front nine (holes 1-9) vs back nine (holes 10-18)",
        "values": ["front_nine", "back_nine"]
    },
    "max_hole": {
        "type": "int",
        "description": "Maximum hole number (e.g. 2 for opening banter)",
        "placeholder": "e.g. 2"
    },
    "min_hole": {
        "type": "int",
        "description": "Minimum hole number (e.g. 10 for back nine)",
        "placeholder": "e.g. 10"
    },
    "surface": {
        "type": "enum",
        "description": "Required surface type",
        "values": ["sand", "water", "green", "fairway", "rough"]
    },
    "tee_box": {
        "type": "bool",
        "description": "Ball or player on tee box",
        "values": [True, False]
    },
    "tree_hit_type": {
        "type": "enum",
        "description": "Tree collision type (trunk impact vs canopy leaves/branches)",
        "values": ["trunk", "leaves"]
    },
    "gir": {
        "type": "bool",
        "description": "Green in Regulation reached on this stroke",
        "values": [True, False]
    },
    "birdie_chance": {
        "type": "bool",
        "description": "Putt or approach for birdie",
        "values": [True, False]
    },
    "tee_shot": {
        "type": "bool",
        "description": "Shot hit off the tee box (stroke 1)",
        "values": [True, False]
    },
    "close_to_pin": {
        "type": "bool",
        "description": "Ball landed within 4 yards (12 feet) of the pin",
        "values": [True, False]
    },
    "is_iron": {
        "type": "bool",
        "description": "Whether the shot was hit using an iron (1i-9i)",
        "values": [True, False]
    },
    "min_backspin": {
        "type": "int",
        "description": "Minimum backspin RPM required (e.g. 8000 for backspin praise)",
        "placeholder": "e.g. 8000"
    },
    "strokes": {
        "type": "int",
        "description": "Exact stroke count required (e.g. 8 for snowman heckles)",
        "placeholder": "e.g. 8"
    },
    "high_apex": {
        "type": "bool",
        "description": "Whether the shot reached a high apex or popup balloon trajectory",
        "values": [True, False]
    },
    "min_apex_ft": {
        "type": "int",
        "description": "Minimum apex height in feet (e.g. 100 or 115)",
        "placeholder": "e.g. 115"
    }
}

def load_prompts_json():
    """Load JSON from the primary runtime path or generator path."""
    for path in TARGET_JSON_PATHS:
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception as e:
                print(f"[WARN] Failed to load {path}: {e}")
    raise FileNotFoundError("Could not locate heckle_prompts.json in any expected directory.")

def save_prompts_json(data):
    """Save JSON to all target paths with backups."""
    if not isinstance(data, dict) or "categories" not in data:
        raise ValueError("Invalid JSON format: missing 'categories' object.")

    saved_paths = []
    formatted = json.dumps(data, indent=4, ensure_ascii=False) + "\n"

    for path in TARGET_JSON_PATHS:
        # Create directory if needed
        os.makedirs(os.path.dirname(path), exist_ok=True)
        # Create backup if file exists
        if os.path.exists(path):
            bak_path = path + ".bak"
            try:
                with open(path, "r", encoding="utf-8") as src, open(bak_path, "w", encoding="utf-8") as dst:
                    dst.write(src.read())
            except Exception as e:
                print(f"[WARN] Could not create backup at {bak_path}: {e}")
        # Write new content
        with open(path, "w", encoding="utf-8") as f:
            f.write(formatted)
        saved_paths.append(path)
    return saved_paths

def resolve_audio_path(res_path):
    """Translate 'res://...' Godot path to an absolute filesystem path."""
    if not res_path:
        return None
    clean = res_path.replace("res://", "").replace("\\", "/")
    abs_path = os.path.abspath(os.path.join(PROJECT_ROOT, clean))
    # Security check: must reside inside PROJECT_ROOT
    if not abs_path.startswith(PROJECT_ROOT):
        return None
    return abs_path

def get_stats(data):
    """Compute overall prompt counts."""
    categories = data.get("categories", {})
    total = 0
    enabled = 0
    disabled = 0
    qualified = 0

    for cat_name, prompts in categories.items():
        for p in prompts:
            total += 1
            if p.get("enabled", True):
                enabled += 1
            else:
                disabled += 1
            if p.get("qualifiers"):
                qualified += 1

    return {
        "total_prompts": total,
        "enabled_count": enabled,
        "disabled_count": disabled,
        "qualified_count": qualified,
        "category_count": len(categories)
    }

class HeckleEditorHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Keep console output minimal and tidy
        if args and str(args[1]) in ("404", "500"):
            super().log_message(format, *args)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/" or path == "/index.html":
            self.serve_html()
        elif path == "/api/data":
            self.serve_api_data()
        elif path == "/api/audio":
            self.serve_audio(parsed.query)
        else:
            self.send_error(404, "Not Found")

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/api/save":
            self.handle_api_save()
        else:
            self.send_error(404, "Not Found")

    def serve_html(self):
        html_bytes = HTML_TEMPLATE.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(html_bytes)))
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.end_headers()
        self.wfile.write(html_bytes)

    def serve_api_data(self):
        try:
            data = load_prompts_json()
            stats = get_stats(data)
            payload = {
                "description": data.get("description", ""),
                "categories": data.get("categories", {}),
                "stats": stats,
                "allowed_qualifiers": ALLOWED_QUALIFIERS,
                "target_paths": [os.path.relpath(p, PROJECT_ROOT) for p in TARGET_JSON_PATHS]
            }
            resp_bytes = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(resp_bytes)))
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()
            self.wfile.write(resp_bytes)
        except Exception as e:
            err_msg = json.dumps({"error": str(e)}).encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(err_msg)))
            self.end_headers()
            self.wfile.write(err_msg)

    def serve_audio(self, query_str):
        params = urllib.parse.parse_qs(query_str)
        res_path = params.get("path", [""])[0]
        if not res_path:
            self.send_error(400, "Missing 'path' query parameter")
            return

        abs_file = resolve_audio_path(res_path)
        if not abs_file or not os.path.isfile(abs_file):
            self.send_error(404, f"Audio file not found: {res_path}")
            return

        try:
            file_size = os.path.getsize(abs_file)
            mime_type, _ = mimetypes.guess_type(abs_file)
            if not mime_type:
                mime_type = "audio/wav"

            with open(abs_file, "rb") as f:
                content = f.read()

            self.send_response(200)
            self.send_header("Content-Type", mime_type)
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Cache-Control", "public, max-age=3600")
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self.send_error(500, f"Error streaming audio: {e}")

    def handle_api_save(self):
        try:
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            data = json.loads(body)

            saved = save_prompts_json(data)
            stats = get_stats(data)

            resp = {
                "success": True,
                "saved_paths": [os.path.relpath(p, PROJECT_ROOT) for p in saved],
                "stats": stats
            }
            resp_bytes = json.dumps(resp).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(resp_bytes)))
            self.end_headers()
            self.wfile.write(resp_bytes)
        except Exception as e:
            err = json.dumps({"success": False, "error": str(e)}).encode("utf-8")
            self.send_response(500)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(err)))
            self.end_headers()
            self.wfile.write(err)

def find_open_port(preferred_port=8088):
    for port in range(preferred_port, preferred_port + 50):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    return preferred_port

HTML_TEMPLATE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Heckle Audio & Commentary Editor</title>
<style>
  :root {
    --bg-main: #0c111d;
    --bg-card: #151d30;
    --bg-card-hover: #1c2640;
    --bg-sidebar: #0f172a;
    --bg-input: #1e293b;
    --border: #2a3754;
    --border-highlight: #3b82f6;
    --text-primary: #f8fafc;
    --text-secondary: #94a3b8;
    --text-muted: #64748b;
    --accent: #10b981;
    --accent-hover: #059669;
    --accent-blue: #3b82f6;
    --accent-amber: #f59e0b;
    --accent-red: #ef4444;
    --accent-purple: #8b5cf6;
    --tag-bg: #1e293b;
    --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg-main);
    color: var(--text-primary);
    font-family: var(--font);
    display: flex;
    flex-direction: column;
    height: 100vh;
    overflow: hidden;
  }

  /* Top Navigation Bar */
  header {
    background: var(--bg-sidebar);
    border-bottom: 1px solid var(--border);
    padding: 10px 20px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 15px;
    flex-shrink: 0;
    z-index: 50;
  }
  .brand {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .brand-icon {
    font-size: 24px;
    background: #064e3b;
    color: #34d399;
    width: 38px;
    height: 38px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1px solid #059669;
  }
  .brand-title {
    font-size: 17px;
    font-weight: 700;
    letter-spacing: -0.3px;
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .brand-badge {
    background: #1e293b;
    color: #94a3b8;
    font-size: 11px;
    padding: 2px 7px;
    border-radius: 12px;
    border: 1px solid var(--border);
    font-weight: 500;
  }

  .stats-bar {
    display: flex;
    align-items: center;
    gap: 8px;
    background: #090e17;
    padding: 4px 12px;
    border-radius: 20px;
    border: 1px solid var(--border);
    font-size: 12px;
  }
  .stat-item {
    display: flex;
    align-items: center;
    gap: 5px;
    color: var(--text-secondary);
  }
  .stat-val {
    font-weight: 700;
    color: var(--text-primary);
  }
  .stat-divider { color: var(--border); }
  .stat-val.enabled { color: #34d399; }
  .stat-val.disabled { color: #f87171; }
  .stat-val.qualified { color: #60a5fa; }

  .nav-actions {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .dirty-badge {
    display: none;
    align-items: center;
    gap: 6px;
    background: rgba(245, 158, 11, 0.15);
    border: 1px solid var(--accent-amber);
    color: var(--accent-amber);
    font-size: 12px;
    font-weight: 600;
    padding: 5px 12px;
    border-radius: 6px;
    animation: pulse 2s infinite;
  }
  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.7; }
  }
  .btn {
    background: var(--bg-input);
    color: var(--text-primary);
    border: 1px solid var(--border);
    padding: 7px 14px;
    border-radius: 6px;
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    transition: all 0.15s ease;
  }
  .btn:hover {
    background: #2a3754;
    border-color: #475569;
  }
  .btn-primary {
    background: var(--accent);
    color: #fff;
    border-color: var(--accent-hover);
  }
  .btn-primary:hover {
    background: var(--accent-hover);
  }
  .btn-primary:disabled {
    background: #1e293b;
    border-color: var(--border);
    color: #64748b;
    cursor: not-allowed;
  }

  /* Main Layout */
  .workspace {
    display: flex;
    flex: 1;
    overflow: hidden;
  }

  /* Sidebar */
  aside {
    width: 310px;
    background: var(--bg-sidebar);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    flex-shrink: 0;
  }
  .sidebar-header {
    padding: 12px 14px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .sidebar-title {
    font-size: 12px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--text-muted);
    display: flex;
    justify-content: space-between;
  }
  .search-box {
    position: relative;
    width: 100%;
  }
  .search-input {
    width: 100%;
    background: var(--bg-input);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 7px 10px 7px 30px;
    color: var(--text-primary);
    font-size: 13px;
    outline: none;
    transition: border 0.15s;
  }
  .search-input:focus { border-color: var(--border-highlight); }
  .search-icon {
    position: absolute;
    left: 9px;
    top: 50%;
    transform: translateY(-50%);
    font-size: 13px;
    color: var(--text-muted);
    pointer-events: none;
  }

  .category-list {
    flex: 1;
    overflow-y: auto;
    padding: 8px;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .category-item {
    padding: 8px 12px;
    border-radius: 6px;
    font-size: 13px;
    color: var(--text-secondary);
    display: flex;
    align-items: center;
    justify-content: space-between;
    cursor: pointer;
    border: 1px solid transparent;
    transition: all 0.12s;
    user-select: none;
  }
  .category-item:hover {
    background: #1e293b;
    color: var(--text-primary);
  }
  .category-item.active {
    background: #1e293b;
    color: #fff;
    border-color: var(--border-highlight);
    font-weight: 600;
  }
  .category-name-group {
    display: flex;
    align-items: center;
    gap: 8px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .cat-pill {
    font-size: 11px;
    padding: 2px 6px;
    border-radius: 10px;
    background: #090e17;
    border: 1px solid var(--border);
    font-weight: 600;
    color: var(--text-muted);
  }
  .cat-pill.has-disabled {
    border-color: rgba(245, 158, 11, 0.4);
    color: var(--accent-amber);
    background: rgba(245, 158, 11, 0.08);
  }
  .cat-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: #34d399;
  }
  .cat-dot.has-disabled { background: var(--accent-amber); }

  /* Main Content Area */
  main {
    flex: 1;
    display: flex;
    flex-direction: column;
    background: var(--bg-main);
    overflow: hidden;
  }

  /* Subheader / Filter Bar */
  .filter-bar {
    padding: 12px 24px;
    background: var(--bg-sidebar);
    border-bottom: 1px solid var(--border);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 15px;
    flex-wrap: wrap;
  }
  .current-cat-header {
    display: flex;
    align-items: baseline;
    gap: 10px;
  }
  .current-cat-title {
    font-size: 18px;
    font-weight: 700;
    color: var(--text-primary);
  }
  .current-cat-count {
    font-size: 13px;
    color: var(--text-secondary);
  }

  .filter-controls {
    display: flex;
    align-items: center;
    gap: 10px;
    flex-wrap: wrap;
  }
  .filter-select {
    background: var(--bg-input);
    border: 1px solid var(--border);
    color: var(--text-primary);
    padding: 6px 10px;
    border-radius: 6px;
    font-size: 12px;
    outline: none;
    cursor: pointer;
  }
  .filter-select:focus { border-color: var(--border-highlight); }

  .batch-actions {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .btn-sm {
    padding: 5px 10px;
    font-size: 12px;
  }

  /* Prompts Container */
  .prompts-container {
    flex: 1;
    overflow-y: auto;
    padding: 20px 24px;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  /* Prompt Card */
  .prompt-card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 12px;
    transition: border-color 0.15s, background 0.15s, opacity 0.2s;
    position: relative;
  }
  .prompt-card:hover {
    border-color: #3b4e74;
    background: var(--bg-card-hover);
  }
  .prompt-card.disabled {
    opacity: 0.65;
    background: #111726;
    border-color: #272c3d;
  }
  .prompt-card.disabled:hover {
    opacity: 0.85;
  }
  .prompt-card.playing {
    border-color: var(--accent);
    box-shadow: 0 0 0 1px var(--accent);
  }

  .card-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }
  .card-meta {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 12px;
  }
  .card-idx {
    background: #090e17;
    color: var(--text-muted);
    padding: 2px 7px;
    border-radius: 4px;
    font-family: monospace;
    font-size: 11px;
    border: 1px solid var(--border);
  }
  .card-file {
    color: var(--text-secondary);
    font-family: monospace;
    font-size: 12px;
  }

  .card-actions {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  /* Audio Play Button */
  .play-btn {
    background: #064e3b;
    color: #34d399;
    border: 1px solid #059669;
    padding: 5px 12px;
    border-radius: 20px;
    font-size: 12px;
    font-weight: 700;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 6px;
    transition: all 0.15s;
  }
  .play-btn:hover {
    background: #047857;
    color: #fff;
  }
  .play-btn.playing {
    background: var(--accent-red);
    color: #fff;
    border-color: #dc2626;
  }

  /* Toggle Switch */
  .switch-container {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    font-weight: 600;
    user-select: none;
    cursor: pointer;
  }
  .switch {
    position: relative;
    display: inline-block;
    width: 36px;
    height: 20px;
  }
  .switch input { opacity: 0; width: 0; height: 0; }
  .slider {
    position: absolute;
    cursor: pointer;
    top: 0; left: 0; right: 0; bottom: 0;
    background-color: #334155;
    transition: .2s;
    border-radius: 20px;
  }
  .slider:before {
    position: absolute;
    content: "";
    height: 14px;
    width: 14px;
    left: 3px;
    bottom: 3px;
    background-color: white;
    transition: .2s;
    border-radius: 50%;
  }
  input:checked + .slider {
    background-color: var(--accent);
  }
  input:checked + .slider:before {
    transform: translateX(16px);
  }
  .switch-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }
  .switch-label.enabled { color: #34d399; }
  .switch-label.disabled { color: #f87171; }

  /* Spoken Dialogue Section */
  .dialogue-box {
    display: flex;
    flex-direction: column;
    gap: 8px;
    background: #0b101b;
    border-radius: 6px;
    padding: 10px 14px;
    border: 1px solid #1f2b42;
  }
  .speaker-line {
    display: flex;
    align-items: flex-start;
    gap: 12px;
  }
  .speaker-pill {
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    flex-shrink: 0;
    width: 120px;
    text-align: center;
  }
  .speaker-connor { background: #1e3a5f; color: #93c5fd; border: 1px solid #2563eb; }
  .speaker-sophia { background: #4c1d95; color: #d8b4fe; border: 1px solid #7c3aed; }
  .speaker-other { background: #374151; color: #d1d5db; border: 1px solid #4b5563; }

  .speaker-text {
    flex: 1;
    font-size: 14px;
    line-height: 1.45;
    color: var(--text-primary);
  }
  .speaker-text-input {
    width: 100%;
    background: transparent;
    border: 1px solid transparent;
    color: var(--text-primary);
    font-family: inherit;
    font-size: 14px;
    line-height: 1.4;
    resize: vertical;
    border-radius: 4px;
    padding: 2px 6px;
  }
  .speaker-text-input:hover {
    border-color: #334155;
    background: #111827;
  }
  .speaker-text-input:focus {
    border-color: var(--border-highlight);
    background: #111827;
    outline: none;
  }

  /* Qualifiers Section */
  .qualifiers-section {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding-top: 4px;
    border-top: 1px solid #1f2b42;
  }
  .qualifiers-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--text-muted);
  }
  .qualifier-tags {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    align-items: center;
  }
  .tag {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 3px 8px;
    border-radius: 4px;
    font-size: 12px;
    font-weight: 500;
    border: 1px solid var(--border);
    background: var(--tag-bg);
  }
  .tag-score { border-color: #2563eb; color: #93c5fd; background: rgba(37, 99, 235, 0.12); }
  .tag-tree { border-color: #059669; color: #6ee7b7; background: rgba(5, 150, 105, 0.12); }
  .tag-strokes { border-color: #d97706; color: #fcd34d; background: rgba(217, 119, 6, 0.12); }
  .tag-flag { border-color: #7c3aed; color: #c4b5fd; background: rgba(124, 58, 237, 0.12); }
  .tag-custom { border-color: #64748b; color: #cbd5e1; background: rgba(100, 116, 139, 0.12); }

  .tag-remove {
    cursor: pointer;
    font-size: 13px;
    font-weight: bold;
    color: var(--text-muted);
    transition: color 0.1s;
    line-height: 1;
  }
  .tag-remove:hover { color: #f87171; }

  .no-qualifiers-hint {
    font-size: 12px;
    color: var(--text-muted);
    font-style: italic;
  }

  /* Inline Qualifier Adder */
  .add-qualifier-row {
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;
    margin-top: 2px;
  }
  .qual-select {
    background: var(--bg-input);
    border: 1px solid var(--border);
    color: var(--text-primary);
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 12px;
    outline: none;
  }
  .qual-select:focus { border-color: var(--border-highlight); }
  .qual-input {
    background: var(--bg-input);
    border: 1px solid var(--border);
    color: var(--text-primary);
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 12px;
    outline: none;
    width: 90px;
  }
  .qual-input:focus { border-color: var(--border-highlight); }

  /* Floating Bottom Player Bar */
  .bottom-player {
    background: #090e17;
    border-top: 1px solid var(--border);
    padding: 10px 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
    flex-shrink: 0;
  }
  .now-playing-info {
    display: flex;
    align-items: center;
    gap: 12px;
    flex: 1;
    overflow: hidden;
  }
  .now-playing-icon {
    font-size: 20px;
    color: var(--accent);
  }
  .now-playing-details {
    display: flex;
    flex-direction: column;
    gap: 2px;
    overflow: hidden;
  }
  .now-playing-title {
    font-size: 12px;
    font-weight: 700;
    color: var(--text-primary);
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .now-playing-text {
    font-size: 12px;
    color: var(--text-secondary);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .player-controls {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .volume-slider {
    width: 80px;
    accent-color: var(--accent);
    cursor: pointer;
  }

  /* Toast Notification */
  .toast {
    position: fixed;
    bottom: 80px;
    right: 24px;
    background: #064e3b;
    border: 1px solid #059669;
    color: #ecfdf5;
    padding: 12px 18px;
    border-radius: 8px;
    font-size: 13px;
    font-weight: 600;
    box-shadow: 0 10px 25px rgba(0,0,0,0.5);
    z-index: 100;
    opacity: 0;
    transform: translateY(10px);
    transition: all 0.25s ease;
    pointer-events: none;
  }
  .toast.show {
    opacity: 1;
    transform: translateY(0);
    pointer-events: auto;
  }
  .toast.error {
    background: #7f1d1d;
    border-color: #dc2626;
    color: #fef2f2;
  }
</style>
</head>
<body>

<!-- Top Navigation -->
<header>
  <div class="brand">
    <div class="brand-icon">🎙️</div>
    <div>
      <div class="brand-title">
        Heckle Audio & Qualifier Editor
        <span class="brand-badge">Standalone Tool</span>
      </div>
    </div>
  </div>

  <div class="stats-bar">
    <div class="stat-item">Total: <span id="stat-total" class="stat-val">0</span></div>
    <span class="stat-divider">|</span>
    <div class="stat-item">Enabled: <span id="stat-enabled" class="stat-val enabled">0</span></div>
    <span class="stat-divider">|</span>
    <div class="stat-item">Disabled: <span id="stat-disabled" class="stat-val disabled">0</span></div>
    <span class="stat-divider">|</span>
    <div class="stat-item">Qualified: <span id="stat-qualified" class="stat-val qualified">0</span></div>
  </div>

  <div class="nav-actions">
    <div id="dirty-badge" class="dirty-badge">
      <span>●</span> <span id="dirty-count">0</span> Unsaved Edits
    </div>
    <button id="discard-btn" class="btn" style="display:none;" onclick="discardChanges()">Discard</button>
    <button id="save-btn" class="btn btn-primary" onclick="saveChanges()" title="Save changes to disk (Ctrl+S)">
      <span>💾</span> Save to Disk
    </button>
  </div>
</header>

<!-- Main Workspace -->
<div class="workspace">
  <!-- Sidebar -->
  <aside>
    <div class="sidebar-header">
      <div class="sidebar-title">
        <span>Categories (<span id="cat-count">0</span>)</span>
      </div>
      <div class="search-box">
        <span class="search-icon">🔍</span>
        <input type="text" id="cat-search" class="search-input" placeholder="Search categories..." oninput="filterCategories()">
      </div>
    </div>
    <div id="category-list" class="category-list">
      <!-- Populated by JS -->
    </div>
  </aside>

  <!-- Content Area -->
  <main>
    <!-- Filter Subheader -->
    <div class="filter-bar">
      <div class="current-cat-header">
        <div id="current-cat-title" class="current-cat-title">All Prompts</div>
        <div id="current-cat-count" class="current-cat-count">Loading...</div>
      </div>

      <div class="filter-controls">
        <div class="search-box" style="width: 220px;">
          <span class="search-icon">🔍</span>
          <input type="text" id="prompt-search" class="search-input" placeholder="Search voice lines..." oninput="renderPrompts()">
        </div>

        <select id="status-filter" class="filter-select" onchange="renderPrompts()">
          <option value="all">Status: All</option>
          <option value="enabled">Enabled Only</option>
          <option value="disabled">Disabled Only</option>
        </select>

        <select id="qualifier-filter" class="filter-select" onchange="renderPrompts()">
          <option value="all">Qualifiers: All</option>
          <option value="has_qual">Has Qualifiers</option>
          <option value="no_qual">No Qualifiers (General)</option>
          <option value="score_type">Has score_type</option>
          <option value="tree_hit_type">Has tree_hit_type</option>
          <option value="strokes">Has strokes</option>
          <option value="gir">Has GIR</option>
          <option value="birdie_chance">Has Birdie Chance</option>
        </select>

        <select id="speaker-filter" class="filter-select" onchange="renderPrompts()">
          <option value="all">Speaker: All</option>
          <option value="Connor">Connor</option>
          <option value="Sophia">Sophia</option>
        </select>

        <div class="batch-actions">
          <button class="btn btn-sm" onclick="batchSetCurrentCategory(true)" title="Enable all prompts in currently viewed category">✓ Enable All</button>
          <button class="btn btn-sm" onclick="batchSetCurrentCategory(false)" title="Disable all prompts in currently viewed category">✕ Disable All</button>
        </div>
      </div>
    </div>

    <!-- Prompts Cards -->
    <div id="prompts-container" class="prompts-container">
      <!-- Populated by JS -->
    </div>
  </main>
</div>

<!-- Floating Bottom Player -->
<div class="bottom-player">
  <div class="now-playing-info">
    <div class="now-playing-icon">🔊</div>
    <div class="now-playing-details">
      <div id="now-playing-title" class="now-playing-title">Ready to audition audio</div>
      <div id="now-playing-text" class="now-playing-text">Select any prompt card above to play its commentary line.</div>
    </div>
  </div>

  <div class="player-controls">
    <button id="global-play-btn" class="btn btn-sm" onclick="toggleGlobalAudio()" disabled>▶ Play</button>
    <button class="btn btn-sm" onclick="replayGlobalAudio()" title="Replay">↺</button>
    <label style="font-size: 11px; color: var(--text-muted); display:flex; align-items:center; gap:6px;">
      Vol:
      <input type="range" id="vol-slider" class="volume-slider" min="0" max="1" step="0.05" value="0.9" oninput="setGlobalVolume(this.value)">
    </label>
  </div>
</div>

<div id="toast" class="toast">Changes saved successfully!</div>

<!-- Global Hidden Audio Element -->
<audio id="audio-engine" preload="auto"></audio>

<script>
// Application State
let appData = {
  description: "",
  categories: {},
  stats: {},
  allowed_qualifiers: {}
};

let originalJsonStr = "";
let selectedCategory = "all";
let currentlyPlayingCardId = null;
let currentAudioPath = null;
let currentPromptRef = null;

const audioEngine = document.getElementById("audio-engine");
const globalPlayBtn = document.getElementById("global-play-btn");

// Init
window.addEventListener("DOMContentLoaded", () => {
  fetchData();

  // Global Keyboard Shortcuts
  window.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
      e.preventDefault();
      saveChanges();
    }
  });

  // Warn on close if unsaved changes
  window.addEventListener("beforeunload", (e) => {
    if (isDirty()) {
      e.preventDefault();
      e.returnValue = "You have unsaved changes!";
    }
  });

  // Audio Engine listeners
  audioEngine.addEventListener("ended", () => {
    updatePlayingUi(null);
  });
  audioEngine.addEventListener("pause", () => {
    if (audioEngine.currentTime > 0 && !audioEngine.ended) {
      updatePlayingUi(null, true);
    }
  });
});

async function fetchData() {
  try {
    const res = await fetch("/api/data");
    const json = await res.json();
    appData = json;
    originalJsonStr = JSON.stringify(appData.categories);
    updateStats();
    renderCategories();
    renderPrompts();
    checkDirtyState();
  } catch (err) {
    showToast("Error loading prompt data: " + err, true);
  }
}

function isDirty() {
  return JSON.stringify(appData.categories) !== originalJsonStr;
}

function checkDirtyState() {
  const dirty = isDirty();
  const dirtyBadge = document.getElementById("dirty-badge");
  const discardBtn = document.getElementById("discard-btn");
  const saveBtn = document.getElementById("save-btn");

  if (dirty) {
    // Count modified prompts
    let diffCount = 0;
    const origCats = JSON.parse(originalJsonStr);
    for (const cat in appData.categories) {
      const origList = origCats[cat] || [];
      const currList = appData.categories[cat] || [];
      for (let i = 0; i < currList.length; i++) {
        if (JSON.stringify(currList[i]) !== JSON.stringify(origList[i])) {
          diffCount++;
        }
      }
    }
    document.getElementById("dirty-count").textContent = diffCount;
    dirtyBadge.style.display = "inline-flex";
    discardBtn.style.display = "inline-flex";
    saveBtn.disabled = false;
  } else {
    dirtyBadge.style.display = "none";
    discardBtn.style.display = "none";
    saveBtn.disabled = false;
  }
  updateStats();
}

function discardChanges() {
  if (confirm("Discard all unsaved edits and reload from disk?")) {
    appData.categories = JSON.parse(originalJsonStr);
    renderCategories();
    renderPrompts();
    checkDirtyState();
    showToast("Edits discarded. Reloaded from disk.");
  }
}

async function saveChanges() {
  const saveBtn = document.getElementById("save-btn");
  saveBtn.disabled = true;
  saveBtn.innerHTML = "<span>⏳</span> Saving...";

  try {
    const res = await fetch("/api/save", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        description: appData.description,
        categories: appData.categories
      })
    });
    const result = await res.json();
    if (result.success) {
      originalJsonStr = JSON.stringify(appData.categories);
      checkDirtyState();
      showToast("✅ Successfully saved to runtime and generator JSON files!");
    } else {
      showToast("❌ Error saving: " + result.error, true);
    }
  } catch (err) {
    showToast("❌ Network error saving: " + err, true);
  } finally {
    saveBtn.disabled = false;
    saveBtn.innerHTML = "<span>💾</span> Save to Disk";
  }
}

function updateStats() {
  let total = 0, enabled = 0, disabled = 0, qualified = 0;
  for (const cat in appData.categories) {
    for (const p of appData.categories[cat]) {
      total++;
      if (p.enabled !== false) enabled++;
      else disabled++;
      if (p.qualifiers && Object.keys(p.qualifiers).length > 0) qualified++;
    }
  }
  document.getElementById("stat-total").textContent = total;
  document.getElementById("stat-enabled").textContent = enabled;
  document.getElementById("stat-disabled").textContent = disabled;
  document.getElementById("stat-qualified").textContent = qualified;
}

function formatCategoryTitle(cat) {
  return cat.replace(/_/g, " ").replace(/\b\w/g, c => c.toUpperCase());
}

function renderCategories() {
  const list = document.getElementById("category-list");
  list.innerHTML = "";
  const filter = (document.getElementById("cat-search").value || "").toLowerCase();

  const categories = Object.keys(appData.categories);
  document.getElementById("cat-count").textContent = categories.length;

  // "All Categories" Item
  let totalAll = 0, disAll = 0;
  categories.forEach(c => {
    appData.categories[c].forEach(p => {
      totalAll++;
      if (p.enabled === false) disAll++;
    });
  });

  const allItem = document.createElement("div");
  allItem.className = `category-item ${selectedCategory === "all" ? "active" : ""}`;
  allItem.onclick = () => selectCategory("all");
  allItem.innerHTML = `
    <div class="category-name-group">
      <div class="cat-dot ${disAll > 0 ? "has-disabled" : ""}"></div>
      <span>All Categories</span>
    </div>
    <span class="cat-pill ${disAll > 0 ? "has-disabled" : ""}">${totalAll - disAll}/${totalAll}</span>
  `;
  list.appendChild(allItem);

  categories.forEach(cat => {
    if (filter && !cat.toLowerCase().includes(filter)) return;

    let catTotal = appData.categories[cat].length;
    let catDisabled = appData.categories[cat].filter(p => p.enabled === false).length;
    let catEnabled = catTotal - catDisabled;

    const item = document.createElement("div");
    item.className = `category-item ${selectedCategory === cat ? "active" : ""}`;
    item.onclick = () => selectCategory(cat);
    item.innerHTML = `
      <div class="category-name-group" title="${cat}">
        <div class="cat-dot ${catDisabled > 0 ? "has-disabled" : ""}"></div>
        <span>${formatCategoryTitle(cat)}</span>
      </div>
      <span class="cat-pill ${catDisabled > 0 ? "has-disabled" : ""}">
        ${catEnabled}/${catTotal}
      </span>
    `;
    list.appendChild(item);
  });
}

function filterCategories() {
  renderCategories();
}

function selectCategory(cat) {
  selectedCategory = cat;
  renderCategories();
  renderPrompts();
}

function renderPrompts() {
  const container = document.getElementById("prompts-container");
  container.innerHTML = "";

  const searchText = (document.getElementById("prompt-search").value || "").toLowerCase();
  const statusFilter = document.getElementById("status-filter").value;
  const qualFilter = document.getElementById("qualifier-filter").value;
  const speakerFilter = document.getElementById("speaker-filter").value;

  // Header Title
  const titleEl = document.getElementById("current-cat-title");
  titleEl.textContent = selectedCategory === "all" ? "All Categories" : formatCategoryTitle(selectedCategory);

  const targetCats = selectedCategory === "all" ? Object.keys(appData.categories) : [selectedCategory];

  let totalMatched = 0;
  let totalInCat = 0;

  targetCats.forEach(cat => {
    const list = appData.categories[cat] || [];
    totalInCat += list.length;

    list.forEach((promptObj, idx) => {
      // Filters
      const isEnabled = promptObj.enabled !== false;
      if (statusFilter === "enabled" && !isEnabled) return;
      if (statusFilter === "disabled" && isEnabled) return;

      const quals = promptObj.qualifiers || {};
      const qualKeys = Object.keys(quals);
      if (qualFilter === "has_qual" && qualKeys.length === 0) return;
      if (qualFilter === "no_qual" && qualKeys.length > 0) return;
      if (qualFilter !== "all" && qualFilter !== "has_qual" && qualFilter !== "no_qual") {
        if (!quals.hasOwnProperty(qualFilter)) return;
      }

      if (speakerFilter !== "all") {
        const matchesSpeaker = (promptObj.name && promptObj.name.toLowerCase() === speakerFilter.toLowerCase()) ||
                               (promptObj.follow_up && promptObj.follow_up.name && promptObj.follow_up.name.toLowerCase() === speakerFilter.toLowerCase());
        if (!matchesSpeaker) return;
      }

      if (searchText) {
        const textToSearch = [
          promptObj.prompt || "",
          promptObj.name || "",
          (promptObj.follow_up && promptObj.follow_up.prompt) || "",
          (promptObj.follow_up && promptObj.follow_up.name) || "",
          promptObj.filepath || "",
          JSON.stringify(quals)
        ].join(" ").toLowerCase();
        if (!textToSearch.includes(searchText)) return;
      }

      totalMatched++;
      // Render Card
      const card = createPromptCard(cat, idx, promptObj);
      container.appendChild(card);
    });
  });

  document.getElementById("current-cat-count").textContent = `Showing ${totalMatched} of ${totalInCat} prompts`;
  if (totalMatched === 0) {
    container.innerHTML = `
      <div style="text-align:center; padding: 60px 20px; color: var(--text-muted);">
        <div style="font-size: 32px; margin-bottom: 10px;">🔍</div>
        <div style="font-size: 16px; font-weight: 600;">No prompts match your current filters.</div>
        <div style="font-size: 13px; margin-top: 6px;">Try adjusting your search query, status filter, or qualifier filter.</div>
      </div>
    `;
  }
}

function createPromptCard(category, index, promptObj) {
  const cardId = `prompt-${category}-${index}`;
  const isEnabled = promptObj.enabled !== false;
  const isPlaying = currentlyPlayingCardId === cardId;
  const quals = promptObj.qualifiers || {};
  const qualKeys = Object.keys(quals);

  const card = document.createElement("div");
  card.className = `prompt-card ${isEnabled ? "" : "disabled"} ${isPlaying ? "playing" : ""}`;
  card.id = cardId;

  const fileName = promptObj.filepath ? promptObj.filepath.split("/").pop() : "unknown.wav";

  // Card Header
  const headerHtml = `
    <div class="card-header">
      <div class="card-meta">
        <span class="card-idx">#${index + 1}</span>
        <span class="card-file" title="${promptObj.filepath || ''}">${fileName}</span>
        ${selectedCategory === "all" ? `<span class="cat-pill">${category}</span>` : ""}
      </div>
      <div class="card-actions">
        <button class="play-btn ${isPlaying ? "playing" : ""}" id="btn-play-${cardId}" onclick="playPromptAudio('${cardId}', '${category}', ${index})">
          <span>${isPlaying ? "⏸ Pause" : "▶ Play"}</span>
        </button>

        <label class="switch-container" title="Enable or mute this voice line">
          <div class="switch">
            <input type="checkbox" ${isEnabled ? "checked" : ""} onchange="togglePromptEnabled('${category}', ${index}, this.checked)">
            <span class="slider"></span>
          </div>
          <span class="switch-label ${isEnabled ? "enabled" : "disabled"}">${isEnabled ? "ENABLED" : "MUTED"}</span>
        </label>
      </div>
    </div>
  `;

  // Dialogue Box
  const speakerClass1 = (promptObj.name || "").toLowerCase() === "connor" ? "speaker-connor" :
                        (promptObj.name || "").toLowerCase() === "sophia" ? "speaker-sophia" : "speaker-other";
  
  let dialogueHtml = `
    <div class="dialogue-box">
      <div class="speaker-line">
        <span class="speaker-pill ${speakerClass1}">${promptObj.name || "Speaker"}</span>
        <textarea class="speaker-text-input" rows="1" onchange="updatePromptText('${category}', ${index}, 'prompt', this.value)">${escapeHtml(promptObj.prompt || "")}</textarea>
      </div>
  `;

  if (promptObj.follow_up) {
    const fu = promptObj.follow_up;
    const speakerClass2 = (fu.name || "").toLowerCase() === "connor" ? "speaker-connor" :
                          (fu.name || "").toLowerCase() === "sophia" ? "speaker-sophia" : "speaker-other";
    dialogueHtml += `
      <div class="speaker-line">
        <span class="speaker-pill ${speakerClass2}">${fu.name || "Follow-up"}</span>
        <textarea class="speaker-text-input" rows="1" onchange="updateFollowUpText('${category}', ${index}, this.value)">${escapeHtml(fu.prompt || "")}</textarea>
      </div>
    `;
  }
  dialogueHtml += `</div>`;

  // Qualifiers Tags & Controls
  let tagsHtml = "";
  if (qualKeys.length === 0) {
    tagsHtml = `<span class="no-qualifiers-hint">None (general pool - can play for any situation in this category)</span>`;
  } else {
    qualKeys.forEach(k => {
      const v = quals[k];
      let tagClass = "tag-custom";
      if (k === "score_type") tagClass = "tag-score";
      else if (k === "tree_hit_type") tagClass = "tag-tree";
      else if (k === "strokes") tagClass = "tag-strokes";
      else if (["gir", "birdie_chance", "tee_shot", "close_to_pin"].includes(k)) tagClass = "tag-flag";

      tagsHtml += `
        <span class="tag ${tagClass}">
          <strong>${k}:</strong> ${v}
          <span class="tag-remove" onclick="removeQualifier('${category}', ${index}, '${k}')" title="Remove qualifier">×</span>
        </span>
      `;
    });
  }

  const qualifiersHtml = `
    <div class="qualifiers-section">
      <div class="qualifiers-header">
        <span>Context Qualifiers</span>
        <span>${qualKeys.length > 0 ? `${qualKeys.length} condition(s)` : "General Pool"}</span>
      </div>
      <div class="qualifier-tags" id="tags-${cardId}">
        ${tagsHtml}
      </div>
      <div class="add-qualifier-row">
        <select class="qual-select" id="qual-type-${cardId}" onchange="onQualifierTypeChange('${cardId}')">
          <option value="">+ Add Qualifier...</option>
          <option value="score_type">score_type (birdie, eagle, etc.)</option>
          <option value="game_mode">game_mode (course_play, range, minigames)</option>
          <option value="min_score_relative_to_par">min_score_relative_to_par (e.g. 20)</option>
          <option value="max_score_relative_to_par">max_score_relative_to_par (e.g. 5)</option>
          <option value="score_status">score_status (over_par, under_par, even_par)</option>
          <option value="overall_score">overall_score (over_par, under_par, even_par)</option>
          <option value="hole_range">hole_range (front_nine, back_nine)</option>
          <option value="max_hole">max_hole (e.g. 2)</option>
          <option value="min_hole">min_hole (e.g. 10)</option>
          <option value="surface">surface (sand, water, green, fairway, rough)</option>
          <option value="tee_box">tee_box (true/false)</option>
          <option value="tree_hit_type">tree_hit_type (trunk, leaves)</option>
          <option value="strokes">strokes (exact count, e.g. 8)</option>
          <option value="gir">gir (true/false)</option>
          <option value="birdie_chance">birdie_chance (true/false)</option>
          <option value="tee_shot">tee_shot (true/false)</option>
          <option value="close_to_pin">close_to_pin (true/false)</option>
          <option value="is_iron">is_iron (true/false)</option>
          <option value="min_backspin">min_backspin (e.g. 8000)</option>
          <option value="custom">Custom Qualifier...</option>
        </select>

        <span id="qual-val-container-${cardId}"></span>

        <button class="btn btn-sm" id="qual-add-btn-${cardId}" style="display:none;" onclick="addQualifierFromRow('${cardId}', '${category}', ${index})">Add</button>
      </div>
    </div>
  `;

  card.innerHTML = headerHtml + dialogueHtml + qualifiersHtml;
  return card;
}

function onQualifierTypeChange(cardId) {
  const select = document.getElementById(`qual-type-${cardId}`);
  const container = document.getElementById(`qual-val-container-${cardId}`);
  const addBtn = document.getElementById(`qual-add-btn-${cardId}`);
  const type = select.value;

  if (!type) {
    container.innerHTML = "";
    addBtn.style.display = "none";
    return;
  }

  addBtn.style.display = "inline-flex";

  if (type === "score_type") {
    container.innerHTML = `
      <select class="qual-select" id="qual-val-${cardId}">
        <option value="birdie">birdie</option>
        <option value="eagle">eagle</option>
        <option value="albatross">albatross</option>
        <option value="hole_in_one">hole_in_one</option>
        <option value="double_bogey">double_bogey</option>
        <option value="triple_bogey">triple_bogey</option>
        <option value="over_bogey">over_bogey</option>
        <option value="under_par">under_par</option>
      </select>
    `;
  } else if (type === "game_mode") {
    container.innerHTML = `
      <select class="qual-select" id="qual-val-${cardId}">
        <option value="course_play">course_play</option>
        <option value="range">range</option>
        <option value="minigames">minigames</option>
      </select>
    `;
  } else if (["score_status", "overall_score"].includes(type)) {
    container.innerHTML = `
      <select class="qual-select" id="qual-val-${cardId}">
        <option value="over_par">over_par</option>
        <option value="under_par">under_par</option>
        <option value="even_par">even_par</option>
      </select>
    `;
  } else if (type === "hole_range") {
    container.innerHTML = `
      <select class="qual-select" id="qual-val-${cardId}">
        <option value="front_nine">front_nine (holes 1-9)</option>
        <option value="back_nine">back_nine (holes 10-18)</option>
      </select>
    `;
  } else if (type === "surface") {
    container.innerHTML = `
      <select class="qual-select" id="qual-val-${cardId}">
        <option value="sand">sand</option>
        <option value="water">water</option>
        <option value="green">green</option>
        <option value="fairway">fairway</option>
        <option value="rough">rough</option>
      </select>
    `;
  } else if (type === "tree_hit_type") {
    container.innerHTML = `
      <select class="qual-select" id="qual-val-${cardId}">
        <option value="trunk">trunk (solid impact)</option>
        <option value="leaves">leaves (canopy pass)</option>
      </select>
    `;
  } else if (["gir", "birdie_chance", "tee_shot", "close_to_pin", "tee_box", "is_iron"].includes(type)) {
    container.innerHTML = `
      <select class="qual-select" id="qual-val-${cardId}">
        <option value="true">true</option>
        <option value="false">false</option>
      </select>
    `;
  } else if (["strokes", "min_score_relative_to_par", "max_score_relative_to_par", "max_hole", "min_hole", "min_backspin"].includes(type)) {
    let defVal = "8";
    if (type === "min_score_relative_to_par") defVal = "20";
    else if (type === "max_score_relative_to_par") defVal = "5";
    else if (type === "max_hole") defVal = "2";
    else if (type === "min_hole") defVal = "10";
    else if (type === "min_backspin") defVal = "8000";
    container.innerHTML = `
      <input type="number" class="qual-input" id="qual-val-${cardId}" placeholder="Value" value="${defVal}">
    `;
  } else if (type === "custom") {
    container.innerHTML = `
      <input type="text" class="qual-input" id="qual-custom-key-${cardId}" placeholder="Key" style="width:90px;">
      <input type="text" class="qual-input" id="qual-val-${cardId}" placeholder="Value" style="width:90px;">
    `;
  }
}

function addQualifierFromRow(cardId, category, index) {
  const typeSelect = document.getElementById(`qual-type-${cardId}`);
  const type = typeSelect.value;
  if (!type) return;

  let key = type;
  if (type === "custom") {
    key = (document.getElementById(`qual-custom-key-${cardId}`).value || "").trim();
    if (!key) {
      alert("Please enter a custom qualifier key.");
      return;
    }
  }

  const valEl = document.getElementById(`qual-val-${cardId}`);
  let rawVal = valEl.value;
  let finalVal = rawVal;

  if (rawVal === "true") finalVal = true;
  else if (rawVal === "false") finalVal = false;
  else if (type === "strokes" || (!isNaN(rawVal) && rawVal.trim() !== "")) {
    finalVal = parseInt(rawVal, 10);
  }

  const promptObj = appData.categories[category][index];
  if (!promptObj.qualifiers) promptObj.qualifiers = {};
  promptObj.qualifiers[key] = finalVal;

  checkDirtyState();
  renderPrompts();
}

function removeQualifier(category, index, key) {
  const promptObj = appData.categories[category][index];
  if (promptObj.qualifiers && promptObj.qualifiers.hasOwnProperty(key)) {
    delete promptObj.qualifiers[key];
    if (Object.keys(promptObj.qualifiers).length === 0) {
      delete promptObj.qualifiers;
    }
    checkDirtyState();
    renderPrompts();
  }
}

function togglePromptEnabled(category, index, enabled) {
  appData.categories[category][index].enabled = enabled;
  checkDirtyState();
  renderCategories();
  renderPrompts();
}

function updatePromptText(category, index, key, value) {
  appData.categories[category][index][key] = value.trim();
  checkDirtyState();
}

function updateFollowUpText(category, index, value) {
  if (appData.categories[category][index].follow_up) {
    appData.categories[category][index].follow_up.prompt = value.trim();
    checkDirtyState();
  }
}

function batchSetCurrentCategory(enabled) {
  const targetCats = selectedCategory === "all" ? Object.keys(appData.categories) : [selectedCategory];
  const actionName = enabled ? "enable" : "mute/disable";
  const catName = selectedCategory === "all" ? "ALL categories" : formatCategoryTitle(selectedCategory);

  if (!confirm(`Are you sure you want to ${actionName} all voice lines in ${catName}?`)) return;

  targetCats.forEach(cat => {
    appData.categories[cat].forEach(p => {
      p.enabled = enabled;
    });
  });

  checkDirtyState();
  renderCategories();
  renderPrompts();
  showToast(`All prompts in ${catName} set to ${enabled ? "Enabled" : "Disabled"}.`);
}

// Audio Player Handling
function playPromptAudio(cardId, category, index) {
  const promptObj = appData.categories[category][index];
  const audioPath = promptObj.filepath;

  if (!audioPath) {
    showToast("No audio filepath specified for this prompt.", true);
    return;
  }

  // If already playing this card, toggle pause
  if (currentlyPlayingCardId === cardId && !audioEngine.paused) {
    audioEngine.pause();
    updatePlayingUi(null);
    return;
  }

  currentAudioPath = audioPath;
  currentPromptRef = { cardId, category, index, promptObj };
  
  const streamUrl = `/api/audio?path=${encodeURIComponent(audioPath)}`;
  audioEngine.src = streamUrl;
  audioEngine.volume = parseFloat(document.getElementById("vol-slider").value || 0.9);
  
  audioEngine.play().then(() => {
    updatePlayingUi(cardId);
    updateBottomBar(promptObj, category, index);
  }).catch(err => {
    showToast("Failed to play audio clip: " + err, true);
    updatePlayingUi(null);
  });
}

function updatePlayingUi(cardId, paused = false) {
  // Clear previous playing state
  if (currentlyPlayingCardId) {
    const oldCard = document.getElementById(currentlyPlayingCardId);
    const oldBtn = document.getElementById(`btn-play-${currentlyPlayingCardId}`);
    if (oldCard) oldCard.classList.remove("playing");
    if (oldBtn) {
      oldBtn.classList.remove("playing");
      oldBtn.innerHTML = "<span>▶ Play</span>";
    }
  }

  currentlyPlayingCardId = cardId;
  if (cardId) {
    const newCard = document.getElementById(cardId);
    const newBtn = document.getElementById(`btn-play-${cardId}`);
    if (newCard) newCard.classList.add("playing");
    if (newBtn) {
      newBtn.classList.add("playing");
      newBtn.innerHTML = "<span>⏸ Pause</span>";
    }
    globalPlayBtn.disabled = false;
    globalPlayBtn.textContent = "⏸ Pause";
  } else {
    globalPlayBtn.textContent = "▶ Play";
  }
}

function updateBottomBar(promptObj, category, index) {
  const fileName = promptObj.filepath ? promptObj.filepath.split("/").pop() : "Clip";
  const titleEl = document.getElementById("now-playing-title");
  const textEl = document.getElementById("now-playing-text");

  titleEl.innerHTML = `
    <span>${formatCategoryTitle(category)} · ${fileName}</span>
    <span class="brand-badge">${promptObj.name || "Speaker"}</span>
    ${promptObj.enabled === false ? '<span class="brand-badge" style="background:#7f1d1d;color:#fca5a5;">MUTED</span>' : ''}
  `;

  let transcript = `"${promptObj.prompt || ""}"`;
  if (promptObj.follow_up) {
    transcript += ` ➔ ${promptObj.follow_up.name || "Follow-up"}: "${promptObj.follow_up.prompt || ""}"`;
  }
  textEl.textContent = transcript;
}

function toggleGlobalAudio() {
  if (!audioEngine.src) return;
  if (audioEngine.paused) {
    audioEngine.play();
    if (currentPromptRef) updatePlayingUi(currentPromptRef.cardId);
  } else {
    audioEngine.pause();
    updatePlayingUi(null, true);
  }
}

function replayGlobalAudio() {
  if (!audioEngine.src) return;
  audioEngine.currentTime = 0;
  audioEngine.play();
  if (currentPromptRef) updatePlayingUi(currentPromptRef.cardId);
}

function setGlobalVolume(val) {
  audioEngine.volume = parseFloat(val);
}

function showToast(msg, isError = false) {
  const toast = document.getElementById("toast");
  toast.textContent = msg;
  toast.className = `toast show ${isError ? "error" : ""}`;
  setTimeout(() => {
    toast.className = "toast";
  }, 3500);
}

function escapeHtml(str) {
  return str.replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
}
</script>
</body>
</html>
"""

def main():
    parser = argparse.ArgumentParser(description="Heckle Audio & Commentary Editor mini-app")
    parser.add_argument("--port", type=int, default=8088, help="Preferred web server port (default: 8088)")
    parser.add_argument("--no-browser", action="store_true", help="Do not automatically open browser on startup")
    args = parser.parse_args()

    port = find_open_port(args.port)
    server_address = ("127.0.0.1", port)
    
    try:
        httpd = HTTPServer(server_address, HeckleEditorHandler)
    except Exception as e:
        print(f"[ERROR] Could not start HTTP server on port {port}: {e}")
        sys.exit(1)

    url = f"http://127.0.0.1:{port}"
    print("=" * 64)
    print(" 🎙️ Heckle Audio & Commentary Editor")
    print("=" * 64)
    print(f" Mini-app server running at: {url}")
    print(f" Press Ctrl+C in this terminal to stop the server.")
    print("=" * 64)

    if not args.no_browser:
        try:
            webbrowser.open(url)
        except Exception:
            pass

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[INFO] Stopping Heckle Audio Editor server...")
        httpd.server_close()
        print("[INFO] Server stopped.")

if __name__ == "__main__":
    main()
