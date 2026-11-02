import urllib.request
import os

urls = {
    "crowd_oh_disappointed_619007.mp3": "https://cdn.freesound.org/previews/619/619007_781461-hq.mp3",
    "golf_groan_cryany_867450.mp3": "https://cdn.freesound.org/previews/867/867450_7536-hq.mp3",
    "crowd_golf_clap_257793.mp3": "https://cdn.freesound.org/previews/257/257793_4157918-hq.mp3"
}

out_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"
for name, url in urls.items():
    dest = os.path.join(out_dir, name)
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=10) as r, open(dest, 'wb') as f:
            f.write(r.read())
        print(f"Saved {name}: {os.path.getsize(dest)} bytes")
    except Exception as e:
        print(f"Error {name}: {e}")
