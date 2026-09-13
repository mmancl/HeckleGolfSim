import os
import sys
import re
import argparse
import tempfile
import numpy as np
import torch
from torch import nn

# Fix PyTorch 2.6+ unpickling error for Bark checkpoints
try:
    if hasattr(np, "_core"):
        torch.serialization.add_safe_globals([np._core.multiarray.scalar])
    else:
        torch.serialization.add_safe_globals([np.core.multiarray.scalar])
except Exception:
    pass

_orig_torch_load = torch.load
def _patched_torch_load(*args, **kwargs):
    kwargs.setdefault("weights_only", False)
    return _orig_torch_load(*args, **kwargs)
torch.load = _patched_torch_load

# Determine execution device
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device} ({torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'CPU'})")

import torchaudio
from transformers import HubertModel
import huggingface_hub
from bark.generation import load_codec_model, SAMPLE_RATE
import scipy.io.wavfile as wavfile


def get_ffmpeg_path():
    """Finds an available ffmpeg executable path."""
    import shutil
    ffmpeg_system = shutil.which("ffmpeg")
    if ffmpeg_system:
        return ffmpeg_system
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return None


def parse_time_to_seconds(time_str):
    """
    Parses timestamps like '90', '1:30', or '01:30:15' into float seconds.
    """
    if time_str is None:
        return 0.0
    if isinstance(time_str, (int, float)):
        return float(time_str)
    
    parts = str(time_str).strip().split(":")
    try:
        if len(parts) == 1:
            return float(parts[0])
        elif len(parts) == 2:
            return float(parts[0]) * 60 + float(parts[1])
        elif len(parts) == 3:
            return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])
        else:
            raise ValueError(f"Invalid timestamp format: {time_str}")
    except ValueError as e:
        print(f"Warning: Could not parse time '{time_str}', defaulting to 0.0. Error: {e}")
        return 0.0


def sanitize_filename(name):
    """Cleans a string to be a safe filename."""
    name = re.sub(r'[\\/*?:"<>|]', "", name)
    name = re.sub(r"\s+", "_", name.strip())
    return name.lower()


class CustomTokenizer(nn.Module):
    """HuBERT feature quantizer to semantic tokens for Bark."""
    def __init__(self, hidden_size=1024, input_size=768, output_size=10000, version=0):
        super().__init__()
        self.lstm = nn.LSTM(input_size, hidden_size, 2, batch_first=True)
        self.fc = nn.Linear(hidden_size, output_size)
        self.softmax = nn.LogSoftmax(dim=1)
        self.version = version

    def forward(self, x):
        out, _ = self.lstm(x)
        out = self.fc(out)
        out = self.softmax(out)
        return out

    @torch.no_grad()
    def get_token(self, x):
        if x.ndim == 2:
            x = x.unsqueeze(0)
        logits = self.forward(x)
        return torch.argmax(logits.squeeze(0), dim=-1)


def download_youtube_audio(youtube_url, output_temp_dir):
    """
    Downloads the best audio stream from a YouTube URL using yt-dlp and converts directly to WAV.
    Avoids requiring external ffprobe on Windows.
    """
    try:
        import yt_dlp
    except ImportError:
        raise RuntimeError("yt-dlp is required. Please install it using: pip install yt-dlp")

    import subprocess
    ffmpeg_path = get_ffmpeg_path()
    out_tmpl = os.path.join(output_temp_dir, "%(title).50s-%(id)s.%(ext)s")

    ydl_opts = {
        "format": "bestaudio/best",
        "outtmpl": out_tmpl,
        "quiet": False,
        "no_warnings": False,
    }

    print(f"\n[1/5] Downloading audio from YouTube: {youtube_url}...")
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(youtube_url, download=True)
        title = info.get("title", "custom_voice")
        raw_downloaded = ydl.prepare_filename(info)

    # Convert to 24kHz mono WAV using ffmpeg binary directly (no ffprobe required)
    if ffmpeg_path and os.path.exists(raw_downloaded):
        base_name, _ = os.path.splitext(raw_downloaded)
        wav_path = base_name + ".wav"
        cmd = [
            ffmpeg_path,
            "-y",
            "-i", raw_downloaded,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", "24000",
            "-ac", "1",
            wav_path
        ]
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if os.path.exists(wav_path):
                return wav_path, title
        except Exception as e:
            print(f"Direct ffmpeg conversion notice: {e}")

    if os.path.exists(raw_downloaded):
        return raw_downloaded, title

    # Fallback search in temp dir
    files = [os.path.join(output_temp_dir, f) for f in os.listdir(output_temp_dir)]
    if files:
        return files[0], title
    raise FileNotFoundError("Could not find downloaded audio file from YouTube.")


