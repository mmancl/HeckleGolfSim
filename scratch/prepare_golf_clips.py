import soundfile as sf
import numpy as np
import os
import imageio_ffmpeg
import subprocess

cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"
ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()

# Let's create trimmed, punchy versions of the golf gallery cheers
files_to_normalize = {
    # 1. Golf Anticipation (swelling crowd murmur on the green)
    "golf_anticipation_murmur": {
        "src": "outdoor_golf_applause.mp3",
        "start": 0.0,
        "dur": 7.0,
        "fade_in": 1.0,
        "target_peak": 0.75
    },
    # 2. Outdoor Golf Gallery Cheers
    "golf_cheer_gallery_1": {
        "src": "golf_gallery_cheer_1.mp3",
        "start": 0.0,
        "dur": 6.5,
        "fade_in": 0.05,
        "target_peak": 0.95
    },
    "golf_cheer_gallery_3": {
        "src": "golf_gallery_cheer_3.mp3",
        "start": 0.0,
        "dur": 7.0,
        "fade_in": 0.05,
        "target_peak": 0.95
    },
    "golf_cheer_yukon_hazard": {
        "src": "golf_cheer_618255.mp3", # The one user liked!
        "start": 0.0,
        "dur": 3.78,
        "fade_in": 0.0,
        "target_peak": 0.95
    },
    "golf_cheer_yukon_short": {
        "src": "yukon_cheer_1_618203.mp3",
        "start": 0.0,
        "dur": 1.46,
        "fade_in": 0.0,
        "target_peak": 0.95
    },
    "golf_cheer_yukon_goodshot": {
        "src": "yukon_cheer_3_618256.mp3",
        "start": 0.0,
        "dur": 4.8,
        "fade_in": 0.0,
        "target_peak": 0.95
    },
    "golf_cheer_wii_huge_roar": {
        "src": "wii_golf_huge_gallery_roar.mp3",
        "start": 0.0,
        "dur": 6.5,
        "fade_in": 0.0,
        "target_peak": 0.95
    },
    "golf_cheer_wii_classic": {
        "src": "wii_golf_cheer_applause.mp3",
        "start": 0.0,
        "dur": 5.5,
        "fade_in": 0.0,
        "target_peak": 0.95
    },
    # 3. Golf Miss "Awww" / Groans
    "golf_aww_groan_wii": {
        "src": "golf_miss_groan_norm.mp3",
        "start": 0.0,
        "dur": 1.78,
        "fade_in": 0.0,
        "target_peak": 0.95
    },
    "golf_aww_groan_wii_alt": {
        "src": "wii_golf_groan_aww.mp3",
        "start": 0.0,
        "dur": 2.0,
        "fade_in": 0.0,
        "target_peak": 0.95
    },
    "golf_aww_crowd_phmiller": {
        "src": "aww_crowd.mp3",
        "start": 0.0,
        "dur": 2.0,
        "fade_in": 0.0,
        "target_peak": 0.95
    }
}

for name, cfg in files_to_normalize.items():
    src_p = os.path.join(cand_dir, cfg["src"])
    if not os.path.exists(src_p):
        print(f"Missing {src_p}")
        continue
    d, sr = sf.read(src_p)
    i0 = int(cfg["start"] * sr)
    i1 = min(len(d), int((cfg["start"] + cfg["dur"]) * sr))
    seg = d[i0:i1].copy()
    
    # Fade in / fade out
    if cfg["fade_in"] > 0:
        fi = int(cfg["fade_in"] * sr)
        seg[:fi] *= np.linspace(0, 1, fi)[:, None] if seg.ndim == 2 else np.linspace(0, 1, fi)
    fo = int(0.25 * sr)
    if len(seg) > fo:
        seg[-fo:] *= np.linspace(1, 0, fo)[:, None] if seg.ndim == 2 else np.linspace(1, 0, fo)
        
    pk = np.max(np.abs(seg))
    if pk > 0:
        seg = seg / pk * cfg["target_peak"]
    
    out_p = os.path.join(cand_dir, f"{name}.mp3")
    sf.write(out_p, seg, sr)
    print(f"Generated clean clip: {name}.mp3 ({len(seg)/sr:.2f}s, peak {np.max(np.abs(seg)):.2f})")
