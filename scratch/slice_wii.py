import soundfile as sf
import numpy as np

d, sr = sf.read('scratch/candidates/wii_sports_golf_crowd.mp3')
dur = len(d) / sr

# Print energy across 1-second chunks
print(f"Total duration: {dur:.1f}s")
for sec in range(int(dur)):
    chunk = d[sec*sr:(sec+1)*sr]
    peak = np.max(np.abs(chunk))
    print(f"Sec {sec:02d}-{sec+1:02d}: peak={peak:.2f}")
