import urllib.request
import os

new_downloads = {
    "yukon_cheer_1_618203.mp3": "https://cdn.freesound.org/previews/618/618203_13699353-hq.mp3",
    "yukon_cheer_3_618256.mp3": "https://cdn.freesound.org/previews/618/618256_13699353-hq.mp3",
    "crowd_oh_disappointed_619007.mp3": "https://cdn.freesound.org/previews/619/619007_6619179-hq.mp3",
    "crowd_sigh_disappointment_764106.mp3": "https://cdn.freesound.org/previews/764/764106_11744683-hq.mp3",
    "crowd_sigh_bin_763997.mp3": "https://cdn.freesound.org/previews/763/763997_11744683-hq.mp3",
    "golf_groan_cryany_867450.mp3": "https://cdn.freesound.org/previews/867/867450_5587747-hq.mp3",
    "crowd_golf_clap_257793.mp3": "https://cdn.freesound.org/previews/257/257793_37876-hq.mp3",
}

out_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"
os.makedirs(out_dir, exist_ok=True)

for name, url in new_downloads.items():
    dest = os.path.join(out_dir, name)
    if not os.path.exists(dest):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=10) as r, open(dest, 'wb') as f:
                f.write(r.read())
            print(f"Saved {name}: {os.path.getsize(dest)} bytes", flush=True)
        except Exception as e:
            print(f"Error {name}: {e}", flush=True)
