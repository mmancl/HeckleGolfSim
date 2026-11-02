import urllib.request
import re

for sid in ["618203", "618255", "618256"]:
    url = f"https://freesound.org/s/{sid}/"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            html = r.read().decode('utf-8', errors='ignore')
            title = re.search(r'<title>(.*?)</title>', html, re.DOTALL).group(1).strip()
            desc = re.search(r'<div id="sound_description">(.*?)</div>', html, re.DOTALL)
            desc_text = re.sub(r'<[^>]+>', '', desc.group(1)).strip() if desc else ''
            tags = re.findall(r'class="tag"[^>]*>([^<]+)<', html)
            hq = re.search(r'(https://cdn\.freesound\.org/previews/\d+/\d+_[^"\']+-hq\.mp3)', html)
            print(f"[{sid}] {title}")
            print(f"  Desc: {desc_text}")
            print(f"  Tags: {tags}")
            print(f"  HQ MP3: {hq.group(1) if hq else 'None'}\n")
    except Exception as e:
        print(f"Error {sid}: {e}")
