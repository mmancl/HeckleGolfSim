import os
import sys
import json
import random
import re
import argparse
import tempfile
import numpy as np
import torch
import soundfile as sf
import torchaudio.functional as F

# Fix PyTorch 2.6+ unpickling compatibility
try:
    if hasattr(np, "_core"):
        torch.serialization.add_safe_globals([np._core.multiarray.scalar])
    else:
        torch.serialization.add_safe_globals([np.core.multiarray.scalar])
except Exception:
    pass

_orig_torch_load = torch.load
def _patched_torch_load(*args, **kwargs):
    kwargs.setdefault('weights_only', False)
    return _orig_torch_load(*args, **kwargs)
torch.load = _patched_torch_load

device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"Using device: {device} ({torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'})")

try:
    from f5_tts.api import F5TTS
    from f5_tts.infer.utils_infer import infer_process
except ImportError:
    print("\n[Error] F5-TTS library is not installed.")
    print("Please install it using: pip install f5-tts soundfile")
    sys.exit(1)


def prepare_reference_audio(ref_path: str, max_duration_sec: float = 6.5):
    """
    Loads, normalizes, and prepares a clean, properly sized (<= 6.5s) mono 24kHz WAV for F5-TTS DiT.
    Avoids external ffprobe/pydub dependencies completely.
    """
    data, sr = sf.read(ref_path)
    if len(data.shape) > 1:
        data = data.mean(axis=1)
    
    # Resample to 24000Hz if needed
    if sr != 24000:
        waveform_tensor = torch.from_numpy(data).unsqueeze(0).float()
        resampled_tensor = F.resample(waveform_tensor, orig_freq=sr, new_freq=24000)
        data = resampled_tensor.squeeze(0).numpy()
        sr = 24000

    max_samples = int(sr * max_duration_sec)
    is_sliced = len(data) > max_samples
    if is_sliced:
        data = data[:max_samples]
    
    temp_dir = tempfile.gettempdir()
    temp_wav = os.path.join(temp_dir, f"f5_ref_{os.path.basename(ref_path)}")
    sf.write(temp_wav, data, sr)
    return temp_wav, data, sr, is_sliced


def get_or_transcribe_reference_text(ref_wav_path: str, audio_data: np.ndarray, sr: int, cached_txt_path: str = None, is_sliced: bool = False) -> str:
    """
    Retrieves reference text for the exact audio slice passed to F5-TTS.
    If the audio was sliced from a longer file, it auto-transcribes only the sliced portion
    to guarantee zero transcript leakage or mismatched timing.
    """
    if cached_txt_path and os.path.isfile(cached_txt_path) and not is_sliced:
        with open(cached_txt_path, "r", encoding="utf-8") as f:
            txt = f.read().strip()
            if txt:
                return txt

    print(f"\n[Whisper] Transcribing reference clip ({os.path.basename(ref_wav_path)}) for precise alignment...")
    try:
        from transformers import WhisperProcessor, WhisperForConditionalGeneration
        processor = WhisperProcessor.from_pretrained("openai/whisper-tiny")
        model = WhisperForConditionalGeneration.from_pretrained("openai/whisper-tiny").to(device)
        
        # Resample to 16kHz for Whisper
        audio_tensor = torch.from_numpy(audio_data).unsqueeze(0).float()
        audio_16k = F.resample(audio_tensor, orig_freq=sr, new_freq=16000).squeeze(0).numpy()
        
        input_features = processor(audio_16k, sampling_rate=16000, return_tensors="pt").input_features.to(device)
        predicted_ids = model.generate(input_features, language="en")
        transcript = processor.batch_decode(predicted_ids, skip_special_tokens=True)[0].strip()
        
        if cached_txt_path and not is_sliced:
            try:
                with open(cached_txt_path, "w", encoding="utf-8") as f:
                    f.write(transcript)
            except Exception:
                pass
                
        return transcript
    except Exception as e:
        print(f"[Warning] Whisper auto-transcription notice: {e}")
        return "This is a sample voice clip for reference."


