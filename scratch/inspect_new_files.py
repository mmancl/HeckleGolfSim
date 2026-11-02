import soundfile as sf
import numpy as np
import os

cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"
files = [
    "golf_gallery_cheer_1.mp3",
    "golf_gallery_cheer_3.mp3",
    "outdoor_golf_applause.mp3",
    "golf_gallery_whistle.mp3",
    "golf_miss_groan.mp3",
    "wii_sports_golf_crowd.mp3",
    "crowd_aww_7s.mp3",
    "yukon_cheer_1_618203.mp3",
    "yukon_cheer_3_618256.mp3",
    "golf_cheer_618255.mp3"
]

print(f"{'Filename':<28} | {'Dur (s)':<8} | {'SR':<6} | {'Peak':<6} | {'RMS':<6}")
print("-" * 65)
for f in files:
    p = os.path.join(cand_dir, f)
    if os.path.exists(p):
        d, sr = sf.read(p)
        dur = len(d) / sr
        peak = np.max(np.abs(d))
        rms = np.sqrt(np.mean(d**2))
        print(f"{f:<28} | {dur:<8.2f} | {sr:<6} | {peak:<6.2f} | {rms:<6.3f}")
