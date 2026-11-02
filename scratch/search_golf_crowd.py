import urllib.request
import urllib.parse
import re

queries = [
    "Golf Fan",
    "Golf Fan Cheer",
    "golf tournament cheer",
    "golf crowd reaction",
    "golf miss crowd",
    "golf groan",
    "golf cheer crowd",
    "golf roar crowd",
    "gallery cheer golf"
]

print("Searching Freesound...", flush=True)

for q in queries:
    url = f"https://freesound.org/search/?q={urllib.parse.quote(q)}"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            html = resp.read().decode('utf-8', errors='ignore')
            matches = re.findall(r'href="(/people/([^/]+)/sounds/(\d+)/)"', html)
            seen = set()
            found = []
            for path, user, sid in matches:
                if sid in seen:
                    continue
                seen.add(sid)
                found.append((sid, user, path))
                if len(found) >= 3:
                    break
            for sid, user, path in found:
                s_url = f"https://freesound.org{path}"
                try:
                    req_s = urllib.request.Request(s_url, headers={'User-Agent': 'Mozilla/5.0'})
                    with urllib.request.urlopen(req_s, timeout=5) as r_s:
                        h_s = r_s.read().decode('utf-8', errors='ignore')
                        tm = re.search(r'<title>(.*?)</title>', h_s, re.DOTALL)
                        title = tm.group(1).replace('Freesound - ', '').strip() if tm else 'Unknown'
                        hq_mp3 = re.search(r'(https://cdn\.freesound\.org/previews/\d+/\d+_[^"\']+-hq\.mp3)', h_s)
                        mp3 = hq_mp3.group(1) if hq_mp3 else ''
                        print(f"[{sid}] ({q}) {title} by {user} -> {mp3}", flush=True)
                except:
                    pass
    except Exception as e:
        print(f"Error {q}: {e}", flush=True)