def isolate_vocals_demucs(waveform, sr, target_sr=24000):
    """
    Uses Demucs deep neural network to isolate the vocal stem and remove background
    music, instruments, crowd cheering, and ambient noise.
    """
    print(" - Isolating speech/vocals with Demucs neural separator (removing music & crowds)...")
    try:
        bundle = torchaudio.pipelines.HDEMUCS_HIGH_MUSDB_PLUS
        demucs_model = bundle.get_model().to(device)
        demucs_model.eval()

        # Demucs expects stereo audio at 44100 Hz
        if waveform.shape[0] == 1:
            stereo_wav = waveform.repeat(2, 1)
        else:
            stereo_wav = waveform[:2, :]

        wav_44k = torchaudio.functional.resample(stereo_wav, orig_freq=sr, new_freq=bundle.sample_rate).to(device)

        with torch.no_grad():
            # Output shape: (1, 4, 2, time) -> [drums, bass, other, vocals]
            sources = demucs_model(wav_44k.unsqueeze(0))

        # Source index 3 is vocals
        vocals_stereo = sources[0, 3]  # (2, time)
        vocals_mono = torch.mean(vocals_stereo, dim=0, keepdim=True).cpu()  # (1, time)

        # Resample to target_sr
        vocals_resampled = torchaudio.functional.resample(vocals_mono, orig_freq=bundle.sample_rate, new_freq=target_sr)
        return vocals_resampled
    except Exception as e:
        print(f"Warning: Neural vocal separation failed ({e}). Continuing with raw audio.")
        if sr != target_sr:
            waveform = torchaudio.functional.resample(waveform, orig_freq=sr, new_freq=target_sr)
        if waveform.shape[0] > 1:
            waveform = torch.mean(waveform, dim=0, keepdim=True)
        return waveform.cpu()


def apply_noise_reduction(waveform, sr, prop_decrease=0.75):
    """
    Applies spectral gating noise reduction to eliminate background hiss and room noise.
    """
    print(f" - Applying spectral noise reduction (strength: {prop_decrease})...")
    try:
        import noisereduce as nr
        audio_np = waveform.squeeze(0).numpy()
        denoised = nr.reduce_noise(
            y=audio_np,
            sr=sr,
            stationary=True,
            prop_decrease=prop_decrease,
            n_fft=1024,
            win_length=1024,
            hop_length=512
        )
        return torch.from_numpy(denoised).unsqueeze(0).float()
    except Exception as e:
        print(f"Warning: Noise reduction failed ({e}). Proceeding without noise reduction.")
        return waveform


def process_audio_segment(audio_path, start_sec=0.0, duration_sec=10.0, isolate_vocals=True, denoise=True, denoise_strength=0.75, target_sr=24000):
    """
    Loads audio, trims to [start_sec, start_sec + duration_sec], isolates vocals,
    denoises, normalizes volume, and resamples to target_sr.
    """
    print(f"\n[2/5] Trimming audio segment (Start: {start_sec:.1f}s, Duration: {duration_sec:.1f}s)...")
    waveform, sr = torchaudio.load(audio_path)

    total_samples = waveform.shape[-1]
    total_seconds = total_samples / sr

    start_sample = int(start_sec * sr)
    if start_sample >= total_samples:
        print(f"Warning: Start time ({start_sec}s) exceeds audio duration ({total_seconds:.1f}s). Resetting to 0s.")
        start_sample = 0

    end_sample = int((start_sec + duration_sec) * sr)
    if end_sample > total_samples:
        print(f"Warning: Requested segment exceeds audio length. Truncating to available audio ({total_seconds:.1f}s).")
        end_sample = total_samples

    segment = waveform[:, start_sample:end_sample]

    # Step 1: Vocal isolation via Demucs (Removes background music, applause, and crowd noise)
    if isolate_vocals:
        print(f"\n[3/5] Cleaning & Isolating Vocal Track:")
        segment = isolate_vocals_demucs(segment, sr, target_sr=target_sr)
        sr = target_sr
    else:
        # Fallback basic conversion
        if segment.shape[0] > 1:
            segment = torch.mean(segment, dim=0, keepdim=True)
        if sr != target_sr:
            segment = torchaudio.functional.resample(segment, orig_freq=sr, new_freq=target_sr)
            sr = target_sr

    # Step 2: Denoise via spectral gating
    if denoise:
        segment = apply_noise_reduction(segment, sr, prop_decrease=denoise_strength)

    # Step 3: Highpass filter (80 Hz) to eliminate sub-bass rumble and mic handling noise
    try:
        segment = torchaudio.functional.highpass_biquad(segment, sr, cutoff_freq=80.0)
    except Exception:
        pass

    # Step 4: Peak Normalization
    max_val = torch.max(torch.abs(segment))
    if max_val > 0:
        segment = segment / max_val * 0.95

    actual_duration = segment.shape[-1] / sr
    print(f"Cleaned isolated vocal segment: {actual_duration:.2f} seconds at {sr} Hz.")
    return segment, sr


