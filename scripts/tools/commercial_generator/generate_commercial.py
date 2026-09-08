#!/usr/bin/env python3
"""
Heckle Golf Simulator - AI Commercial Video Generator
Calls Google Veo (via Google GenAI SDK or Gemini REST API) using game screenshots
to generate cinematic video clips, then stitches them into a final promotional commercial.
"""

import os
import sys
import json
import time
import shutil
import argparse
import subprocess
from pathlib import Path

# Optional / installed libraries
try:
    from PIL import Image
except ImportError:
    Image = None

try:
    import cv2
except ImportError:
    cv2 = None

# Default paths
DEFAULT_INPUT_DIR = r"C:\Users\micha\Downloads\golf_sim_commercial"
REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
DEFAULT_OUTPUT_DIR = str(REPO_ROOT / "output" / "commercial")
DEFAULT_CONFIG_PATH = str(Path(__file__).resolve().parent / "storyboard_config.json")
FALLBACK_IMAGE_DIR = str(REPO_ROOT / "assets" / "images")


def log_info(msg: str):
    print(f"[INFO] {msg}")


def log_warn(msg: str):
    print(f"[WARN] {msg}")


def log_err(msg: str):
    print(f"[ERROR] {msg}", file=sys.stderr)


def log_success(msg: str):
    print(f"[SUCCESS] {msg}")


def load_storyboard(config_path: str) -> dict:
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def find_image_for_scene(scene: dict, input_dir: str) -> str | None:
    candidates = []
    if "image" in scene:
        candidates.append(os.path.join(input_dir, scene["image"]))
    if "fallback_image" in scene:
        candidates.append(os.path.join(input_dir, scene["fallback_image"]))

    # Common repo fallback paths
    candidates.append(os.path.join(FALLBACK_IMAGE_DIR, scene.get("image", "")))
    candidates.append(str(REPO_ROOT / scene.get("image", "")))
    candidates.append(str(REPO_ROOT / scene.get("fallback_image", "")))

    for path in candidates:
        if path and os.path.isfile(path) and os.path.getsize(path) > 0:
            return path
    return None


def get_image_dimensions(image_path: str) -> tuple[int, int]:
    if Image:
        with Image.open(image_path) as img:
            return img.size
    elif cv2:
        mat = cv2.imread(image_path)
        if mat is not None:
            return mat.shape[1], mat.shape[0]
    return 1920, 1080


def generate_clip_with_sdk(
    client,
    model_name: str,
    image_path: str,
    prompt: str,
    output_path: str,
    aspect_ratio: str = "16:9",
    duration_seconds: int = 5,
    poll_interval: int = 15,
    max_poll_time: int = 600,
) -> bool:
    from google.genai import types

    log_info(f"Uploading reference image: {os.path.basename(image_path)}...")
    uploaded_file = client.files.upload(file=image_path)
    log_info(f"Uploaded file URI: {getattr(uploaded_file, 'uri', 'uploaded')}")

    log_info(f"Submitting video generation to {model_name}...")
    config = types.GenerateVideosConfig(
        aspect_ratio=aspect_ratio,
        reference_images=[uploaded_file] if hasattr(types, "GenerateVideosConfig") else None,
    )

    operation = client.models.generate_videos(
        model=model_name,
        prompt=prompt,
        image=uploaded_file,
        config=config,
    )

    op_name = getattr(operation, "name", "operation")
    log_info(f"Operation initiated: {op_name}")
    elapsed = 0
    while not operation.done:
        time.sleep(poll_interval)
        elapsed += poll_interval
        log_info(f"Waiting for completion... ({elapsed}s elapsed)")
        if elapsed > max_poll_time:
            log_err(f"Timed out after {max_poll_time}s waiting for {model_name}")
            return False
        operation = client.operations.get(operation)

    if hasattr(operation, "error") and operation.error:
        log_err(f"Veo generation failed: {operation.error}")
        return False

    if hasattr(operation, "response") and operation.response:
        generated_videos = getattr(operation.response, "generated_videos", [])
        if generated_videos:
            video = generated_videos[0].video
            log_info(f"Downloading generated video to {output_path}...")
            client.files.download(file=video, output_path=output_path)
            log_success(f"Saved clip: {output_path}")
            return True

    log_err("Operation completed without generated_videos in response.")
    return False