def resolve_speaker_files(speaker_name: str, voice_dir: str):
    """Finds reference WAV audio and companion transcript for a given speaker identifier."""
    ref_wav = None
    txt_file = None
    
    # 1. Direct path check
    if os.path.isfile(speaker_name):
        ref_wav = os.path.abspath(speaker_name)
    else:
        clean_name = os.path.splitext(os.path.basename(speaker_name))[0]
        candidate_names = [
            f"{clean_name}_reference_cleaned.wav",
            f"{clean_name}_reference.wav",
            f"{clean_name}_test_sample.wav",
            f"{clean_name}.wav",
            f"{speaker_name}.wav",
            f"{speaker_name}",
        ]
        
        for candidate in candidate_names:
            full_candidate = os.path.join(voice_dir, candidate)
            if os.path.isfile(full_candidate):
                ref_wav = os.path.abspath(full_candidate)
                break

        # Search voice_dir for any matching .wav
        if not ref_wav and os.path.isdir(voice_dir):
            for f in os.listdir(voice_dir):
                if f.lower().endswith(".wav") and clean_name.lower() in f.lower():
                    ref_wav = os.path.abspath(os.path.join(voice_dir, f))
                    break
            
            # Fallback to first available .wav file
            if not ref_wav:
                all_wavs = [f for f in os.listdir(voice_dir) if f.lower().endswith(".wav")]
                if all_wavs:
                    ref_wav = os.path.abspath(os.path.join(voice_dir, all_wavs[0]))
                    print(f"[Warning] Could not find speaker '{speaker_name}'. Falling back to: {all_wavs[0]}")

    if ref_wav:
        wav_base = os.path.splitext(ref_wav)[0]
        txt_candidates = [
            f"{wav_base}.txt",
            f"{wav_base.replace('_cleaned', '')}.txt",
            f"{wav_base.replace('_test_sample', '')}.txt",
        ]
        for tc in txt_candidates:
            if tc and os.path.isfile(tc):
                txt_file = tc
                break
        if not txt_file:
            txt_file = f"{wav_base}.txt"

    return ref_wav, txt_file


# Global cache for prepared speaker reference assets
_SPEAKER_CACHE = {}
_LAUGH_CACHE = {}

def get_prepared_speaker_assets(speaker_name: str, voice_dir: str, manual_ref_text: str = ""):
    """Retrieves and caches prepared reference audio slice and transcript for a speaker."""
    cache_key = (speaker_name, manual_ref_text)
    if cache_key in _SPEAKER_CACHE:
        return _SPEAKER_CACHE[cache_key]
    
    ref_wav_path, companion_txt = resolve_speaker_files(speaker_name, voice_dir)
    if not ref_wav_path or not os.path.isfile(ref_wav_path):
        raise FileNotFoundError(f"No reference audio found for speaker '{speaker_name}' in '{voice_dir}'.")
    
    prep_wav, audio_data, sr, was_sliced = prepare_reference_audio(ref_wav_path, max_duration_sec=6.5)
    
    if manual_ref_text:
        ref_text = manual_ref_text.strip()
    else:
        ref_text = get_or_transcribe_reference_text(prep_wav, audio_data, sr, companion_txt, is_sliced=was_sliced)
    
    assets = {
        "prep_wav": prep_wav,
        "ref_text": ref_text,
        "orig_path": ref_wav_path
    }
    _SPEAKER_CACHE[cache_key] = assets
    return assets


def resolve_laugh_file(speaker_name: str, voice_dir: str):
    """Finds matching acoustic laugh WAV file for a given speaker."""
    clean = os.path.splitext(os.path.basename(speaker_name))[0].lower()
    clean = clean.replace("_reference_cleaned", "").replace("_test_sample", "")
    
    candidates = [
        f"{clean}_laugh_reference_cleaned.wav",
        f"{clean}_laugh_test_sample.wav",
        f"{clean}_laugh.wav",
        f"{clean}_chuckle.wav",
    ]
    for cand in candidates:
        fp = os.path.join(voice_dir, cand)
        if os.path.isfile(fp):
            return fp
            
    if os.path.isdir(voice_dir):
        for f in os.listdir(voice_dir):
            if "laugh" in f.lower() and clean in f.lower() and f.lower().endswith(".wav"):
                return os.path.join(voice_dir, f)
    return None


