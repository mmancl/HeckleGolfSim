import soundfile as sf
import numpy as np
import os

d, sr = sf.read('scratch/candidates/golf_moan_variations.mp3')
cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"

# The video is "15 Sound Variations of Crowd Moaning in Wii Sports Golf"
# Each variation is about 1.5s separated by silence.
# Let's find each variation by envelope
env = np.abs(d)
if env.ndim == 2:
    env = np.mean(env, axis=1)

# Smooth envelope
k = int(sr * 0.05)
smooth_env = np.convolve(env, np.ones(k)/k, mode='same')

# Find peaks separated by at least 1.0s
peaks = []
last_t = -999.0
for i in range(len(smooth_env)):
    if smooth_env[i] > 0.04:
        t = i / sr
        if t - last_t > 1.2:
            peaks.append(t)
            last_t = t

print(f"Detected {len(peaks)} groan variations at times:", [round(p, 2) for p in peaks])

for idx, p in enumerate(peaks[:4]):
    t0 = max(0.0, p - 0.1)
    t1 = min(len(d)/sr, p + 1.4)
    seg = d[int(t0*sr):int(t1*sr)]
    # Normalize peak to 0.85
    seg_norm = seg / np.max(np.abs(seg)) * 0.85
    out_file = os.path.join(cand_dir, f"golf_groan_var_{idx+1}.mp3")
    sf.write(out_file, seg_norm, sr)
    print(f"Exported golf_groan_var_{idx+1}.mp3 ({len(seg)/sr:.2f}s)")
