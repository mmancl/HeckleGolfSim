import os
import base64

art_dir = r"C:\Users\micha\.gemini\antigravity\brain\c7e82aa1-43b9-4dc7-bafd-24ad5ce9cf1f"
cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"

golf_sounds = {
    # Anticipation
    "golf_anticipation_murmur": {
        "category": "1. Crowd Anticipation (Alongside Heartbeat)",
        "label": "Option A: Outdoor Golf Gallery Murmur (7.0s)",
        "desc": "Hushed, atmospheric outdoor golf tournament gallery presence. Scales up in volume as the ball rolls closer."
    },
    # Cheers
    "golf_cheer_yukon_hazard": {
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 1: Outdoor Golf Gallery Cheer (3.8s) [Your Favorite Style]",
        "desc": "Authentic outdoor golf gallery shout and cheer: 'Yeah! Great shot!' with enthusiastic outdoor applause."
    },
    "golf_cheer_yukon_goodshot": {
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 2: Golf Spectator Shout & Warm Applause (4.8s)",
        "desc": "Crisp outdoor golf spectator reaction with genuine gallery applause as the putt sinks."
    },
    "golf_cheer_gallery_1": {
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 3: PGA-Style Outdoor Gallery Roar (6.5s)",
        "desc": "Medium outdoor golf gallery applauding and cheering with great open-air acoustics."
    },
    "golf_cheer_gallery_3": {
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 4: Outdoor Gallery Cheering Variation (7.0s)",
        "desc": "Warm, spirited outdoor gallery reaction with whistles and sustained clapping."
    },
    "golf_cheer_wii_huge_roar": {
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 5: Tournament Big Cup Roar (6.5s)",
        "desc": "The iconic, energetic tournament golf gallery roar when dropping a clutch putt or chip."
    },
    "golf_cheer_wii_classic": {
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 6: Tournament Gallery Applause (5.5s)",
        "desc": "Smooth, refined tournament gallery cheer and applause."
    },
    # Aww / Miss
    "golf_aww_groan_wii": {
        "category": "3. Miss / Roll-Past 'Awww' Reactions",
        "label": "Option 1: Golf Gallery 'Awww' / Groan (1.8s) [Recommended]",
        "desc": "Authentic golf gallery groan / 'awww' right as the ball slides past the cup or lips out."
    },
    "golf_aww_groan_wii_alt": {
        "category": "3. Miss / Roll-Past 'Awww' Reactions",
        "label": "Option 2: Golf Gallery Sympathy Groan (2.0s)",
        "desc": "Slightly deeper collective gallery groan of disappointment from onlookers on the green."
    },
    "golf_aww_crowd_phmiller": {
        "category": "3. Miss / Roll-Past 'Awww' Reactions",
        "label": "Option 3: Classic Collective 'Awwww' (2.0s)",
        "desc": "Synchronized, sympathetic 'awwww!' reaction when barely missing."
    }
}

b64_data = {}
for sid in golf_sounds:
    fpath = os.path.join(cand_dir, f"{sid}.mp3")
    if os.path.exists(fpath):
        with open(fpath, "rb") as f:
            b64_data[sid] = base64.b64encode(f.read()).decode("utf-8")
        print(f"Encoded {sid}: {len(b64_data[sid])} chars")

html_content = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Outdoor Golf Crowd SFX Review</title>
  <script src="https://www.gstatic.com/antigravity/web/dev/tailwindcss.min.js"></script>
</head>
<body class="bg-[var(--background)] text-[var(--foreground)] p-6 font-sans">
  <div class="max-w-4xl mx-auto space-y-6">
    <!-- Header -->
    <div class="border-b border-[var(--border)] pb-4">
      <div class="flex items-center space-x-3">
        <span class="text-3xl">⛳ 👏</span>
        <div>
          <h1 class="text-2xl font-bold tracking-tight text-[var(--foreground)]">Authentic Golf Gallery Sound Effects</h1>
          <p class="text-sm text-[var(--muted-foreground)]">Focused specifically on real outdoor golf gallery cheers, open-air acoustics, and golf missed-putt groans.</p>
        </div>
      </div>
    </div>
"""

categories = [
    ("1. Crowd Anticipation (Alongside Heartbeat)", "Plays softly as suspense triggers, swelling in volume as the ball rolls closer to the pin."),
    ("2. Hole-In Celebration Cheering", "Triggers instantly when the ball drops into the cup with victorious golf gallery cheering/applause."),
    ("3. Miss / Roll-Past 'Awww' Reactions", "Triggers the exact moment the ball rolls past the hole and won't drop, immediately stopping the heartbeat.")
]

for cat_title, cat_subtitle in categories:
    html_content += f"""
    <div class="bg-[var(--card)] rounded-xl border border-[var(--border)] p-5 space-y-4 shadow-sm">
      <div>
        <h2 class="text-lg font-semibold text-[var(--foreground)]">{cat_title}</h2>
        <p class="text-xs text-[var(--muted-foreground)]">{cat_subtitle}</p>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
"""
    for sid, info in golf_sounds.items():
        if info["category"] != cat_title or sid not in b64_data:
            continue
        audio_src = f"data:audio/mp3;base64,{b64_data[sid]}"
        html_content += f"""
        <div class="bg-[var(--background)] border border-[var(--border)] rounded-lg p-4 flex flex-col justify-between space-y-3 hover:border-[var(--primary)] transition-colors">
          <div>
            <div class="flex justify-between items-start mb-1">
              <span class="font-medium text-sm text-[var(--foreground)]">{info['label']}</span>
              <span class="text-[11px] px-2 py-0.5 rounded bg-[var(--secondary)] text-[var(--secondary-foreground)] font-mono">Golf SFX</span>
            </div>
            <p class="text-xs text-[var(--muted-foreground)] mb-1">{info['desc']}</p>
          </div>
          <audio controls class="w-full h-8 pt-1" preload="none">
            <source src="{audio_src}" type="audio/mp3">
            Your browser does not support audio.
          </audio>
        </div>
"""
    html_content += """
      </div>
    </div>
"""

html_content += """
    <!-- Instructions Footer -->
    <div class="bg-[var(--secondary)] text-[var(--secondary-foreground)] rounded-lg p-4 text-xs space-y-1">
      <p class="font-semibold">Review Instructions:</p>
      <p>1. Test the pure golf clips above by pressing play on each audio player.</p>
      <p>2. Let me know which <strong>Cheer</strong> and which <strong>Awww</strong> you like best!</p>
      <p>3. Once you give the thumbs up, I will wire the sounds, heartbeat timing, distance volume curve, and instant miss deactivation into the game!</p>
    </div>
  </div>
</body>
</html>
"""

out_html = os.path.join(art_dir, "audio_review.html")
with open(out_html, "w", encoding="utf-8") as f:
    f.write(html_content)

print(f"Updated {out_html} ({os.path.getsize(out_html)} bytes)")
