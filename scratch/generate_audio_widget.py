import os
import base64
import json

art_dir = r"C:\Users\micha\.gemini\antigravity\brain\c7e82aa1-43b9-4dc7-bafd-24ad5ce9cf1f"
cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"
os.makedirs(art_dir, exist_ok=True)

sound_files = {
    # Anticipation
    "anticipation_swell": {
        "file": "cheer_swell.mp3",
        "category": "1. Crowd Anticipation (Alongside Heartbeat)",
        "label": "Option A: Excited Crowd Swell (14.5s)",
        "author": "mglennsound (CC0 Public Domain)",
        "desc": "Natural acoustic crescendo of crowd anticipation building alongside the heartbeat as the ball rolls closer to the cup."
    },
    # Holed Out Cheers
    "cheer_roar": {
        "file": "crowd_roar_449915.mp3",
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 1: Stadium / Big Gallery Roar (21.3s)",
        "author": "jonsept (CC0 Public Domain)",
        "desc": "A massive, eruptive outdoor cheer and roar when sinking a clutch putt or chip."
    },
    "cheer_burst": {
        "file": "crowd_cheer_651646.mp3",
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 2: Punchy Sports Cheer Burst (6.3s)",
        "author": "Krizin (CC0 Public Domain)",
        "desc": "Energetic, punchy celebration with clapping, shouting, and whistles."
    },
    "cheer_small_crowd": {
        "file": "crowd_cheering_264377.mp3",
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 3: Enthusiastic Gallery Cheers (24.6s)",
        "author": "HowardV (CC0 Public Domain)",
        "desc": "Warm, lively crowd cheering with whoops, applause, and excitement."
    },
    "cheer_golf_shot": {
        "file": "golf_cheer_618255.mp3",
        "category": "2. Hole-In Celebration Cheering",
        "label": "Option 4: Authentic Golf Shot Cheer (3.8s)",
        "author": "yukon456 (CC0 Public Domain)",
        "desc": "Short, crisp authentic golf spectator yell and applause right off the cup."
    },
    # Missed Shot Awws
    "aww_classic": {
        "file": "aww_crowd.mp3",
        "category": "3. Miss / Roll-Past 'Awww' Reactions",
        "label": "Option 1: Classic Crowd 'Awwww' (2.0s) [Recommended]",
        "author": "phmiller42 (CC0 Public Domain)",
        "desc": "The quintessential, unified crowd pity groan ('awww!') when the ball lips out or rolls just past the cup."
    },
    "aww_quick": {
        "file": "aww_whisperpotato.mp3",
        "category": "3. Miss / Roll-Past 'Awww' Reactions",
        "label": "Option 2: Snappy Collective Aww (1.2s)",
        "author": "WhisperPotato (CC0 Public Domain)",
        "desc": "Fast, punchy 1.2s reaction, great for quick transitions back to normal play."
    },
    "aww_groan": {
        "file": "crowd_ouch.mp3",
        "category": "3. Miss / Roll-Past 'Awww' Reactions",
        "label": "Option 3: Crowd Ouch / Sympathy Groan (17.8s)",
        "author": "Freesound (CC0 Public Domain)",
        "desc": "A slightly deeper, visceral reaction from onlookers feeling the pain of a close miss."
    }
}

b64_data = {}
for sid, info in sound_files.items():
    p = os.path.join(cand_dir, info["file"])
    if os.path.exists(p):
        with open(p, "rb") as f:
            b64_data[sid] = base64.b64encode(f.read()).decode("utf-8")
        print(f"Encoded {sid}: {len(b64_data[sid])} b64 chars")

html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Crowd SFX Review & Selection</title>
  <script src="https://www.gstatic.com/antigravity/web/dev/tailwindcss.min.js"></script>
</head>
<body class="bg-[var(--background)] text-[var(--foreground)] p-6 font-sans">
  <div class="max-w-4xl mx-auto space-y-6">
    <!-- Header -->
    <div class="border-b border-[var(--border)] pb-4">
      <div class="flex items-center space-x-3">
        <span class="text-3xl">⛳ 📢</span>
        <div>
          <h1 class="text-2xl font-bold tracking-tight text-[var(--foreground)]">Crowd Sound Effects Review</h1>
          <p class="text-sm text-[var(--muted-foreground)]">Listen to the candidate audio clips below and let me know your preferences before implementation.</p>
        </div>
      </div>
    </div>

    <!-- Category Sections -->
"""

categories = [
    ("1. Crowd Anticipation (Alongside Heartbeat)", "Plays softly as suspense triggers, swelling in volume as the ball rolls closer to the pin."),
    ("2. Hole-In Celebration Cheering", "Triggers instantly when the ball sinks into the cup with victorious roaring/cheering."),
    ("3. Miss / Roll-Past 'Awww' Reactions", "Triggers the moment the ball rolls past the hole or misses, immediately stopping the heartbeat.")
]

for cat_title, cat_subtitle in categories:
    html_content += f"""
    <!-- Section -->
    <div class="bg-[var(--card)] rounded-xl border border-[var(--border)] p-5 space-y-4 shadow-sm">
      <div>
        <h2 class="text-lg font-semibold text-[var(--foreground)]">{cat_title}</h2>
        <p class="text-xs text-[var(--muted-foreground)]">{cat_subtitle}</p>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
"""
    for sid, info in sound_files.items():
        if info["category"] != cat_title or sid not in b64_data:
            continue
        audio_src = f"data:audio/mp3;base64,{b64_data[sid]}"
        html_content += f"""
        <div class="bg-[var(--background)] border border-[var(--border)] rounded-lg p-4 flex flex-col justify-between space-y-3 hover:border-[var(--primary)] transition-colors">
          <div>
            <div class="flex justify-between items-start mb-1">
              <span class="font-medium text-sm text-[var(--foreground)]">{info['label']}</span>
              <span class="text-[11px] px-2 py-0.5 rounded bg-[var(--secondary)] text-[var(--secondary-foreground)] font-mono">CC0</span>
            </div>
            <p class="text-xs text-[var(--muted-foreground)] mb-2">{info['desc']}</p>
            <p class="text-[11px] text-[var(--muted-foreground)] opacity-75">Source: {info['author']}</p>
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
      <p>1. Click play on each candidate sound above to test how they feel in terms of tone, realism, and energy.</p>
      <p>2. Reply with your preferred choice for each category (e.g. <em>"Use Option 1 for cheer and Option 1 for aww"</em>) or request adjustments.</p>
      <p>3. Once confirmed, I will integrate them into <code>TensionManager.gd</code> and wire the volume curve and hole-passing triggers!</p>
    </div>
  </div>
</body>
</html>
"""

out_html = os.path.join(art_dir, "audio_review.html")
with open(out_html, "w", encoding="utf-8") as f:
    f.write(html_content)

print(f"Generated {out_html} ({os.path.getsize(out_html)} bytes)")