def create_bark_voice_prompt(waveform_24k, output_npz_path):
    """
    Generates Bark semantic, coarse, and fine tokens and saves to .npz voice prompt.
    """
    print("\n[4/5] Extracting HuBERT semantic & EnCodec audio tokens for Bark...")
    
    # 1. Load HuBERT model
    print(" - Loading HuBERT model (facebook/hubert-base-ls960)...")
    hubert = HubertModel.from_pretrained("facebook/hubert-base-ls960").to(device)
    hubert.eval()

    # 2. Load GitMylo Tokenizer
    print(" - Loading Bark semantic tokenizer checkpoint...")
    tokenizer_model_file = huggingface_hub.hf_hub_download(
        "GitMylo/bark-voice-cloning",
        "quantifier_hubert_base_ls960_14.pth"
    )
    tokenizer = CustomTokenizer().to(device)
    tokenizer.load_state_dict(torch.load(tokenizer_model_file, map_location=device, weights_only=False))
    tokenizer.eval()

    # Resample to 16kHz for HuBERT
    wav_16k = torchaudio.functional.resample(waveform_24k, orig_freq=24000, new_freq=16000).to(device)

    with torch.no_grad():
        outputs = hubert(wav_16k, output_hidden_states=True)
        # Layer 9 hidden state features
        layer9 = outputs.hidden_states[9]
        semantic_tokens = tokenizer.get_token(layer9).cpu().numpy()

    # 3. Load Codec model (EnCodec 24kHz)
    print(" - Loading EnCodec 24kHz neural audio codec...")
    use_gpu_for_codec = (device.type == "cuda")
    codec_model = load_codec_model(use_gpu=use_gpu_for_codec)

    wav_for_codec = waveform_24k.to(device if use_gpu_for_codec else "cpu")
    with torch.no_grad():
        encoded_frames = codec_model.encode(wav_for_codec.unsqueeze(0))
    codes = torch.cat([encoded[0] for encoded in encoded_frames], dim=-1).squeeze().cpu().numpy()

    coarse_prompt = codes[:2, :]
    fine_prompt = codes

    print(f"Token shapes - Semantic: {semantic_tokens.shape}, Coarse: {coarse_prompt.shape}, Fine: {fine_prompt.shape}")

    # Ensure output directory exists
    os.makedirs(os.path.dirname(os.path.abspath(output_npz_path)), exist_ok=True)

    np.savez(
        output_npz_path,
        semantic_prompt=semantic_tokens.astype(np.int64),
        coarse_prompt=coarse_prompt.astype(np.int64),
        fine_prompt=fine_prompt.astype(np.int32)
    )
    print(f"\n[5/5] Successfully created Bark custom voice preset:")
    print(f" -> {os.path.abspath(output_npz_path)}")
    return output_npz_path


def transcribe_reference_audio(audio_tensor, sr=24000):
    """Transcribes reference audio slice using Whisper for F5-TTS alignment."""
    print("\n - Transcribing reference audio with Whisper for F5-TTS...")
    try:
        from transformers import WhisperProcessor, WhisperForConditionalGeneration
        processor = WhisperProcessor.from_pretrained("openai/whisper-tiny")
        model = WhisperForConditionalGeneration.from_pretrained("openai/whisper-tiny").to(device)
        
        audio_mono = audio_tensor.squeeze(0).cpu()
        if sr != 16000:
            audio_16k = torchaudio.functional.resample(audio_mono, orig_freq=sr, new_freq=16000).numpy()
        else:
            audio_16k = audio_mono.numpy()
            
        input_features = processor(audio_16k, sampling_rate=16000, return_tensors="pt").input_features.to(device)
        predicted_ids = model.generate(input_features, language="en")
        transcript = processor.batch_decode(predicted_ids, skip_special_tokens=True)[0].strip()
        return transcript
    except Exception as e:
        print(f"Warning: Whisper transcription notice: {e}")
        return ""


