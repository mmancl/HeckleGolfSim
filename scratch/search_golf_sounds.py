import urllib.request
import urllib.parse
import re

queries = [
    "golf cheer",
    "golf gallery",
    "golf crowd",
    "golf applause",
    "golf roar",
    "golf reaction",
    "golf groan",
    "gallery cheer",
    "crowd sigh",
    "crowd oh",
    "crowd groan sports",
    "crowd disappointment sports",
    "spectator cheer",
    "spectator groan",
    "audience oh"
]

print("Searching Freesound for authentic golf / sports gallery sounds...", flush=True)

results = {}
for q in queries:
    url = f"https://freesound.org/search/?q={urllib.parse.quote(q)}"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            html = resp.read().decode('utf-8', errors='ignore')
            matches = re.findall(r'href="(/people/([^/]+)/sounds/(\d+)/)"', html)
            seen = set()
            found = []
            for path, user, sid in matches:
                if sid in seen or sid in results:
                    continue
                seen.add(sid)
                found.append((sid, user, path))
                if len(found) >= 5:
                    break
            for sid, user, path in found:
                s_url = f"https://freesound.org{path}"
                try:
                    req_s = urllib.request.Request(s_url, headers={'User-Agent': 'Mozilla/5.0'})
                    with urllib.request.urlopen(req_s, timeout=6) as r_s:
                        h_s = r_s.read().decode('utf-8', errors='ignore')
                        tm = re.search(r'<title>(.*?)</title>', h_s, re.DOTALL)
                        title = tm.group(1).replace('Freesound - ', '').strip() if tm else 'Unknown'
                        hq_mp3 = re.search(r'(https://cdn\.freesound\.org/previews/\d+/\d+_[^"\']+-hq\.mp3)', h_s)
                        mp3 = hq_mp3.group(1) if hq_mp3 else ''
                        dur_m = re.search(r'class="duration">([^<]+)<', h_s)
                        dur = dur_m.group(1).strip() if dur_m else ''
                        lic_m = re.findall(r'creativecommons\.org/(?:publicdomain/zero/1\.0|licenses/[^"\'\s]+)', h_s)
                        lic = lic_m[0] if lic_m else 'Unknown'
                        
                        results[sid] = {
                            "query": q,
                            "user": user,
                            "title": title,
                            "mp3": mp3,
                            "duration": dur,
                            "license": lic,
                            "url": s_url
                        }
                        print(f"[{sid}] ({q}) {title} | {dur} | {lic}", flush=True)
                except Exception as ex:
                    pass
    except Exception as e:
        print(f"Error {q}: {e}", flush=True)

print(f"\nTotal unique sounds found: {len(results)}", flush=True)
