# Golf Heckle Generator & Custom Voice Tools

This directory contains tools for generating sarcastic golf commentary and heckles using [Suno Bark](https://github.com/suno-ai/bark), as well as extracting and cloning custom voices directly from YouTube videos.

---

## 1. Create Custom Voice from YouTube (`create_voice_from_youtube.py`)

Extract audio from any YouTube video (e.g. Happy Gilmore, Shooter McGavin, Tiger Woods, movie lines, commentators), process it, and generate a Bark custom voice preset (`.npz`).

### Usage:
```bash
# Basic usage: download and create a custom voice prompt (.npz)
python create_voice_from_youtube.py "https://www.youtube.com/watch?v=VIDEO_ID" --name "shooter_mcgavin"

# Specify a custom start time and duration (recommended 5-14 seconds of clear speech)
python create_voice_from_youtube.py "https://www.youtube.com/watch?v=VIDEO_ID" --name "happy_gilmore" --start "01:23" --duration 10.0

# Keep the extracted reference audio WAV and immediately test synthesize a golf heckle line
python create_voice_from_youtube.py "https://www.youtube.com/watch?v=VIDEO_ID" --name "bob_barker" --start 45.5 --duration 8.0 --keep-reference-audio --test
```

### CLI Options:
| Flag | Description | Default |
|------|-------------|---------|
| `url` | YouTube video URL or ID | *(Required)* |
| `--name`, `-n` | Custom voice name | Derived from video title |
| `--start`, `-s` | Start offset in seconds (`45.5`) or timestamp (`01:23`) | `0` |
| `--duration`, `-d` | Audio slice duration in seconds (optimal: 5-14s) | `10.0` |
| `--output-dir`, `-o` | Output directory for `.npz` file | `custom_voices/` |
| `--no-isolate-vocals` | Disable Demucs AI vocal isolation (removes music & crowds) | `False` (Isolation active) |
| `--no-denoise` | Disable spectral background noise reduction | `False` (Denoising active) |
| `--denoise-strength` | Background noise reduction strength (0.0 to 1.0) | `0.75` |
| `--keep-reference-audio`, `-k` | Save the cleaned vocal reference `.wav` file | `False` |
| `--test`, `-t` | Immediately test voice by generating a sample heckle | `False` |
| `--test-prompt` | Custom text to synthesize when `--test` is active | Golf heckle quote |

---

## 2. Generate Heckles with Bark (`generate.py`)

Generates audio lines from `heckle_prompts.json` using Suno Bark.

```bash
# Generate a random prompt using built-in speaker preset (default: v2/en_speaker_9)
python generate.py --speaker "v2/en_speaker_9" --category "good_shot_fairway"

# Generate using your custom YouTube voice!
python generate.py --speaker "shooter_mcgavin" --category "ball_in_water"

# Batch generate all prompts across all categories:
python generate.py --category "all" --all
```

---

## 3. Generate Heckles with F5-TTS (`generate_f5.py`)

Generates realistic, studio-quality audio from `heckle_prompts.json` using **[F5-TTS](https://github.com/SWivid/F5-TTS)** (MIT License). Supports **multi-announcer dialogue banter** between **Connor** (`irish_accent2`) and **Sophia** (`english_female`), zero-shot voice cloning from reference WAV files with continuous flow-matching diffusion, and automatic conversational audio stitching.

### Announcers & Prompts Setup:
- **Connor** (`irish_accent2`): 70% of lead commentary lines.
- **Sophia** (`english_female`): 30% of lead commentary lines.
- **Interactive Banter (`follow_up`)**: 20% of prompts feature back-and-forth dialogue (Connor + Sophia reacting to each other), which `generate_f5.py` synthesizes and stitches with a natural conversational pause into a single audio clip.

### Prerequisites:
```bash
pip install f5-tts soundfile
```

### Categories in `heckle_prompts.json` (776 Total Prompts across 21 categories):
1. `good_shot_fairway` (50) - Clean fairway strikes and center-line drives.
2. `good_shot_green` (50) - Greens in regulation, pin-seeking approaches, and backspin control.
3. `home_button_popup` (50) - Quitting / Home button popup heckles (*"Are you sick of me already?"*).
4. `mulligan_heckles` (50) - Mulligan / breakfast ball re-do heckles (*"A mulligan? I saw that!"*).
5. `player_afk_heckles` (50) - Player idle / slow play heckles (*"Did you fall asleep on the tee box?"*).
6. `under_par` (50) - Birdies, eagles, and red numbers.
7. `over_bogey_heckles` (50) - Double/triple bogeys and disaster holes.
8. `ball_in_sand` (50) - Bunker and sand trap plunges.
9. `ball_in_water` (50) - Water hazards and splashdowns.
10. `slice_into_rough` (50) - Hard right curves and banana slices into fescue.
11. `hook_into_rough` (50) - Severe snap hooks and duck hooks into left rough.
12. `crazy_high_apex` (50) - Moonshots and skyballs with extreme hang time.
13. `really_short_shots` (50) - Dribblers, whiffs, and two-yard rollouts.
14. `terrible_putts_off_green` (50) - Blown putts rolling past the cup and off the fringe.
15. `hitting_or_going_through_trees` (50) - Wood-on-wood collisions and pinball tree branches.
16. `heckles_disabled` (5) - Pleads not to turn heckles off, abruptly cut off mid-speech.
17. `heckles_enabled` (5) - Announcers waking back up from the pitch-black void.
18. `settings_opened` (10) - Joking that the player opened settings to cheat, adjust wind/gravity, or fix their game.

### Usage:
```bash
# Generate a random prompt from a category (automatically using assigned announcers):
python generate_f5.py --category "player_afk_heckles"

# Generate a specific prompt index (e.g. index 0 has multi-announcer follow-up banter):
python generate_f5.py --category "mulligan_heckles" --index 0

# Batch generate all prompts in a category:
python generate_f5.py --category "good_shot_fairway" --all

# Batch generate the entire audio library across all 15 categories (750 files):
python generate_f5.py --category "all" --all

# Override speaker, speed, diffusion steps, pause, or prompt:
python generate_f5.py --speaker "irish_accent2" --speed 0.95 --pause 0.35 --prompt "That swing belonged in a batting cage, not on a golf course."
```

---

## 4. Test Voices (`test_voices.py`)

Test all available voices or a specific voice against a sample golf heckle prompt.

```bash
# Test a custom voice
python test_voices.py --speaker "shooter_mcgavin"

# Test all voices (including all custom voices in custom_voices/)
python test_voices.py
```

