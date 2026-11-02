import os
import soundfile as sf
import numpy as np

cand_dir = r"c:\Users\micha\Repositories\HeckleGolfSim\scratch\candidates"

sounds = {
    # 1. Crowd Anticipation / Murmur (builds alongside heartbeat)
    "cheer_swell.mp3": {
        "category": "Anticipation / Build-up",
        "title": "Excited Swell (mglennsound - CC0)",
        "desc": "Natural acoustic crescendo of crowd excitement building as the ball rolls closer"
    },
    "craigsmith_golf_479967.mp3": {
        "category": "Anticipation / Background",
        "title": "R19-34 Golf Crowd Applauds & Murmur (craigsmith - CC0)",
        "desc": "Classic outdoor golf gallery presence with low background murmur"
    },
    
    # 2. Holed Out Cheers (when ball goes in cup)
    "crowd_roar_449915.mp3": {
        "category": "Cheer / Hole-In",
        "title": "Crowd Roar (jonsept - CC0)",
        "desc": "Eruptive loud outdoor sports cheer / roar when a big putt or chip sinks"
    },
    "crowd_cheering_264377.mp3": {
        "category": "Cheer / Hole-In",
        "title": "Small Crowd Cheering (HowardV - CC0)",
        "desc": "Enthusiastic, bright group cheering with excited whoops and applause"
    },
    "crowd_cheer_651646.mp3": {
        "category": "Cheer / Hole-In",
        "title": "Crowd Cheer 5 (Krizin - CC0)",
        "desc": "Punchy 7-second sports cheer burst with clear clapping and shouts"
    },
    "golf_cheer_618255.mp3": {
        "category": "Cheer / Hole-In",
        "title": "Golf Cheers (yukon456 - CC0)",
        "desc": "Authentic outdoor golf gallery shout and cheer"
    },

    # 3. Disappointed 'Awww' / Groans (when ball rolls past / misses)
    "aww_crowd.mp3": {
        "category": "Miss / Awww",
        "title": "Crowd Aww (phmiller42 - CC0)",
        "desc": "Classic unified crowd 'awww' groan of sympathy/disappointment right as it lips out or rolls past"
    },
    "aww_whisperpotato.mp3": {
        "category": "Miss / Awww",
        "title": "Crowd Awwww (WhisperPotato - CC0)",
        "desc": "Short, punchy 1.2-second synchronized collective groan / awww"
    },
    "crowd_ouch.mp3": {
        "category": "Miss / Awww",
        "title": "Crowd Ouch / Groan (Freesound CC0)",
        "desc": "Deep collective groan and grimace reaction from onlookers"
    }
}

for fname, meta in sounds.items():
    fpath = os.path.join(cand_dir, fname)
    if os.path.exists(fpath):
        data, sr = sf.read(fpath)
        dur = len(data) / sr
        peak = np.max(np.abs(data))
        rms = np.sqrt(np.mean(data**2))
        meta["duration"] = round(dur, 2)
        meta["sample_rate"] = sr
        meta["peak"] = round(float(peak), 2)
        meta["rms"] = round(float(rms), 3)

for cat in ["Anticipation / Build-up", "Cheer / Hole-In", "Miss / Awww"]:
    print(f"\n=== {cat} ===")
    for fname, meta in sounds.items():
        if meta.get("category") == cat:
            print(f"File: {fname}")
            print(f"  Title: {meta['title']}")
            print(f"  Duration: {meta.get('duration', 'N/A')}s | Peak: {meta.get('peak', 'N/A')} | RMS: {meta.get('rms', 'N/A')}")
            print(f"  Description: {meta['desc']}")
