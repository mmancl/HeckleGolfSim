import soundfile as sf
import os

d, sr = sf.read('scratch/candidates/wii_sports_golf_crowd.mp3')
cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"

sections = {
    "wii_golf_groan_aww": (0.0, 2.0),
    "wii_golf_cheer_applause": (2.2, 8.5),
    "wii_golf_big_cheer": (9.0, 18.0),
    "wii_golf_applause_whistle": (18.0, 24.5),
    "wii_golf_huge_gallery_roar": (25.0, 33.0)
}

for name, (t0, t1) in sections.items():
    seg = d[int(t0*sr):int(t1*sr)]
    out_path = os.path.join(cand_dir, f"{name}.mp3")
    sf.write(out_path, seg, sr)
    print(f"Exported {name}: {len(seg)/sr:.2f}s")
