import urllib.request
import re

url = "https://freesound.org/people/ShangusBurger/sounds/"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        html = r.read().decode('utf-8', errors='ignore')
        matches = re.findall(r'href="(/people/ShangusBurger/sounds/(\d+)/)" title="([^"]+)"', html)
        seen = set()
        print(f"Total found on page: {len(matches)}")
        for path, sid, title in matches:
            if sid in seen:
                continue
            seen.add(sid)
            print(f"[{sid}] {title}")
except Exception as e:
    print("Error:", e)