def generate_clip_with_rest(
    api_key: str,
    model_name: str,
    image_path: str,
    prompt: str,
    output_path: str,
    aspect_ratio: str = "16:9",
    poll_interval: int = 15,
    max_poll_time: int = 600,
) -> bool:
    import base64
    import urllib.request
    import urllib.error

    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:predictLongRunning?key={api_key}"

    with open(image_path, "rb") as f:
        img_b64 = base64.b64encode(f.read()).decode("utf-8")

    mime_type = "image/png" if image_path.lower().endswith(".png") else "image/jpeg"

    payload = {
        "instances": [
            {
                "prompt": prompt,
                "image": {
                    "bytesBase64Encoded": img_b64,
                    "mimeType": mime_type
                }
            }
        ],
        "parameters": {
            "aspectRatio": aspect_ratio,
            "sampleCount": 1
        }
    }

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    try:
        log_info(f"Submitting REST request to {url.split('?')[0]}...")
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            op_name = data.get("name")
            if not op_name:
                log_err(f"No operation name returned in REST response: {data}")
                return False
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8") if hasattr(e, "read") else ""
        log_err(f"REST API call failed ({e.code}): {e.reason} - {body}")
        return False

    log_info(f"REST Operation created: {op_name}. Polling status...")
    poll_url = f"https://generativelanguage.googleapis.com/v1beta/{op_name}?key={api_key}"
    elapsed = 0
    while elapsed < max_poll_time:
        time.sleep(poll_interval)
        elapsed += poll_interval
        log_info(f"Polling {op_name} ({elapsed}s elapsed)...")
        try:
            poll_req = urllib.request.Request(poll_url)
            with urllib.request.urlopen(poll_req) as p_resp:
                poll_data = json.loads(p_resp.read().decode("utf-8"))
                if poll_data.get("done"):
                    if "error" in poll_data:
                        log_err(f"Operation error: {poll_data['error']}")
                        return False

                    response_obj = poll_data.get("response", {})
                    # Look for video data or download link
                    videos = response_obj.get("generateVideoResponse", {}).get("generatedSamples", [])
                    if not videos:
                        videos = response_obj.get("generatedVideos", [])

                    if videos:
                        video_entry = videos[0]
                        video_uri = video_entry.get("video", {}).get("uri") or video_entry.get("videoUri")
                        if video_uri:
                            log_info(f"Downloading video from {video_uri}...")
                            urllib.request.urlretrieve(f"{video_uri}?key={api_key}", output_path)
                            log_success(f"Saved clip: {output_path}")
                            return True
                        video_bytes = video_entry.get("video", {}).get("bytesBase64Encoded")
                        if video_bytes:
                            with open(output_path, "wb") as vf:
                                vf.write(base64.b64decode(video_bytes))
                            log_success(f"Saved clip: {output_path}")
                            return True

                    log_err(f"Operation done but no video found in response: {poll_data}")
                    return False
        except urllib.error.HTTPError as pe:
            log_warn(f"Poll query encountered HTTP {pe.code}, retrying...")

    log_err(f"Polling timed out after {max_poll_time}s")
    return False


