import yt_dlp
import subprocess
import imageio_ffmpeg
import os

ffmpeg_exe = imageio_ffmpeg.get_ffmpeg_exe()
cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"
os.makedirs(cand_dir, exist_ok=True)

targets = {
    "golf_gallery_cheer_1": "https://www.youtube.com/watch?v=MsRmFaLQPPE",
    "golf_gallery_cheer_3": "https://www.youtube.com/watch?v=As76J4FSruo",
    "golf_gallery_whistle": "https://www.youtube.com/watch?v=iOzSueWw5tI",
    "outdoor_golf_applause": "https://www.youtube.com/watch?v=_GqwLW87dCQ",
    "golf_miss_groan": "https://www.youtube.com/watch?v=VRECg42otTs",
    "golf_moan_variations": "https://www.youtube.com/watch?v=zQbMXAQklUk",
    "wii_sports_golf_crowd": "https://www.youtube.com/watch?v=U9Cbr1etYOw",
    "crowd_aww_7s": "https://www.youtube.com/watch?v=ewGwngOFsXk"
}

ydl_opts = {
    'format': 'bestaudio[ext=m4a]/bestaudio',
    'outtmpl': os.path.join(cand_dir, 'raw_%(id)s.%(ext)s'),
    'quiet': True,
}

with yt_dlp.YoutubeDL(ydl_opts) as ydl:
    for key, url in targets.items():
        mp3_out = os.path.join(cand_dir, f"{key}.mp3")
        if os.path.exists(mp3_out) and os.path.getsize(mp3_out) > 0:
            print(f"Already exists: {key}")
            continue
        try:
            print(f"Downloading {key}...", flush=True)
            info = ydl.extract_info(url, download=True)
            vid = info.get('id')
            ext = info.get('ext', 'm4a')
            raw_path = os.path.join(cand_dir, f"raw_{vid}.{ext}")
            if not os.path.exists(raw_path):
                # Search for file matching vid
                for f in os.listdir(cand_dir):
                    if vid in f and f.startswith("raw_"):
                        raw_path = os.path.join(cand_dir, f)
                        break
            
            if os.path.exists(raw_path):
                # Convert to mp3 using ffmpeg
                cmd = [ffmpeg_exe, "-y", "-i", raw_path, "-vn", "-ar", "44100", "-ac", "2", "-b:a", "192k", mp3_out]
                subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                print(f"Converted {key} -> {mp3_out} ({os.path.getsize(mp3_out)} bytes)", flush=True)
                try:
                    os.remove(raw_path)
                except:
                    pass
        except Exception as e:
            print(f"Error {key}: {e}", flush=True)

print("Done downloading targets.", flush=True)
