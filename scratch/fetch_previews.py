import urllib.request
import re

for sid in ['619007', '867450', '257793']:
    try:
        req = urllib.request.Request(f'https://freesound.org/s/{sid}/', headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=8) as r:
            h = r.read().decode('utf-8', errors='ignore')
            m = re.findall(r'https://cdn\.freesound\.org/previews/[^"\'\s]+\.mp3', h)
            title = re.search(r'<title>(.*?)</title>', h, re.DOTALL)
            t_str = title.group(1).strip() if title else ''
            print(f"[{sid}] {t_str}")
            for u in set(m):
                print(f"  {u}")
    except Exception as e:
        print(f"[{sid}] Error: {e}")
