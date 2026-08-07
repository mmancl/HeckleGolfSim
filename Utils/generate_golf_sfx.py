import os
import numpy as np
import scipy.signal as signal
import soundfile as sf

SR = 44100

def noise(n_samples):
    return np.random.uniform(-1.0, 1.0, n_samples)

def bandpass(data, lowcut, highcut, fs=SR, order=2):
    nyq = 0.5 * fs
    low = max(0.001, min(lowcut / nyq, 0.99))
    high = max(low + 0.001, min(highcut / nyq, 0.99))
    b, a = signal.butter(order, [low, high], btype='band')
    return signal.lfilter(b, a, data)

def normalize(audio, peak=0.9):
    max_val = np.max(np.abs(audio))
    if max_val > 0:
        return (audio / max_val) * peak
    return audio

def generate_bounce_fairway():
    # 0.16s: Solid golf ball (45.9g) hitting turf
    dur = 0.16
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    # Low thud transient: pitch drop 180Hz -> 130Hz
    freq = 180.0 - 50.0 * (t / dur)**0.5
    phase = 2 * np.pi * np.cumsum(freq) / SR
    thud = np.sin(phase) * np.exp(-t * 45)
    
    # Turf grass compression noise
    grass_noise = bandpass(noise(len(t)), 600, 2400) * np.exp(-t * 55)
    
    audio = thud * 0.7 + grass_noise * 0.4
    return normalize(audio, 0.9)

def generate_bounce_green():
    # 0.12s: Softer bentgrass green turf bounce
    dur = 0.12
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    freq = 150.0 - 40.0 * (t / dur)**0.5
    phase = 2 * np.pi * np.cumsum(freq) / SR
    thud = np.sin(phase) * np.exp(-t * 60)
    
    grass_noise = bandpass(noise(len(t)), 400, 1600) * np.exp(-t * 70)
    
    audio = thud * 0.75 + grass_noise * 0.35
    return normalize(audio, 0.85)

def generate_rough_thump():
    # 0.24s: Deep grass/dirt absorption thump
    dur = 0.24
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    freq = 120.0 - 40.0 * (t / dur)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    thud = np.sin(phase) * np.exp(-t * 28)
    
    foliage = bandpass(noise(len(t)), 300, 1500) * np.exp(-t * 22)
    
    audio = thud * 0.6 + foliage * 0.5
    return normalize(audio, 0.9)

def generate_sand_thud():
    # 0.35s: Bunker sand displacement impact
    dur = 0.35
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    freq = 130.0 - 60.0 * (t / dur)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    thud = np.sin(phase) * np.exp(-t * 25)
    
    # Sand grit spray with quick attack and decay
    attack = (1.0 - np.exp(-t * 150.0))
    sand_noise = bandpass(noise(len(t)), 400, 3200) * attack * np.exp(-t * 16)
    
    audio = thud * 0.5 + sand_noise * 0.6
    return normalize(audio, 0.9)

def generate_tree_hit():
    # 0.20s: Solid wood branch or trunk hit ("THWACK")
    dur = 0.20
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    wood_snap = np.sin(2 * np.pi * 620 * t) * np.exp(-t * 65) + \
                np.sin(2 * np.pi * 1350 * t) * np.exp(-t * 80)
    wood_thud = np.sin(2 * np.pi * 180 * t) * np.exp(-t * 35)
    bark_noise = bandpass(noise(len(t)), 1200, 4800) * np.exp(-t * 70)
    
    audio = wood_snap * 0.5 + wood_thud * 0.4 + bark_noise * 0.3
    return normalize(audio, 0.92)

