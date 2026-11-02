import urllib.request
import urllib.parse
import re

queries = [
    "golf roar",
    "golf crowd",
    "crowd roar",
    "crowd cheer",
    "crowd aww",
    "crowd gasp",
    "crowd murmur",
    "crowd anticipation",
    "crowd suspense"
]

print("Searching Freesound (CC0)...", flush=True)

for q in queries:
    url = f"https://freesound.org/search/?q={urllib.parse.quote(q)}&f=license%3A%22Creative+Commons+0%22"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            html = resp.read().decode('utf-8', errors='ignore')
            matches = re.findall(r'href="(/people/([^/]+)/sounds/(\d+)/)"', html)
            seen = set()
            found = []
            for path, user, sid in matches:
                if sid in seen:
                    continue
                seen.add(sid)
                found.append((sid, user, path))
                if len(found) >= 4:
                    break
            print(f"\nQuery '{q}': {len(found)} results")
            for sid, user, path in found:
                # get title and preview
                s_url = f"https://freesound.org{path}"
                req_s = urllib.request.Request(s_url, headers={'User-Agent': 'Mozilla/5.0'})
                with urllib.request.urlopen(req_s, timeout=8) as r_s:
                    h_s = r_s.read().decode('utf-8', errors='ignore')
                    tm = re.search(r'<title>(.*?)</title>', h_s, re.DOTALL)
                    title = tm.group(1).replace('Freesound - ', '').strip() if tm else 'Unknown'
                    hq_mp3 = re.search(r'(https://cdn\.freesound\.org/previews/\d+/\d+_[^"\']+-hq\.mp3)', h_s)
                    mp3 = hq_mp3.group(1) if hq_mp3 else ''
                    print(f"  [{sid}] by {user}: {title}")
                    print(f"    Preview: {mp3}")
    except Exception as e:
        print(f"Error {q}: {e}")
