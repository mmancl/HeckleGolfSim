import urllib.request
import urllib.parse
import re

queries = [
    "disc golf cheer",
    "putt cheer",
    "putting cheer",
    "golf tournament",
    "outdoor cheer",
    "outdoor applause",
    "outdoor crowd",
    "spectators cheer",
    "crowd sigh outdoor",
    "crowd groan outdoor",
    "sports groan",
    "audience groan outdoor"
]

print("Searching outdoor crowd reactions...", flush=True)

results = {}
for q in queries:
    url = f"https://freesound.org/search/?q={urllib.parse.quote(q)}"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            html = resp.read().decode('utf-8', errors='ignore')
            matches = re.findall(r'href="(/people/([^/]+)/sounds/(\d+)/)"', html)
            seen = set()
            for path, user, sid in matches[:5]:
                if sid in seen or sid in results:
                    continue
                seen.add(sid)
                s_url = f"https://freesound.org{path}"
                try:
                    req_s = urllib.request.Request(s_url, headers={'User-Agent': 'Mozilla/5.0'})
                    with urllib.request.urlopen(req_s, timeout=5) as r_s:
                        h_s = r_s.read().decode('utf-8', errors='ignore')
                        tm = re.search(r'<title>(.*?)</title>', h_s, re.DOTALL)
                        title = tm.group(1).replace('Freesound - ', '').strip() if tm else 'Unknown'
                        hq = re.search(r'(https://cdn\.freesound\.org/previews/\d+/\d+_[^"\']+-hq\.mp3)', h_s)
                        mp3 = hq.group(1) if hq else ''
                        if mp3:
                            results[sid] = {"title": title, "user": user, "mp3": mp3, "query": q}
                            print(f"[{sid}] ({q}) {title} by {user}", flush=True)
                except:
                    pass
    except Exception as e:
        print(f"Error {q}: {e}", flush=True)

print(f"Total found: {len(results)}", flush=True)
