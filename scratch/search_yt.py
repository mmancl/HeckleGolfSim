import yt_dlp
import json

queries = [
    "golf crowd cheer sound effect",
    "golf cheer sound effect",
    "golf applause sound effect",
    "crowd aww sound effect golf",
    "golf crowd groan sound effect",
    "golf gallery cheer sound effect",
    "crowd sigh golf sound effect"
]

ydl_opts = {
    'quiet': True,
    'extract_flat': True,
    'default_search': 'ytsearch3',
}

results = []
with yt_dlp.YoutubeDL(ydl_opts) as ydl:
    for q in queries:
        try:
            info = ydl.extract_info(f"ytsearch3:{q}", download=False)
            if 'entries' in info:
                for entry in info['entries']:
                    results.append({
                        'query': q,
                        'id': entry.get('id'),
                        'title': entry.get('title'),
                        'url': f"https://www.youtube.com/watch?v={entry.get('id')}",
                        'duration': entry.get('duration')
                    })
        except Exception as e:
            print(f"Error {q}: {e}")

for r in results:
    print(f"[{r['query']}] {r['title']} ({r['duration']}s) -> {r['url']}")
