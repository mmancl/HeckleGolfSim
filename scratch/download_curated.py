import urllib.request
import os

downloads = {
    "crowd_roar_449915.mp3": "https://cdn.freesound.org/previews/449/449915_4185768-hq.mp3",
    "crowd_cheer_651646.mp3": "https://cdn.freesound.org/previews/651/651646_5315864-hq.mp3",
    "cheer_1_618203.mp3": "https://cdn.freesound.org/previews/618/618203_13699353-hq.mp3",
    "crowd_gasp_264376.mp3": "https://cdn.freesound.org/previews/264/264376_1654262-hq.mp3",
}

out_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"
for name, url in downloads.items():
    dest = os.path.join(out_dir, name)
    if not os.path.exists(dest):
        print(f"Downloading {name}...", flush=True)
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=10) as r, open(dest, 'wb') as f:
                f.write(r.read())
            print(f"Saved {name}: {os.path.getsize(dest)} bytes", flush=True)
        except Exception as e:
            print(f"Error {name}: {e}", flush=True)

print("Done downloading downloads.", flush=True)
