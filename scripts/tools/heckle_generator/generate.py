import json
import os
import random
import numpy
import torch

# Fix PyTorch 2.6+ unpickling error for Bark checkpoints
try:
    if hasattr(numpy, "_core"):
        torch.serialization.add_safe_globals([numpy._core.multiarray.scalar])
    else:
        torch.serialization.add_safe_globals([numpy.core.multiarray.scalar])
except Exception:
    pass

_orig_torch_load = torch.load
def _patched_torch_load(*args, **kwargs):
    kwargs.setdefault('weights_only', False)
    return _orig_torch_load(*args, **kwargs)
torch.load = _patched_torch_load

# Enable CUDA GPU if available
if torch.cuda.is_available():
    print(f"Using GPU Acceleration: {torch.cuda.get_device_name(0)}")
else:
    print("CUDA not available yet. Running on CPU.")

from bark import SAMPLE_RATE, generate_audio, preload_models
import scipy.io.wavfile as wavfile

import argparse

# Configurable speaker preset (Default: "v2/en_speaker_9")
# Available English presets: "v2/en_speaker_0" through "v2/en_speaker_9"
DEFAULT_SPEAKER = "v2/en_speaker_9"

parser = argparse.ArgumentParser(description="Generate golf heckle audio using Bark.")
parser.add_argument("--speaker", type=str, default=DEFAULT_SPEAKER, help=f"Bark speaker preset (default: {DEFAULT_SPEAKER})")
parser.add_argument("--category", type=str, default="good_shot_fairway", help="Category name, or 'all' for all categories")
parser.add_argument("--index", type=int, default=None, help="Specific prompt index in category (default: random selection)")
parser.add_argument("--all", action="store_true", help="Batch generate all prompts in selected category/categories")
args, _ = parser.parse_known_args()

speaker_preset = args.speaker

# Determine paths relative to script location
script_dir = os.path.dirname(os.path.abspath(__file__))
json_path = os.path.join(script_dir, "heckle_prompts.json")
project_root = os.path.abspath(os.path.join(script_dir, "..", "..", ".."))

# If speaker is a custom voice name or file in custom_voices/, resolve its full path
if not speaker_preset.startswith("v2/"):
    custom_voice_dir = os.path.join(script_dir, "custom_voices")
    candidate_paths = [
        speaker_preset,
        f"{speaker_preset}.npz",
        os.path.join(custom_voice_dir, speaker_preset),
        os.path.join(custom_voice_dir, f"{speaker_preset}.npz"),
    ]
    for p in candidate_paths:
        if os.path.isfile(p):
            speaker_preset = os.path.abspath(p)
            break

# Load the prompts
with open(json_path, "r", encoding="utf-8") as f:
    data = json.load(f)

categories = list(data["categories"].keys())
if args.category.lower() == "all":
    selected_cats = categories
elif args.category in data["categories"]:
    selected_cats = [args.category]
else:
    print(f"Unknown category '{args.category}'. Available categories: {categories}")
    import sys
    sys.exit(1)

tasks = []
for cat in selected_cats:
    cat_items = data["categories"][cat]
    if args.all:
        for idx, item in enumerate(cat_items):
            tasks.append((cat, idx, item))
    elif args.index is not None:
        if 0 <= args.index < len(cat_items):
            tasks.append((cat, args.index, cat_items[args.index]))
        else:
            print(f"Index {args.index} out of range for category '{cat}' (0..{len(cat_items)-1})")
            import sys
            sys.exit(1)
    else:
        rand_idx = random.randrange(len(cat_items))
        tasks.append((cat, rand_idx, cat_items[rand_idx]))
        if args.category.lower() != "all":
            break

print(f"\nTotal Bark generation tasks queued: {len(tasks)}")
preload_models()

for cat_name, item_idx, prompt_item in tasks:
    if isinstance(prompt_item, dict):
        prompt_text = prompt_item.get("prompt", "")
        output_path = prompt_item.get("filepath", f"res://assets/audio/heckler/{cat_name}/{cat_name}_{item_idx}.wav")
    else:
        prompt_text = str(prompt_item)
        output_path = f"res://assets/audio/heckler/{cat_name}/{cat_name}_{item_idx}.wav"

    if output_path.startswith("res://"):
        rel_path = output_path.replace("res://", "")
        full_output_path = os.path.normpath(os.path.join(project_root, rel_path))
    else:
        full_output_path = os.path.normpath(os.path.join(project_root, output_path))

    os.makedirs(os.path.dirname(full_output_path), exist_ok=True)

    print("\n" + "="*60)
    print(f"Category: [{cat_name}] | Index: {item_idx}")
    print(f"Prompt:   {prompt_text}")
    print(f"Speaker:  {speaker_preset}")
    print(f"Target:   {output_path}")
    print("="*60)

    audio_array = generate_audio(prompt_text, history_prompt=speaker_preset)
    wavfile.write(full_output_path, SAMPLE_RATE, audio_array)
    print(f"-> Saved audio to {full_output_path}")

print("\nAll requested generations completed successfully!")