def stitch_clips_ffmpeg(clip_paths: list[str], output_path: str, audio_path: str | None = None) -> bool:
    ffmpeg_bin = shutil.which("ffmpeg")
    if not ffmpeg_bin:
        # Check imageio_ffmpeg
        try:
            import imageio_ffmpeg
            ffmpeg_bin = imageio_ffmpeg.get_ffmpeg_exe()
        except ImportError:
            ffmpeg_bin = None

    if not ffmpeg_bin:
        return False

    log_info(f"Stitching clips using ffmpeg ({ffmpeg_bin})...")
    concat_txt = os.path.join(os.path.dirname(output_path), "concat_list.txt")
    with open(concat_txt, "w", encoding="utf-8") as f:
        for p in clip_paths:
            escaped_p = p.replace("\\", "/").replace("'", "'\\''")
            f.write(f"file '{escaped_p}'\n")

    cmd = [
        ffmpeg_bin,
        "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", concat_txt,
    ]

    if audio_path and os.path.isfile(audio_path):
        cmd.extend([
            "-i", audio_path,
            "-c:v", "libx264",
            "-c:a", "aac",
            "-shortest",
        ])
    else:
        cmd.extend([
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
        ])

    cmd.append(output_path)

    log_info(f"Running command: {' '.join(cmd)}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        log_warn(f"ffmpeg concat failed: {res.stderr}\nAttempting re-encode concat...")
        inputs = []
        filter_parts = []
        for i, p in enumerate(clip_paths):
            inputs.extend(["-i", p])
            filter_parts.append(f"[{i}:v:0]")
        filter_str = f"{''.join(filter_parts)}concat=n={len(clip_paths)}:v=1:a=0[outv]"
        reencode_cmd = [ffmpeg_bin, "-y"] + inputs + [
            "-filter_complex", filter_str,
            "-map", "[outv]",
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            output_path
        ]
        res2 = subprocess.run(reencode_cmd, capture_output=True, text=True)
        if res2.returncode != 0:
            log_err(f"ffmpeg re-encode also failed: {res2.stderr}")
            return False

    return os.path.isfile(output_path) and os.path.getsize(output_path) > 0


def stitch_clips_opencv(
    clip_paths: list[str],
    output_path: str,
    target_width: int = 1920,
    target_height: int = 1080,
    target_fps: float = 30.0,
) -> bool:
    if not cv2:
        log_err("OpenCV (cv2) is not installed; cannot stitch with OpenCV.")
        return False

    log_info(f"Stitching {len(clip_paths)} clips using OpenCV (resolution: {target_width}x{target_height} @ {target_fps}fps)...")

    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, target_fps, (target_width, target_height))
    if not out.isOpened():
        fourcc = cv2.VideoWriter_fourcc(*'avc1')
        out = cv2.VideoWriter(output_path, fourcc, target_fps, (target_width, target_height))

    if not out.isOpened():
        log_err("Failed to open OpenCV VideoWriter.")
        return False

    total_frames = 0
    for idx, cp in enumerate(clip_paths, 1):
        log_info(f"Processing clip {idx}/{len(clip_paths)}: {os.path.basename(cp)}...")
        cap = cv2.VideoCapture(cp)
        if not cap.isOpened():
            log_warn(f"Could not open video clip: {cp}, skipping.")
            continue

        clip_frames = 0
        while True:
            ret, frame = cap.read()
            if not ret or frame is None:
                break

            h, w = frame.shape[:2]
            if w != target_width or h != target_height:
                frame = cv2.resize(frame, (target_width, target_height), interpolation=cv2.INTER_LANCZOS4)
            out.write(frame)
            clip_frames += 1
            total_frames += 1
        cap.release()
        log_info(f"  Wrote {clip_frames} frames.")

    out.release()
    log_success(f"Successfully wrote {total_frames} frames to {output_path}")
    return os.path.isfile(output_path) and os.path.getsize(output_path) > 0


def stitch_clips(
    clip_paths: list[str],
    output_path: str,
    audio_path: str | None = None,
    target_width: int = 1920,
    target_height: int = 1080,
    target_fps: float = 30.0,
) -> bool:
    if not clip_paths:
        log_err("No clips provided to stitch.")
        return False

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    # 1. Try ffmpeg / imageio_ffmpeg
    if stitch_clips_ffmpeg(clip_paths, output_path, audio_path):
        log_success(f"Final commercial assembled with ffmpeg: {output_path}")
        return True

    log_warn("ffmpeg not found or failed; falling back to built-in OpenCV stitcher...")

    # 2. Try OpenCV
    if stitch_clips_opencv(clip_paths, output_path, target_width, target_height, target_fps):
        log_success(f"Final commercial assembled with OpenCV: {output_path}")
        return True

    log_err("All video stitching methods failed.")
    return False


