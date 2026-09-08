# Heckle Golf Simulator - AI Commercial Video Generator

A production-ready Python automation tool that transforms your in-game screenshots into a cinematic promotional commercial for **Heckle Golf Simulator** using Google Veo video generation models (via the Gemini API / `google-genai` SDK and REST API).

---

## Storyboard Overview (13 Scenes)

The tool structures the commercial into a cohesive ~65-second promotional trailer:

1. **Brand Intro & Splash** (`heckle_splash.png` / `icon.png`): High-production camera push-in and golden lighting reveal of the game logo.
2. **Main Menu Hub** (`main_menu.png`): Sleek slow-motion camera glide over game modes and clubhouse UI.
3. **Driving Range & Shot Analytics** (`range_practice.png`): Dynamic sports broadcast camera tracking ball flight trajectory with real-time launch monitor tracer lines and telemetry.
4. **Course Downloads & Community Tracks** (`download_courses.png`): Modern touchscreen pan showing community-created courses and downloads.
5. **Course Play: Tee Off** (`course_play_1.png`): Championship tee box view overlooking lush fairways and dynamic skies.
6. **Course Play: Approach & Hazards** (`course_play_2.png`): Low-angle approach view toward the green with bunkers and water hazards.
7. **Course Play: Tactical GPS Map** (`course_play_map.png`): High-tech tactical zoom into the hole overview map and yardage rings.
8. **Course Play: Putting Green** (`course_play_putting.png`): Cinematic glide across green break lines and slope contour grids.
9. **Match History & Resume** (`match_history.png`): Digital scorecards demonstrating instant round resume functionality.
10. **Player Profile & Smart Analytics** (`player_profile.png`): Analytics dashboard highlighting club yardage averages, lifetime best shots, AI recommendations, and 1-click email export.
11. **Mini-Games Hub** (`mini_game_menu.png`): High-energy arcade menu transition showing party challenges and drills.
12. **Mini-Game: Chipping Challenge** (`mini_game_chipping.png`): Action view of floating target rings and arcade multipliers.
13. **Mini-Game: Putting & Outro** (`mini_game_putting.png`): Climax putting shot with victory fireworks transitioning into a bold call to action: *"Heckle Golf Simulator - Play Now!"*.

---

## Prerequisites

### 1. Python Environment
Python 3.10+ (tested on Python 3.12). Install required packages:
```powershell
pip install -r scripts/tools/commercial_generator/requirements.txt
```
*(Dependencies: `google-genai`, `pillow`, `opencv-python`, `requests`)*

### 2. Google Gemini API Key
Google Veo requires access to video generation models (e.g. `veo-3.1-generate-preview` or `veo-2.0-generate-001`). 

Set your API key in your environment before running:
- **PowerShell**:
  ```powershell
  $env:GEMINI_API_KEY="AIzaSyYourSecretKeyHere"
  ```
- **Command Prompt (cmd)**:
  ```cmd
  set GEMINI_API_KEY=AIzaSyYourSecretKeyHere
  ```
- Alternatively, pass it directly with `--api-key "AIzaSy..."`.

### 3. Video Stitcher (ffmpeg or OpenCV)
- **Automatic Fallback (Zero setup)**: The script has a built-in OpenCV stitcher that uses `opencv-python` (already installed). It rescales and stitches clips cleanly to 1080p MP4.
- **Optional (Faster & Audio Support)**: Install `ffmpeg` on your system (`winget install Gyan.FFmpeg`) or `pip install imageio-ffmpeg`. If ffmpeg is detected, it is used automatically.

---

## Quick Start

### Step 1: Validate Setup (Dry Run)
Test your setup, verify image paths, preview prompts, and check timings without spending API quota:
```powershell
python scripts/tools/commercial_generator/generate_commercial.py --dry-run
```

### Step 2: Generate the Full Commercial
Run the generator:
```powershell
python scripts/tools/commercial_generator/generate_commercial.py
```

The script will:
1. Upload and submit each screenshot to Google Veo with its tailored prompt.
2. Poll the generation operation with live elapsed progress.
3. Download each completed 1080p clip into `output/commercial/clips/`.
4. Automatically stitch the clips into `output/commercial/heckle_golf_sim_commercial.mp4`.

---

## Command Line Options

| Argument | Default | Description |
| :--- | :--- | :--- |
| `--dry-run` | `False` | Validates assets, dimensions, and prompts without calling Google Veo. |
| `--input-dir` | `C:\Users\micha\Downloads\golf_sim_commercial` | Folder containing the screenshots. |
| `--output-dir` | `output/commercial` | Output folder for clips and final combined video. |
| `--config` | `storyboard_config.json` | Path to storyboard config file. |
| `--model` | `veo-3.1-generate-preview` | Target Google Veo model (`veo-3.1-generate-preview`, `veo-2.0-generate-001`, etc.). |
| `--skip-generate` | `False` | Skips generation and re-stitches existing clips in the output folder. |
| `--force` | `False` | Overrides cached clips and forces re-generation from the API. |
| `--audio` | `""` | Optional path to background music (.mp3 or .wav) to mix into the final video. |
| `--resolution` | `1920x1080` | Target video resolution (`WxH`). |
| `--fps` | `30.0` | Output frame rate. |
| `--poll-interval`| `15` | Seconds between status checks during generation. |
| `--max-poll-time`| `600` | Max seconds to wait for a clip before timing out. |

---

## Useful Workflows

### Re-Stitching with Background Music
Once your video clips have been generated in `output/commercial/clips/`, you can test different music tracks or re-stitch instantly without re-generating:
```powershell
python scripts/tools/commercial_generator/generate_commercial.py --skip-generate --audio "C:\path\to\soundtrack.mp3"
```

### Resuming an Interrupted Generation
If your connection drops or you stop the process, don't worry! The script caches all completed clips in `output/commercial/clips/`. When you run the script again, it detects cached clips (`[CACHED] Scene already exists. Skipping API call`) and resumes right where it left off.

### Customizing Prompts & Scenes
Open `storyboard_config.json`:
- Adjust the `"prompt"` text to alter camera motion, lighting, or style.
- Set `"enabled": false` on any scene you want to exclude.
- Change `"duration_seconds"` or change the order of scenes.