def get_prepared_laugh(speaker_name: str, voice_dir: str, target_sr: int = 24000, max_duration: float = 1.8):
    """Retrieves, trims, and normalizes acoustic laugh sample for a speaker."""
    if speaker_name in _LAUGH_CACHE:
        return _LAUGH_CACHE[speaker_name]
    
    laugh_fp = resolve_laugh_file(speaker_name, voice_dir)
    if not laugh_fp or not os.path.isfile(laugh_fp):
        _LAUGH_CACHE[speaker_name] = None
        return None
        
    data, sr = sf.read(laugh_fp)
    if len(data.shape) > 1:
        data = data.mean(axis=1)
    if sr != target_sr:
        t = torch.from_numpy(data).unsqueeze(0).float()
        t = F.resample(t, orig_freq=sr, new_freq=target_sr)
        data = t.squeeze(0).numpy()
        sr = target_sr
        
    # Trim leading silence
    threshold = 0.015
    non_silent = np.where(np.abs(data) > threshold)[0]
    if len(non_silent) > 0:
        data = data[non_silent[0]:]
        
    max_samples = int(sr * max_duration)
    if len(data) > max_samples:
        data = data[:max_samples]
        
    # Apply soft 50ms fade-out
    fade_len = int(sr * 0.05)
    if len(data) > fade_len:
        fade = np.linspace(1.0, 0.0, fade_len)
        data[-fade_len:] *= fade
        
    result = data.astype(np.float32)
    _LAUGH_CACHE[speaker_name] = (result, sr)
    return result, sr


def has_laugh_indicator(text: str) -> bool:
    """Checks whether prompt contains a laugh emotion tag or laugh interjection."""
    return bool(re.search(r"\[(?:laughs?|laughing|chuckles?|giggles?)\]|\b(?:haha|hahaha|hah|hehe)\b", text, flags=re.IGNORECASE))


