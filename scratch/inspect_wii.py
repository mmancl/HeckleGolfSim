import soundfile as sf
import numpy as np

p1 = "scratch/candidates/wii_sports_golf_crowd.mp3"
p2 = "scratch/candidates/golf_moan_variations.mp3"

d1, sr1 = sf.read(p1)
d2, sr2 = sf.read(p2)

print(f"wii_sports_golf_crowd: {len(d1)/sr1:.2f}s")
print(f"golf_moan_variations: {len(d2)/sr2:.2f}s")

# Let's find silent/active segments in d2
# We can find energy peaks in d2
window = int(sr2 * 0.1)
energy = np.array([np.mean(d2[i:i+window]**2) for i in range(0, len(d2)-window, window)])
times = np.arange(len(energy)) * 0.1
peaks = times[energy > 0.005]
print("Active timestamps in golf_moan_variations:", [round(t, 1) for t in peaks[:20]])
