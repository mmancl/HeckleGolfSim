import urllib.request
import re

url = "https://freesound.org/browse/tags/golf/"
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        html = r.read().decode('utf-8', errors='ignore')
        matches = re.findall(r'href="(/people/([^/]+)/sounds/(\d+)/)" title="([^"]+)"', html)
        seen = set()
        print(f"Total found tagged 'golf': {len(matches)}")
        for path, user, sid, title in matches:
            if sid in seen:
                continue
            seen.add(sid)
            print(f"[{sid}] by {user}: {title}")
except Exception as e:
    print("Error:", e)
