import os
import soundfile as sf
import numpy as np

cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"

print(f"{'Filename':<30} | {'Dur (s)':<8} | {'SR':<6} | {'Ch':<3} | {'Peak':<6} | {'RMS':<6}")
print("-" * 75)

for f in sorted(os.listdir(cand_dir)):
    if not f.endswith('.mp3') or os.path.getsize(os.path.join(cand_dir, f)) == 0:
        continue
    p = os.path.join(cand_dir, f)
    try:
        data, sr = sf.read(p)
        peak = np.max(np.abs(data))
        rms = np.sqrt(np.mean(data**2))
        dur = len(data) / sr
        channels = 1 if data.ndim == 1 else data.shape[1]
        print(f"{f:<30} | {dur:<8.2f} | {sr:<6} | {channels:<3} | {peak:<6.2f} | {rms:<6.3f}")
    except Exception as e:
        print(f"{f:<30} | Error: {e}")