def generate_leaf_rustle():
    # 0.45s: Ball cutting through canopy leaves
    dur = 0.45
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    leaf_noise = bandpass(noise(len(t)), 2200, 7500)
    # Bell-curve skewed envelope for ball passing through foliage
    env = np.sin(np.pi * (t / dur)**0.7) * np.exp(-t * 3.2)
    audio = leaf_noise * env
    
    # Add 4 micro leaf snaps (branch/leaf breaks)
    for snap_time in [0.08, 0.16, 0.25, 0.33]:
        idx = int(snap_time * SR)
        if idx < len(t) - 100:
            snap_len = 80
            audio[idx:idx+snap_len] += noise(snap_len) * 0.4 * np.exp(-np.linspace(0, 1, snap_len)*10)
            
    return normalize(audio, 0.8)

def generate_water_splash():
    # 0.75s: Golf ball splash into water (plunge + spray + subside)
    dur = 0.75
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    # Plunge cavity pitch glide (320Hz -> 90Hz)
    freq = 320.0 - 230.0 * np.clip(t / 0.06, 0, 1)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    plunge = np.sin(phase) * np.exp(-t * 18)
    
    # Water splash spray noise
    attack = (1.0 - np.exp(-t * 70.0))
    spray_noise = bandpass(noise(len(t)), 900, 5200) * attack * np.exp(-t * 6.0)
    
    # Secondary droplet pops
    drops = np.zeros_like(t)
    for drop_time in [0.12, 0.22, 0.38, 0.50]:
        idx = int(drop_time * SR)
        if idx < len(t) - 200:
            d_t = np.linspace(0, 0.03, 200, endpoint=False)
            d_freq = 1400.0 - drop_time * 500.0
            drops[idx:idx+200] += np.sin(2 * np.pi * d_freq * d_t) * np.exp(-d_t * 150) * 0.3
            
    audio = plunge * 0.5 + spray_noise * 0.6 + drops * 0.3
    return normalize(audio, 0.92)

def generate_ball_hit_drive():
    # 0.40s: Titanium driver tee shot snap
    dur = 0.40
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    face_ping = np.sin(2 * np.pi * 2750 * t) * np.exp(-t * 22) + \
                np.sin(2 * np.pi * 3850 * t) * np.exp(-t * 30)
    head_thud = np.sin(2 * np.pi * 240 * t) * np.exp(-t * 20)
    crack_noise = bandpass(noise(len(t)), 2500, 8500) * np.exp(-t * 35)
    
    audio = face_ping * 0.4 + head_thud * 0.5 + crack_noise * 0.35
    return normalize(audio, 0.95)

def generate_ball_hit_putt():
    # 0.12s: Putter face click on green
    dur = 0.12
    t = np.linspace(0, dur, int(SR * dur), endpoint=False)
    
    pop = np.sin(2 * np.pi * 350 * t) * np.exp(-t * 65) + \
          np.sin(2 * np.pi * 1100 * t) * np.exp(-t * 90)
    click_noise = bandpass(noise(len(t)), 800, 2400) * np.exp(-t * 85)
    
    audio = pop * 0.6 + click_noise * 0.3
    return normalize(audio, 0.82)

def main():
    output_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
    output_dir = os.path.abspath(output_dir)
    os.makedirs(output_dir, exist_ok=True)
    
    generators = {
        "bounce_fairway.ogg": generate_bounce_fairway,
        "bounce_green.ogg": generate_bounce_green,
        "rough_thump.ogg": generate_rough_thump,
        "sand_thud.ogg": generate_sand_thud,
        "tree_hit.ogg": generate_tree_hit,
        "leaf_rustle.ogg": generate_leaf_rustle,
        "water_splash.ogg": generate_water_splash,
        "ball_hit_drive.ogg": generate_ball_hit_drive,
        "ball_hit_putt.ogg": generate_ball_hit_putt
    }
    
    for filename, gen_fn in generators.items():
        filepath = os.path.join(output_dir, filename)
        audio = gen_fn()
        sf.write(filepath, audio, SR, format='OGG', subtype='VORBIS')
        print(f"Generated {filename:20s}: duration={len(audio)/SR:.2f}s, peak={np.max(np.abs(audio)):.3f}")

if __name__ == "__main__":
    main()