def sanitize_prompt(text: str, remove_laughs: bool = False) -> str:
    """Cleans punctuation and converts/removes emotion tags for natural TTS pacing."""
    cleaned = text
    if remove_laughs:
        cleaned = re.sub(r"\[(?:laughs?|laughing|chuckles?|giggles?)\]", "", cleaned, flags=re.IGNORECASE)
        cleaned = re.sub(r"\b(?:haha!?|hahaha!?|hah!?|hehe!?|heh!?)\b", "", cleaned, flags=re.IGNORECASE)
    else:
        cleaned = re.sub(r"\[(?:laughs?|laughing|chuckles?)\]", "", cleaned, flags=re.IGNORECASE)
        
    cleaned = re.sub(r"\[(?:sighs?|groans?)\]", "Oh, ", cleaned, flags=re.IGNORECASE)
    cleaned = re.sub(r"\[.*?\]", "", cleaned)
    cleaned = re.sub(r"\.{2,}", ",", cleaned)
    cleaned = re.sub(r"^\s*[\!\?\,\.\:\;]+\s*", "", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned


def match_loudness(source_audio: np.ndarray, target_audio: np.ndarray, gain_offset_db: float = -0.5) -> np.ndarray:
    """Scales source_audio so its active RMS power matches target_audio closely."""
    thresh = 0.01
    src_active = source_audio[np.abs(source_audio) > thresh]
    tgt_active = target_audio[np.abs(target_audio) > thresh]
    if len(src_active) == 0 or len(tgt_active) == 0:
        return source_audio
    src_rms = np.sqrt(np.mean(src_active**2))
    tgt_rms = np.sqrt(np.mean(tgt_active**2))
    if src_rms < 1e-5:
        return source_audio
    factor = (tgt_rms / src_rms) * (10 ** (gain_offset_db / 20.0))
    matched = source_audio * factor
    peak = np.abs(matched).max()
    if peak > 0.95:
        matched = matched * (0.95 / peak)
    return matched.astype(np.float32)


def blend_laugh_and_speech(laugh_audio: np.ndarray, speech_audio: np.ndarray, sr: int = 24000, overlap_sec: float = 0.05) -> np.ndarray:
    """Acoustically matches and smoothly crossfades authentic laugh sample into generated speech."""
    matched_laugh = match_loudness(laugh_audio, speech_audio, gain_offset_db=-0.5)
    overlap_samples = int(sr * overlap_sec)
    if len(matched_laugh) > overlap_samples and len(speech_audio) > overlap_samples:
        fade_out = np.linspace(1.0, 0.0, overlap_samples, dtype=np.float32)
        fade_in = np.linspace(0.0, 1.0, overlap_samples, dtype=np.float32)
        
        head = matched_laugh[:-overlap_samples]
        transition = matched_laugh[-overlap_samples:] * fade_out + speech_audio[:overlap_samples] * fade_in
        tail = speech_audio[overlap_samples:]
        return np.concatenate([head, transition, tail])
    else:
        return np.concatenate([matched_laugh, speech_audio])


def synthesize_segment(f5tts: F5TTS, speaker_assets: dict, speaker_name: str, voice_dir: str, text_prompt: str, speed_val: float, nfe_step_val: int):
    """Synthesizes a single audio segment using F5-TTS with acoustic laugh sample blending."""
    has_laugh = has_laugh_indicator(text_prompt)
    laugh_data = get_prepared_laugh(speaker_name, voice_dir) if has_laugh else None
    
    # Remove literal laugh words from spoken text if acoustic laugh sample is being prepended
    cleaned_prompt = sanitize_prompt(text_prompt, remove_laughs=(laugh_data is not None))
    if not cleaned_prompt:
        cleaned_prompt = "Yes, absolutely."

    wav, sr, _ = infer_process(
        ref_audio=speaker_assets["prep_wav"],
        ref_text=speaker_assets["ref_text"],
        gen_text=cleaned_prompt,
        model_obj=f5tts.ema_model,
        vocoder=f5tts.vocoder,
        mel_spec_type=f5tts.mel_spec_type,
        speed=speed_val,
        nfe_step=nfe_step_val,
    )
    
    if laugh_data is not None:
        laugh_audio, laugh_sr = laugh_data
        wav = blend_laugh_and_speech(laugh_audio, wav, sr=sr, overlap_sec=0.05)
        
    # If prompt ends with a cut-off dash, trim trailing silence immediately for an abrupt power-off effect
    if text_prompt.rstrip().endswith("--") or text_prompt.rstrip().endswith("-"):
        thresh = 0.02
        non_silent = np.where(np.abs(wav) > thresh)[0]
        if len(non_silent) > 0:
            last_idx = min(len(wav), non_silent[-1] + int(sr * 0.02))
            wav = wav[:last_idx]

    return wav, sr, cleaned_prompt


def main():
    parser = argparse.ArgumentParser(description="Generate golf commentary audio using F5-TTS with multi-speaker dialogue support.")
    parser.add_argument("--speaker", type=str, default=None, help="Override speaker voice (e.g. irish_accent2, english_female)")
    parser.add_argument("--category", type=str, default="good_shot_fairway", help="Category name, or 'all' for all categories")
    parser.add_argument("--index", type=int, default=None, help="Specific prompt index in category (default: random selection)")
    parser.add_argument("--all", action="store_true", help="Batch generate all prompts in selected category/categories")
    parser.add_argument("--speed", type=float, default=0.95, help="Speech speed multiplier (default: 0.95)")
    parser.add_argument("--pause", type=float, default=0.35, help="Pause duration in seconds between dialogue speakers (default: 0.35s)")
    parser.add_argument("--nfe-step", type=int, default=32, help="Diffusion sampling steps (default: 32)")
    parser.add_argument("--ref-text", type=str, default="", help="Optional manual reference text override")
    parser.add_argument("--prompt", type=str, default=None, help="Optional manual prompt override text")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    json_path = os.path.join(script_dir, "heckle_prompts.json")
    custom_voice_dir = os.path.join(script_dir, "custom_voices")
    project_root = os.path.abspath(os.path.join(script_dir, "..", "..", ".."))

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Determine tasks to process
    categories = list(data["categories"].keys())
    if args.category.lower() == "all":
        selected_cats = categories
    elif args.category in data["categories"]:
        selected_cats = [args.category]
    else:
        print(f"Unknown category '{args.category}'. Available: {categories}")
        sys.exit(1)

    tasks = []
    for cat in selected_cats:
        cat_items = data["categories"][cat]
        if args.all:
            for idx, item in enumerate(cat_items):
                tasks.append((cat, idx, item))
        elif args.index is not None:
            if 0 <= args.index < len(cat_items):
                tasks.append((cat, args.index, cat_items[args.index]))
            else:
                print(f"Index {args.index} out of range for category '{cat}' (0..{len(cat_items)-1})")
                sys.exit(1)
        else:
            rand_idx = random.randrange(len(cat_items))
            tasks.append((cat, rand_idx, cat_items[rand_idx]))
            break

    print(f"\nTotal generation tasks queued: {len(tasks)}")

    # Initialize F5-TTS model once
    print("Loading F5-TTS model (Flow Matching DiT)...")
    f5tts = F5TTS(device=device)

    for cat_name, item_idx, prompt_item in tasks:
        # 1. Resolve lead prompt and speaker
        main_name = prompt_item.get("name", "Announcer")
        main_audio = args.speaker if args.speaker else prompt_item.get("audio", "irish_accent2")
        main_prompt = args.prompt if args.prompt else prompt_item.get("prompt", "")
        output_rel = prompt_item.get("filepath", f"res://assets/audio/heckler/{cat_name}/{cat_name}_{item_idx}.wav")

        if output_rel.startswith("res://"):
            full_out_path = os.path.normpath(os.path.join(project_root, output_rel.replace("res://", "")))
        else:
            full_out_path = os.path.normpath(os.path.join(project_root, output_rel))
        os.makedirs(os.path.dirname(full_out_path), exist_ok=True)

        follow_up = prompt_item.get("follow_up", None)

        print("\n" + "="*70)
        print(f"Category: [{cat_name}] | Index: {item_idx} | Output: {output_rel}")
        print(f"Lead [{main_name} ({main_audio})]: \"{main_prompt}\"")
        if follow_up:
            fu_name = follow_up.get("name", "Follow-up")
            fu_audio = follow_up.get("audio", "english_female")
            fu_prompt = follow_up.get("prompt", "")
            print(f"Follow-up [{fu_name} ({fu_audio})]: \"{fu_prompt}\"")
        print("="*70)

        # Synthesize lead segment
        lead_assets = get_prepared_speaker_assets(main_audio, custom_voice_dir, args.ref_text if args.ref_text else "")
        wav1, sr1, clean_p1 = synthesize_segment(f5tts, lead_assets, main_audio, custom_voice_dir, main_prompt, args.speed, args.nfe_step)

        if follow_up:
            fu_assets = get_prepared_speaker_assets(fu_audio, custom_voice_dir)
            wav2, sr2, clean_p2 = synthesize_segment(f5tts, fu_assets, fu_audio, custom_voice_dir, fu_prompt, args.speed, args.nfe_step)

            # Insert pause between speakers
            pause_samples = int(sr1 * args.pause)
            silence = np.zeros(pause_samples, dtype=np.float32)
            final_wav = np.concatenate([wav1, silence, wav2])
            final_sr = sr1
        else:
            final_wav = wav1
            final_sr = sr1

        # Write final combined sound file
        sf.write(full_out_path, final_wav, final_sr)
        print(f"-> Successfully saved audio to: {full_out_path}")

    print("\nAll requested generations completed successfully!")


if __name__ == "__main__":
    main()
