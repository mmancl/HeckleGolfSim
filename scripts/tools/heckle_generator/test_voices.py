import os
import argparse
import numpy
import torch

# Fix PyTorch 2.6+ unpickling error for Bark checkpoints
try:
    if hasattr(numpy, "_core"):
        torch.serialization.add_safe_globals([numpy._core.multiarray.scalar])
    else:
        torch.serialization.add_safe_globals([numpy.core.multiarray.scalar])
except Exception:
    pass

_orig_torch_load = torch.load
def _patched_torch_load(*args, **kwargs):
    kwargs.setdefault('weights_only', False)
    return _orig_torch_load(*args, **kwargs)
torch.load = _patched_torch_load

# Enable CUDA GPU if available
if torch.cuda.is_available():
    print(f"Using GPU Acceleration: {torch.cuda.get_device_name(0)}")
else:
    print("CUDA not available. Running on CPU.")

from bark import SAMPLE_RATE, generate_audio, preload_models
import scipy.io.wavfile as wavfile

# Available English speakers in Bark:
AVAILABLE_SPEAKERS = [f"v2/en_speaker_{i}" for i in range(10)]

def main():
    parser = argparse.ArgumentParser(description="Test different Bark voice presets for golf heckles.")
    parser.add_argument("--speaker", type=str, default=None, help="Specific speaker preset to test (e.g. v2/en_speaker_6)")
    parser.add_argument("--prompt", type=str, default="Oh look, a beach trip! Too bad you forgot your sunscreen. [laughs]", help="Prompt text to generate")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.join(script_dir, "test_voices_output")
    os.makedirs(output_dir, exist_ok=True)

    preload_models()

    # Check custom_voices directory for user-cloned voices
    custom_voice_dir = os.path.join(script_dir, "custom_voices")
    custom_speakers = []
    if os.path.isdir(custom_voice_dir):
        custom_speakers = [os.path.join(custom_voice_dir, f) for f in os.listdir(custom_voice_dir) if f.endswith(".npz")]

    if args.speaker:
        target = args.speaker
        if not target.startswith("v2/"):
            for candidate in [target, f"{target}.npz", os.path.join(custom_voice_dir, target), os.path.join(custom_voice_dir, f"{target}.npz")]:
                if os.path.isfile(candidate):
                    target = os.path.abspath(candidate)
                    break
        speakers_to_test = [target]
    else:
        speakers_to_test = AVAILABLE_SPEAKERS + custom_speakers

    print(f"\n--- Testing Bark Voices ---")
    print(f"Prompt: {args.prompt}\n")

    for speaker in speakers_to_test:
        speaker_name = os.path.basename(speaker) if speaker.endswith(".npz") else speaker.replace("/", "_")
        filename = f"sample_{speaker_name}.wav"
        output_path = os.path.join(output_dir, filename)

        print(f"Generating audio for speaker: {speaker} -> {filename}")
        audio_array = generate_audio(args.prompt, history_prompt=speaker)
        wavfile.write(output_path, SAMPLE_RATE, audio_array)
        print(f"Saved: {output_path}")

    print(f"\nAll voice samples saved in: {output_dir}")

if __name__ == "__main__":
    main()
