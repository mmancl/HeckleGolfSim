import urllib.request
import urllib.parse
import re
import os

def search_and_download_candidates():
    out_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"
    os.makedirs(out_dir, exist_ok=True)
    
    searches = {
        "golf_cheer_1": "https://freesound.org/people/LoganACountry/sounds/621287/",
        "cheer_swell": "https://freesound.org/people/mglennsound/sounds/725698/",
        "aww_crowd": "https://freesound.org/people/phmiller42/sounds/124996/",
        "crowd_ouch": "https://freesound.org/people/deleted_user_2104797/sounds/324897/",
        "aww_whisperpotato": "https://freesound.org/people/WhisperPotato/sounds/547589/",
    }
    
    # Also find craigsmith sounds
    for q in ["craigsmith golf", "golf cheer", "crowd cheering", "crowd murmur", "crowd gasp"]:
        url = f"https://freesound.org/search/?q={urllib.parse.quote(q)}&f=license%3A%22Creative+Commons+0%22"
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                html = resp.read().decode('utf-8', errors='ignore')
                matches = re.findall(r'href="(/people/[^/]+/sounds/(\d+)/)"', html)
                for path, sid in matches[:2]:
                    searches[f"{q.replace(' ', '_')}_{sid}"] = f"https://freesound.org{path}"
        except Exception as e:
            print(f"Error {q}: {e}")

    print(f"Total candidate pages found: {len(searches)}")
    candidates = []
    
    for key, page_url in searches.items():
        req = urllib.request.Request(page_url, headers={'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'})
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                html = resp.read().decode('utf-8', errors='ignore')
                title_m = re.search(r'<title>(.*?)</title>', html, re.DOTALL)
                title = title_m.group(1).replace('Freesound - ', '').strip() if title_m else key
                # MP3 url
                hq_mp3 = re.search(r'(https://cdn\.freesound\.org/previews/\d+/\d+_[^"\']+-hq\.mp3)', html)
                lq_mp3 = re.search(r'(https://cdn\.freesound\.org/previews/\d+/\d+_[^"\']+-lq\.mp3)', html)
                mp3_url = hq_mp3.group(1) if hq_mp3 else (lq_mp3.group(1) if lq_mp3 else None)
                if mp3_url:
                    local_path = os.path.join(out_dir, f"{key}.mp3")
                    if not os.path.exists(local_path):
                        urllib.request.urlretrieve(mp3_url, local_path)
                    candidates.append({
                        "key": key,
                        "title": title,
                        "page_url": page_url,
                        "mp3_url": mp3_url,
                        "local_file": local_path,
                        "size_bytes": os.path.getsize(local_path)
                    })
                    print(f"Downloaded: {key} ({title}) -> {os.path.getsize(local_path)} bytes")
        except Exception as e:
            print(f"Failed {key} ({page_url}): {e}")

if __name__ == '__main__':
    search_and_download_candidates()