def main():
    parser = argparse.ArgumentParser(description="Generate a commercial video for Heckle Golf Simulator using Google Veo")
    parser.add_argument("--input-dir", default=DEFAULT_INPUT_DIR, help=f"Folder with screenshots (default: {DEFAULT_INPUT_DIR})")
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR, help=f"Output folder (default: {DEFAULT_OUTPUT_DIR})")
    parser.add_argument("--config", default=DEFAULT_CONFIG_PATH, help=f"Storyboard JSON config (default: {DEFAULT_CONFIG_PATH})")
    parser.add_argument("--model", default="", help="Google Veo model to use (default from config: veo-3.1-generate-preview)")
    parser.add_argument("--api-key", default="", help="Gemini API key (or set GEMINI_API_KEY environment variable)")
    parser.add_argument("--dry-run", action="store_true", help="Validate images, print storyboard prompts & timings without calling API")
    parser.add_argument("--skip-generate", action="store_true", help="Skip API generation and stitch existing clips in output folder")
    parser.add_argument("--force", action="store_true", help="Force re-generation of clips even if cached in output folder")
    parser.add_argument("--audio", default="", help="Optional audio soundtrack (.mp3/.wav) to mix into final video")
    parser.add_argument("--poll-interval", type=int, default=15, help="Seconds between operation status checks (default: 15)")
    parser.add_argument("--max-poll-time", type=int, default=600, help="Maximum seconds to wait per clip before timing out (default: 600)")
    parser.add_argument("--resolution", default="1920x1080", help="Output video resolution WxH (default: 1920x1080)")
    parser.add_argument("--fps", type=float, default=30.0, help="Output video frame rate (default: 30.0)")
    args = parser.parse_args()

    print("=" * 75)
    print("       HECKLE GOLF SIMULATOR - COMMERCIAL VIDEO GENERATOR")
    print("=" * 75)

    if not os.path.isfile(args.config):
        log_err(f"Storyboard config file not found: {args.config}")
        sys.exit(1)

    storyboard = load_storyboard(args.config)
    scenes = [s for s in storyboard.get("scenes", []) if s.get("enabled", True)]
    model_name = args.model or storyboard.get("default_model", "veo-3.1-generate-preview")
    aspect_ratio = storyboard.get("aspect_ratio", "16:9")

    try:
        rw, rh = map(int, args.resolution.split("x"))
    except ValueError:
        rw, rh = 1920, 1080

    output_dir = Path(args.output_dir)
    clips_dir = output_dir / "clips"
    clips_dir.mkdir(parents=True, exist_ok=True)
    final_output_path = str(output_dir / "heckle_golf_sim_commercial.mp4")

    # Verify input images
    log_info(f"Input directory: {args.input_dir}")
    log_info(f"Loaded {len(scenes)} enabled scenes from {os.path.basename(args.config)}")

    valid_scenes = []
    missing_scenes = []

    for idx, scene in enumerate(scenes, 1):
        img_path = find_image_for_scene(scene, args.input_dir)
        if img_path:
            dim_w, dim_h = get_image_dimensions(img_path)
            valid_scenes.append((scene, img_path, (dim_w, dim_h)))
        else:
            missing_scenes.append(scene)

    if missing_scenes:
        log_warn(f"{len(missing_scenes)} scene image(s) could not be located:")
        for ms in missing_scenes:
            log_warn(f"  - Scene: '{ms.get('id')}' (Expected: {ms.get('image')})")

    total_duration = sum(s.get("duration_seconds", 5) for s, _, _ in valid_scenes)

    print("-" * 75)
    print(f"Commercial Title     : {storyboard.get('title', 'Heckle Golf Simulator')}")
    print(f"Veo Model Target     : {model_name}")
    print(f"Total Scenes Ready   : {len(valid_scenes)}/{len(scenes)}")
    print(f"Estimated Duration   : ~{total_duration} seconds ({total_duration / 60:.1f} minutes)")
    print(f"Output Resolution    : {rw}x{rh} @ {args.fps} fps")
    print(f"Final Video Path     : {final_output_path}")
    print("-" * 75)

    for i, (scene, img_path, dims) in enumerate(valid_scenes, 1):
        print(f"\n[Scene {i:02d}] {scene.get('title')} ({scene.get('id')})")
        print(f"  Asset   : {img_path} [{dims[0]}x{dims[1]}]")
        print(f"  Duration: {scene.get('duration_seconds', 5)}s | Aspect: {aspect_ratio}")
        print(f"  Prompt  : \"{scene.get('prompt')}\"")

    print("-" * 75)

    if args.dry_run:
        log_success("Dry-run completed successfully! All scenes, prompts, and image assets validated.")
        log_info("To start generation, run without --dry-run.")
        return

    # If skipping generation, just stitch existing clips
    if args.skip_generate:
        log_info("--skip-generate specified. Gathering cached clips for stitching...")
        existing_clips = []
        for scene, _, _ in valid_scenes:
            clip_file = str(clips_dir / f"{scene['id']}.mp4")
            if os.path.isfile(clip_file) and os.path.getsize(clip_file) > 0:
                existing_clips.append(clip_file)
            else:
                log_warn(f"Clip missing for scene: {scene['id']}")

        if not existing_clips:
            log_err(f"No existing clips found in {clips_dir} to stitch.")
            sys.exit(1)

        stitch_clips(
            clip_paths=existing_clips,
            output_path=final_output_path,
            audio_path=args.audio if args.audio else None,
            target_width=rw,
            target_height=rh,
            target_fps=args.fps,
        )
        return

    # Check API Key
    api_key = args.api_key or os.environ.get("GEMINI_API_KEY", "").strip()
    if not api_key:
        log_err("No Gemini API key found! Please set the GEMINI_API_KEY environment variable or pass --api-key.")
        log_info("Example: $env:GEMINI_API_KEY='AIzaSy...' (PowerShell) or set GEMINI_API_KEY=AIzaSy... (CMD)")
        sys.exit(1)

    # Initialize Client (prefer google.genai SDK)
    genai_client = None
    try:
        from google import genai
        genai_client = genai.Client(api_key=api_key)
        log_success("Initialized official Google GenAI SDK client.")
    except ImportError:
        log_warn("google-genai package not installed; falling back to direct Gemini REST API.")
    except Exception as e:
        log_warn(f"Failed to initialize google-genai client ({e}); falling back to REST API.")

    # Generate each scene
    generated_clip_paths = []

    for i, (scene, img_path, _) in enumerate(valid_scenes, 1):
        scene_id = scene["id"]
        clip_path = str(clips_dir / f"{scene_id}.mp4")

        if os.path.isfile(clip_path) and os.path.getsize(clip_path) > 0 and not args.force:
            log_info(f"[CACHED] Scene {i}/{len(valid_scenes)} ({scene_id}) already exists. Skipping API call.")
            generated_clip_paths.append(clip_path)
            continue

        log_info(f"\n>>> Generating Scene {i}/{len(valid_scenes)}: {scene.get('title')} ({scene_id})...")
        prompt_text = scene.get("prompt", "")
        duration = scene.get("duration_seconds", 5)

        success = False
        if genai_client:
            try:
                success = generate_clip_with_sdk(
                    client=genai_client,
                    model_name=model_name,
                    image_path=img_path,
                    prompt=prompt_text,
                    output_path=clip_path,
                    aspect_ratio=aspect_ratio,
                    duration_seconds=duration,
                    poll_interval=args.poll_interval,
                    max_poll_time=args.max_poll_time,
                )
            except Exception as ex:
                log_warn(f"SDK generation encountered exception: {ex}. Retrying via REST...")

        if not success:
            log_info("Attempting REST API video generation...")
            success = generate_clip_with_rest(
                api_key=api_key,
                model_name=model_name,
                image_path=img_path,
                prompt=prompt_text,
                output_path=clip_path,
                aspect_ratio=aspect_ratio,
                poll_interval=args.poll_interval,
                max_poll_time=args.max_poll_time,
            )

        if success and os.path.isfile(clip_path) and os.path.getsize(clip_path) > 0:
            generated_clip_paths.append(clip_path)
            log_success(f"Scene {i} generation complete!")
        else:
            log_err(f"Failed to generate clip for scene {scene_id}!")

    if not generated_clip_paths:
        log_err("No clips were successfully generated or found in cache. Exiting.")
        sys.exit(1)

    log_info(f"\nAll scene generations processed ({len(generated_clip_paths)} clips ready). Assembling commercial...")
    stitch_success = stitch_clips(
        clip_paths=generated_clip_paths,
        output_path=final_output_path,
        audio_path=args.audio if args.audio else None,
        target_width=rw,
        target_height=rh,
        target_fps=args.fps,
    )

    if stitch_success:
        print("\n" + "=" * 75)
        log_success("COMMERCIAL GENERATION COMPLETE!")
        print(f"Final Video: {final_output_path}")
        print(f"File Size  : {os.path.getsize(final_output_path) / (1024 * 1024):.2f} MB")
        print("=" * 75)
    else:
        log_err("Failed to stitch clips into final video.")


if __name__ == "__main__":
    main()
