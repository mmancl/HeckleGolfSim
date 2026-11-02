import os
import urllib.request
import re

out_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"

files = [f for f in os.listdir(out_dir) if f.endswith('.mp3') and os.path.getsize(os.path.join(out_dir, f)) > 0]

print(f"Non-empty files ({len(files)}):")
for f in files:
    full_path = os.path.join(out_dir, f)
    size = os.path.getsize(full_path)
    # Check if we can find sound ID in filename
    m = re.search(r'(\d+)', f)
    sid = m.group(1) if m else None
    title = f
    if sid:
        try:
            req = urllib.request.Request(f"https://freesound.org/s/{sid}/", headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=5) as resp:
                html = resp.read().decode('utf-8', errors='ignore')
                tm = re.search(r'<title>(.*?)</title>', html, re.DOTALL)
                if tm:
                    title = tm.group(1).replace('Freesound - ', '').strip()
        except Exception as e:
            pass
    elif f == "aww_crowd.mp3":
        title = "aww.wav by phmiller42 (Small audience pity moan/aww)"
    elif f == "aww_whisperpotato.mp3":
        title = "awwwww.mp3 by WhisperPotato (Crowd aww in unison)"
    elif f == "cheer_swell.mp3":
        title = "Exp_Crowd Excited Swell_02 by mglennsound (Excited crowd swelling build-up)"
    elif f == "golf_cheer_1.mp3":
        title = "Golf Fan Cheer Shout by LoganACountry (Golf spectator shouting/cheering)"
    elif f == "crowd_ouch.mp3":
        title = "Crowd Ouch.wav by deleted_user (Audience groaning ouch/aww)"
        
    print(f"- {f}: {size} bytes | {title}")
