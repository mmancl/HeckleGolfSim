import os
import urllib.request
import io
import numpy as np
import scipy.signal as signal
import soundfile as sf

SR = 44100

def load_and_resample(path_or_url, target_sr=SR):
    if path_or_url.startswith("http://") or path_or_url.startswith("https://"):
        req = urllib.request.Request(path_or_url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as resp:
            content = resp.read()
        data, sr = sf.read(io.BytesIO(content))
    else:
        data, sr = sf.read(path_or_url)
        
    if data.ndim > 1:
        data = data.mean(axis=1) # Mono for clean game audio
        
    if sr != target_sr:
        num_samples = int(len(data) * target_sr / sr)
        data = signal.resample(data, num_samples)
        
    return data

def extract_peak_clip(data, pre_time_s=0.005, post_time_s=0.25, sr=SR):
    peak_idx = np.argmax(np.abs(data))
    start = max(0, peak_idx - int(pre_time_s * sr))
    end = min(len(data), peak_idx + int(post_time_s * sr))
    return data[start:end]

def apply_fade(data, fade_in_s=0.002, fade_out_s=0.03, sr=SR):
    in_samples = int(fade_in_s * sr)
    out_samples = int(fade_out_s * sr)
    n = len(data)
    data = data.copy()
    if in_samples > 0 and in_samples < n:
        data[:in_samples] *= np.linspace(0, 1, in_samples)
    if out_samples > 0 and out_samples < n:
        data[-out_samples:] *= np.linspace(1, 0, out_samples)
    return data

def normalize(data, peak=0.45):
    m = np.max(np.abs(data))
    if m > 0:
        return (data / m) * peak
    return data

def pad_or_crop(data, target_samples):
    if len(data) >= target_samples:
        return data[:target_samples]
    res = np.zeros(target_samples)
    res[:len(data)] = data
    return res

def main():
    print("Processing real recorded golf sound effects (non-hits half volume)...")
    
    output_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "sfx")
    output_dir = os.path.abspath(output_dir)
    os.makedirs(output_dir, exist_ok=True)
    
    # Load raw real recordings
    golf_bounce_raw = load_and_resample('scratch/real_sounds/golf_ball_bounce_mkoenig_reduced.wav')
    stepgrass1_raw = load_and_resample('scratch/veloren_sfx/stepgrass_1.ogg')
    stepgrass2_raw = load_and_resample('scratch/veloren_sfx/stepgrass_2.ogg')
    stepdirt1_raw = load_and_resample('scratch/veloren_sfx/stepdirt_1.ogg')
    stepdirt2_raw = load_and_resample('scratch/veloren_sfx/stepdirt_2.ogg')
    wood_raw = load_and_resample('scratch/veloren_sfx/wood_step_1.ogg')
    splash_raw = load_and_resample('scratch/veloren_sfx/water_splash_1.ogg')
    drive_raw = load_and_resample('scratch/real_sounds/golf_hit_generic.wav')
    putt_raw = load_and_resample('scratch/real_sounds/golf_ball_putt_lmbubec.wav')
    leaves_raw = load_and_resample('scratch/veloren_sfx/leaves.ogg')
    
    # 1. Fairway Bounce (-2 dB reduction -> 0.357 peak)
    dur_samples = int(0.20 * SR)
    b_part = pad_or_crop(golf_bounce_raw, dur_samples)
    g_part = pad_or_crop(stepgrass1_raw, dur_samples)
    bounce_fairway = apply_fade(b_part * 0.7 + g_part * 0.4, fade_in_s=0.002, fade_out_s=0.04)
    bounce_fairway = normalize(bounce_fairway, 0.357)
    
    # 2. Green Bounce (0.42 peak)
    dur_samples = int(0.16 * SR)
    b_part = pad_or_crop(golf_bounce_raw, dur_samples)
    g_part = pad_or_crop(stepgrass2_raw, dur_samples)
    bounce_green = apply_fade(b_part * 0.6 + g_part * 0.4, fade_in_s=0.002, fade_out_s=0.03)
    bounce_green = normalize(bounce_green, 0.42)
    
    # 3. Rough Thump (-2 dB reduction -> 0.357 peak)
    dur_samples = int(0.28 * SR)
    rough_thump = apply_fade(pad_or_crop(stepdirt1_raw, dur_samples), fade_in_s=0.002, fade_out_s=0.05)
    rough_thump = normalize(rough_thump, 0.357)
    
    # 4. Sand Thud (0.45 peak)
    dur_samples = int(0.35 * SR)
    sand_thud = apply_fade(pad_or_crop(stepdirt2_raw, dur_samples), fade_in_s=0.002, fade_out_s=0.06)
    sand_thud = normalize(sand_thud, 0.45)
    
    # 5. Tree Hit (+1 dB increase -> 0.505 peak)
    dur_samples = int(0.22 * SR)
    tree_hit = apply_fade(pad_or_crop(wood_raw, dur_samples), fade_in_s=0.001, fade_out_s=0.04)
    tree_hit = normalize(tree_hit, 0.505)
    
    # 6. Leaf Rustle (0.40 peak)
    start_idx = int(2.0 * SR)
    leaf_slice = pad_or_crop(leaves_raw[start_idx:], int(0.45 * SR))
    leaf_rustle = apply_fade(leaf_slice, fade_in_s=0.05, fade_out_s=0.08)
    leaf_rustle = normalize(leaf_rustle, 0.40)
    
    # 7. Water Splash (+1 dB increase -> 0.516 peak)
    dur_samples = int(0.85 * SR)
    water_splash = apply_fade(pad_or_crop(splash_raw, dur_samples), fade_in_s=0.002, fade_out_s=0.12)
    water_splash = normalize(water_splash, 0.516)
    
    # 8. Drive Shot (Full Volume -> 0.95 peak)
    drive_clip = extract_peak_clip(drive_raw, pre_time_s=0.005, post_time_s=0.38)
    ball_hit_drive = apply_fade(drive_clip, fade_in_s=0.001, fade_out_s=0.05)
    ball_hit_drive = normalize(ball_hit_drive, 0.95)
    
    # 9. Putt Shot (Full Volume -> 0.95 peak, centered on real putter hit peak)
    putt_clip = extract_peak_clip(putt_raw, pre_time_s=0.005, post_time_s=0.20)
    ball_hit_putt = apply_fade(putt_clip, fade_in_s=0.001, fade_out_s=0.04)
    ball_hit_putt = normalize(ball_hit_putt, 0.95)
    
    outputs = {
        "bounce_fairway.ogg": bounce_fairway,
        "bounce_green.ogg": bounce_green,
        "rough_thump.ogg": rough_thump,
        "sand_thud.ogg": sand_thud,
        "tree_hit.ogg": tree_hit,
        "leaf_rustle.ogg": leaf_rustle,
        "water_splash.ogg": water_splash,
        "ball_hit_drive.ogg": ball_hit_drive,
        "ball_hit_putt.ogg": ball_hit_putt,
    }
    
    for filename, audio in outputs.items():
        filepath = os.path.join(output_dir, filename)
        sf.write(filepath, audio, SR, format='OGG', subtype='VORBIS')
        print(f"Written {filename:20s}: duration={len(audio)/SR:.2f}s, peak={np.max(np.abs(audio)):.3f}")

if __name__ == "__main__":
    main()