def main():
    parser = argparse.ArgumentParser(
        description="Extract audio from YouTube, isolate vocals, and create custom voice assets for Bark (.npz) and F5-TTS (.wav + .txt)."
    )
    parser.add_argument("url", type=str, help="YouTube video URL or ID (e.g. 'https://www.youtube.com/watch?v=...')")
    parser.add_argument("--name", "-n", type=str, default=None, help="Custom voice name (default: derived from video title)")
    parser.add_argument("--start", "-s", type=str, default="0", help="Start offset in seconds or MM:SS format (default: 0)")
    parser.add_argument("--duration", "-d", type=float, default=7.0, help="Duration in seconds (default: 7.0s, optimal for F5-TTS & Bark)")
    parser.add_argument("--transcript", type=str, default=None, help="Optional exact manual transcript for the reference audio slice")
    parser.add_argument("--output-dir", "-o", type=str, default=None, help="Directory to save custom voice files (default: custom_voices/)")
    
    # Audio separation & cleanup options
    parser.add_argument("--no-isolate-vocals", action="store_true", help="Disable Demucs neural vocal isolation (enabled by default)")
    parser.add_argument("--no-denoise", action="store_true", help="Disable spectral background noise reduction (enabled by default)")
    parser.add_argument("--denoise-strength", type=float, default=0.75, help="Noise reduction strength from 0.0 to 1.0 (default: 0.75)")
    
    parser.add_argument("--keep-reference-audio", "-k", action="store_true", default=True, help="Save the cleaned reference .wav file (default: True)")
    parser.add_argument("--test", "-t", action="store_true", help="Immediately test the generated voice by synthesizing a sample heckle")
    parser.add_argument("--test-prompt", type=str, default="That shot belongs in the water hazard! [laughs]", help="Prompt text to synthesize during --test")

    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = args.output_dir if args.output_dir else os.path.join(script_dir, "custom_voices")
    os.makedirs(output_dir, exist_ok=True)

    start_sec = parse_time_to_seconds(args.start)
    duration_sec = float(args.duration)

    with tempfile.TemporaryDirectory() as temp_dir:
        downloaded_path, title = download_youtube_audio(args.url, temp_dir)

        voice_name = args.name if args.name else sanitize_filename(title)
        if voice_name.endswith(".npz"):
            voice_name = voice_name[:-4]

        output_npz_path = os.path.join(output_dir, f"{voice_name}.npz")
        ref_wav_path = os.path.join(output_dir, f"{voice_name}_reference_cleaned.wav")
        ref_txt_path = os.path.join(output_dir, f"{voice_name}_reference_cleaned.txt")

        # Process, isolate vocals, denoise and normalize
        waveform_24k, sr = process_audio_segment(
            downloaded_path,
            start_sec=start_sec,
            duration_sec=duration_sec,
            isolate_vocals=(not args.no_isolate_vocals),
            denoise=(not args.no_denoise),
            denoise_strength=args.denoise_strength,
            target_sr=24000
        )

        # 1. Save cleaned reference WAV for F5-TTS
        wavfile.write(ref_wav_path, sr, waveform_24k.squeeze(0).cpu().numpy())
        print(f"Saved cleaned vocal reference audio to: {ref_wav_path}")

        # 2. Extract transcript using Whisper or user argument
        if args.transcript:
            transcript = args.transcript.strip()
        else:
            transcript = transcribe_reference_audio(waveform_24k, sr=sr)
        
        if transcript:
            with open(ref_txt_path, "w", encoding="utf-8") as f:
                f.write(transcript)
            print(f"Saved reference transcript to: {ref_txt_path}")
            print(f"Transcript: \"{transcript}\"")

        # 3. Create Bark custom voice prompt (.npz)
        created_path = create_bark_voice_prompt(waveform_24k, output_npz_path)

        print("\n" + "=" * 60)
        print(f" Custom Voice '{voice_name}' is Ready for Both F5-TTS & Bark!")
        print("=" * 60)
        print(f" F5-TTS WAV:        {ref_wav_path}")
        print(f" F5-TTS Transcript: {ref_txt_path}")
        print(f" Bark NPZ File:     {output_npz_path}")
        print("\nHow to generate with F5-TTS (Recommended - MIT):")
        print(f"  python generate_f5.py --speaker \"{voice_name}\"")
        print("\nHow to generate with Bark:")
        print(f"  python generate.py --speaker \"{voice_name}\"")
        print("=" * 60)

        # Test generation if requested
        if args.test:
            print("\nGenerating test sample with F5-TTS...")
            try:
                from f5_tts.api import F5TTS
                from f5_tts.infer.utils_infer import infer_process
                import soundfile as sf
                device_str = "cuda" if torch.cuda.is_available() else "cpu"
                f5tts = F5TTS(device=device_str)
                test_wav, test_sr, _ = infer_process(
                    ref_audio=ref_wav_path,
                    ref_text=transcript or " ",
                    gen_text=args.test_prompt,
                    model_obj=f5tts.ema_model,
                    vocoder=f5tts.vocoder,
                    mel_spec_type=f5tts.mel_spec_type,
                    speed=0.95,
                    nfe_step=32,
                )
                test_out_path = os.path.join(output_dir, f"{voice_name}_test_sample.wav")
                sf.write(test_out_path, test_wav, test_sr)
                print(f"Test sample successfully saved to: {test_out_path}")
            except Exception as e:
                print(f"Notice: Test generation skipped ({e})")


if __name__ == "__main__":
    main()
