#!/usr/bin/env python3
"""Procedural generator for High-graphics terrain & tree textures.

Everything is generated from scratch (no third-party imagery), so it is fully
compatible with the project's GPLv2 licensing. Output is written to
Courses/Environments/high/ as seamless (tileable) 2048x2048 PNGs plus matching
Godot .import files (mipmaps on, normal maps flagged, VRAM compression).

Usage:  python scripts/tools/generate_high_res_textures.py [--only fairway,green,rough,bark,leaf]
Requires: numpy, Pillow
"""
import argparse
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT_SIZE = 2048
SS = 2  # supersampling factor for blade/leaf rasterisation
CANVAS = OUT_SIZE * SS
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(REPO, "Courses", "Environments", "high")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def fft_noise(size, beta, seed, sx=1.0, sy=1.0):
    """Seamless 1/f^beta noise in [0,1]. sx/sy stretch frequency (anisotropy)."""
    rng = np.random.default_rng(seed)
    white = rng.standard_normal((size, size))
    fx = np.fft.fftfreq(size)[None, :] * sx
    fy = np.fft.fftfreq(size)[:, None] * sy
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1.0
    spec = np.fft.fft2(white) / (f ** beta)
    spec[0, 0] = 0
    n = np.real(np.fft.ifft2(spec))
    n -= n.min()
    n /= max(n.max(), 1e-9)
    return n


def to_u8(a):
    return np.clip(a * 255.0 + 0.5, 0, 255).astype(np.uint8)


def normal_from_height(h, strength):
    """Tileable tangent-space normal map from a height array in [0,1]."""
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5 * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5 * strength
    nz = np.ones_like(h)
    ln = np.sqrt(dx * dx + dy * dy + nz * nz)
    n = np.stack([-dx / ln, dy / ln, nz / ln], axis=-1)  # +Y up (OpenGL convention used by Godot)
    return Image.fromarray(to_u8(n * 0.5 + 0.5), "RGB")


def blur_wrap(arr, radius):
    """Gaussian blur that respects tiling (pad by wrap, blur, crop)."""
    pad = int(radius * 3) + 2
    padded = np.pad(arr, ((pad, pad), (pad, pad)), mode="wrap")
    im = Image.fromarray(to_u8(padded), "L").filter(ImageFilter.GaussianBlur(radius))
    out = np.asarray(im, dtype=np.float32) / 255.0
    return out[pad:-pad, pad:-pad]


def wrapped_offsets(points, size):
    """Offsets needed so shapes crossing a tile edge also draw on the opposite side."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    ox = [0]
    oy = [0]
    if min(xs) < 0:
        ox.append(size)
    if max(xs) >= size:
        ox.append(-size)
    if min(ys) < 0:
        oy.append(size)
    if max(ys) >= size:
        oy.append(-size)
    return [(a, b) for a in ox for b in oy]


def lerp_color(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def write_texture(img, name, is_normal=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    img.save(path, optimize=True)
    # Godot .import file (no uid/path: the editor fills these in on first scan)
    normal_flag = 1 if is_normal else 0
    src = "res://Courses/Environments/high/" + name
    content = (
        "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n"
        "[deps]\n\nsource_file=\"%s\"\n\n[params]\n\n"
        "compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.8\n"
        "compress/uastc_level=0\ncompress/rdo_quality_loss=0.0\ncompress/hdr_compression=1\n"
        "compress/normal_map=%d\ncompress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\n"
        "roughness/mode=0\nroughness/src_normal=\"\"\n"
        "process/channel_remap/red=0\nprocess/channel_remap/green=1\n"
        "process/channel_remap/blue=2\nprocess/channel_remap/alpha=3\n"
        "process/fix_alpha_border=true\nprocess/premult_alpha=false\n"
        "process/normal_map_invert_y=false\nprocess/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\nprocess/size_limit=0\ndetect_3d/compress_to=0\n"
    ) % (src, normal_flag)
    with open(path + ".import", "w", newline="\n") as f:
        f.write(content)
    print("wrote", path)


# ---------------------------------------------------------------------------
# Grass
# ---------------------------------------------------------------------------
GRASS_PRESETS = {
    # blades, length range (px @ CANVAS), width, root color, tip color, lean spread (deg), curvature, dry fraction
    "fairway": dict(blades=150000, length=(34, 58), width=2.2, root=(22, 52, 16), tip=(104, 158, 52),
                    spread=38, curve=0.20, dry=0.015, base=(30, 60, 20), nstrength=3.2),
    "green": dict(blades=280000, length=(16, 26), width=1.4, root=(55, 115, 36), tip=(168, 224, 82),
                  spread=24, curve=0.08, dry=0.001, base=(72, 138, 48), nstrength=1.4),
    "rough": dict(blades=105000, length=(70, 128), width=2.9, root=(18, 40, 12), tip=(92, 132, 44),
                  spread=180, curve=0.55, dry=0.10, base=(24, 46, 16), nstrength=4.4),
}


def make_grass(kind, seed):
    p = GRASS_PRESETS[kind]
    rnd = random.Random(seed)
    nprng = np.random.default_rng(seed)

    # Dirt/thatch base with mottling, then blades on top.
    mott = fft_noise(CANVAS // 4, 2.2, seed + 1)
    mott = np.asarray(Image.fromarray(to_u8(mott), "L").resize((CANVAS, CANVAS), Image.BICUBIC), dtype=np.float32) / 255.0
    base = np.zeros((CANVAS, CANVAS, 3), dtype=np.float32)
    for c in range(3):
        base[..., c] = p["base"][c] * (0.75 + 0.5 * mott)
    col_img = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), "RGB")
    h_img = Image.new("L", (CANVAS, CANVAS), 40)
    cd = ImageDraw.Draw(col_img)
    hd = ImageDraw.Draw(h_img)

    main_angle = rnd.uniform(0, 360)
    lo, hi = p["length"]
    for _ in range(p["blades"]):
        x = rnd.uniform(0, CANVAS)
        y = rnd.uniform(0, CANVAS)
        ang = math.radians(main_angle + rnd.uniform(-p["spread"], p["spread"]))
        length = rnd.uniform(lo, hi)
        curve = rnd.uniform(-p["curve"], p["curve"])
        # Large-scale tone variation per blade
        tone = rnd.uniform(0.80, 1.14)
        dry = rnd.random() < p["dry"] * 3.0 if kind == "rough" else rnd.random() < p["dry"]
        root = p["root"]
        tip = (176, 156, 84) if dry else p["tip"]
        if not dry:
            tip = (tip[0] * rnd.uniform(0.85, 1.10), tip[1] * rnd.uniform(0.9, 1.08), tip[2] * rnd.uniform(0.8, 1.15))
        pts = [(x, y)]
        a = ang
        segs = 4
        cx, cy = x, y
        for _s in range(segs):
            a += curve
            cx += math.cos(a) * length / segs
            cy += math.sin(a) * length / segs
            pts.append((cx, cy))
        for ox, oy in wrapped_offsets(pts, CANVAS):
            for s in range(segs):
                t0 = s / segs
                t1 = (s + 1) / segs
                col = lerp_color(root, tip, t1)
                col = tuple(int(max(0, min(255, c * tone))) for c in col)
                w = max(1, int(round(p["width"] * (1.0 - 0.55 * t1))))
                a0 = (pts[s][0] + ox, pts[s][1] + oy)
                a1 = (pts[s + 1][0] + ox, pts[s + 1][1] + oy)
                cd.line([a0, a1], fill=col, width=w)
                hv = int(60 + 195 * t1 * rnd.uniform(0.85, 1.0))
                hd.line([a0, a1], fill=hv, width=w)

    col_small = col_img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    h_small = np.asarray(h_img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS), dtype=np.float32) / 255.0

    # Ambient occlusion-style darkening from blurred height (blade roots darker)
    ao = blur_wrap(h_small, 6.0)
    ao = 0.55 + 0.45 * np.clip(ao * 1.6, 0, 1)
    col = np.asarray(col_small, dtype=np.float32) / 255.0
    col *= ao[..., None]

    # Macro colour drift (seamless) for natural patchiness
    macro = fft_noise(OUT_SIZE, 2.6, seed + 7)
    tint = np.stack([0.92 + 0.16 * macro, 0.94 + 0.12 * macro, 0.88 + 0.20 * (1 - macro)], axis=-1)
    col = np.clip(col * tint, 0, 1)

    albedo = Image.fromarray(to_u8(col), "RGB")
    normal = normal_from_height(h_small, p["nstrength"])
    if kind == "green":
        rough = 0.38 + 0.12 * (1.0 - h_small)
    else:
        rough = 0.80 + 0.15 * (1.0 - h_small)
    rough_img = Image.fromarray(to_u8(rough), "L")
    return albedo, normal, rough_img


# ---------------------------------------------------------------------------
# Bark
# ---------------------------------------------------------------------------
def make_bark(seed):
    # Vertical furrows: anisotropic noise (stretched in Y) warped by low-frequency noise
    # Warped, integer-count vertical ridges (tileable) form the bark plates; deep furrows between them
    uu = (np.arange(OUT_SIZE, dtype=np.float32) / OUT_SIZE)[None, :].repeat(OUT_SIZE, axis=0)
    warp = fft_noise(OUT_SIZE, 2.0, seed, sx=0.5, sy=1.0) - 0.5
    warp2 = fft_noise(OUT_SIZE, 1.6, seed + 1, sx=1.0, sy=1.0) - 0.5
    plate_pos = uu * 44.0 + warp * 5.5 + warp2 * 1.2
    ridge = np.abs(np.sin(np.pi * plate_pos))           # 0 in furrows, 1 on plate tops
    ridge = np.clip(ridge * 1.35, 0, 1) ** 1.3           # flat-topped plates, sharp furrows
    grain = fft_noise(OUT_SIZE, 1.1, seed + 2, sx=0.4, sy=1.0)
    n3 = fft_noise(OUT_SIZE, 2.2, seed + 5)
    h = 0.55 * ridge + 0.36 * grain + 0.09 * n3
    cracks = fft_noise(OUT_SIZE, 1.6, seed + 3, sx=1.0, sy=0.12)
    h *= 1.0 - 0.45 * np.clip((cracks - 0.60) * 4.0, 0, 1)
    h = (h - h.min()) / (h.max() - h.min())

    dark = np.array([0.10, 0.075, 0.055])
    mid = np.array([0.30, 0.235, 0.18])
    light = np.array([0.40, 0.34, 0.28])
    t = h[..., None]
    col = np.where(t < 0.5, dark + (mid - dark) * (t / 0.5), mid + (light - mid) * ((t - 0.5) / 0.5))
    # Lichen / moss tint on some ridges
    moss = np.clip((fft_noise(OUT_SIZE, 2.4, seed + 4) - 0.62) * 4.0, 0, 1)[..., None]
    col = col * (1 - 0.25 * moss) + np.array([0.20, 0.30, 0.14]) * (0.25 * moss)
    albedo = Image.fromarray(to_u8(col), "RGB")
    normal = normal_from_height(h, 7.0)
    rough = Image.fromarray(to_u8(0.82 + 0.15 * (1 - h)), "L")
    return albedo, normal, rough


# ---------------------------------------------------------------------------
# Leaf detail (seamless broadleaf canopy pattern; alpha is not used - silhouette
# still comes from the tree mesh cards)
# ---------------------------------------------------------------------------
def leaf_polygon(cx, cy, length, width, angle, steps=10):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        # Pointed-oval outline
        w = width * math.sin(math.pi * t) ** 0.8 * (1 - 0.25 * t)
        pts.append((t * length, w))
    for i in range(steps, -1, -1):
        t = i / steps
        w = width * math.sin(math.pi * t) ** 0.8 * (1 - 0.25 * t)
        pts.append((t * length, -w))
    ca, sa = math.cos(angle), math.sin(angle)
    return [(cx + px * ca - py * sa, cy + px * sa + py * ca) for px, py in pts]


def make_leaf(seed):
    rnd = random.Random(seed)
    col_img = Image.new("RGB", (CANVAS, CANVAS), (10, 24, 8))
    h_img = Image.new("L", (CANVAS, CANVAS), 0)
    cd = ImageDraw.Draw(col_img)
    hd = ImageDraw.Draw(h_img)

    palette = [
        ((22, 60, 18), (50, 112, 32)),   # deep emerald
        ((34, 78, 20), (80, 138, 38)),   # summer green
        ((46, 90, 22), (112, 158, 46)),  # sunlit olive
        ((60, 96, 24), (140, 170, 52)),  # bright chartreuse tip
        ((74, 90, 28), (160, 150, 56)),  # warm golden-green accent
    ]
    weights = [0.28, 0.32, 0.22, 0.12, 0.06]
    layers = 5
    per_layer = 3300
    for layer in range(layers):
        depth = (layer + 1) / layers
        for _ in range(per_layer):
            cx = rnd.uniform(0, CANVAS)
            cy = rnd.uniform(0, CANVAS)
            length = rnd.uniform(90, 170)
            width = length * rnd.uniform(0.22, 0.32)
            ang = rnd.uniform(0, math.tau)
            poly = leaf_polygon(cx, cy, length, width, ang)
            dark, light = rnd.choices(palette, weights)[0]
            # Deeper layers are shadowed, upper layers catch the sun
            shade = 0.45 + 0.65 * depth
            t = rnd.uniform(0.15, 0.95)
            base = lerp_color(dark, light, t)
            col = tuple(int(max(0, min(255, c * shade))) for c in base)
            hv = int(30 + 225 * depth * rnd.uniform(0.9, 1.0))
            mid_end = (cx + math.cos(ang) * length, cy + math.sin(ang) * length)
            for ox, oy in wrapped_offsets(poly + [mid_end], CANVAS):
                shifted = [(px + ox, py + oy) for px, py in poly]
                cd.polygon(shifted, fill=col)
                hd.polygon(shifted, fill=hv)
                # Midrib & slight darker edge for vein definition
                vein = tuple(int(c * 0.72 + 30) if i == 1 else int(c * 0.72) for i, c in enumerate(col))
                cd.line([(cx + ox, cy + oy), (mid_end[0] + ox, mid_end[1] + oy)], fill=vein, width=2)
                hd.line([(cx + ox, cy + oy), (mid_end[0] + ox, mid_end[1] + oy)], fill=min(255, hv + 18), width=2)

    col_small = col_img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    h_small = np.asarray(h_img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS), dtype=np.float32) / 255.0
    ao = blur_wrap(h_small, 5.0)
    col = np.asarray(col_small, dtype=np.float32) / 255.0
    col *= (0.62 + 0.38 * np.clip(ao * 1.4 + (h_small - ao) * 1.2, 0, 1))[..., None]
    albedo = Image.fromarray(to_u8(np.clip(col, 0, 1)), "RGB")
    normal = normal_from_height(h_small, 3.4)
    return albedo, normal, None


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="fairway,green,rough,bark,leaf")
    args = ap.parse_args()
    want = [w.strip() for w in args.only.split(",") if w.strip()]

    for i, kind in enumerate(["fairway", "green", "rough"]):
        if kind in want:
            a, n, r = make_grass(kind, 1000 + i * 17)
            write_texture(a, "grass_%s_albedo.png" % kind)
            write_texture(n, "grass_%s_normal.png" % kind, True)
            write_texture(r, "grass_%s_roughness.png" % kind)
    if "bark" in want:
        a, n, r = make_bark(4242)
        write_texture(a, "bark_albedo.png")
        write_texture(n, "bark_normal.png", True)
        write_texture(r, "bark_roughness.png")
    if "leaf" in want:
        a, n, _ = make_leaf(9090)
        write_texture(a, "leaf_albedo.png")
        write_texture(n, "leaf_normal.png", True)


if __name__ == "__main__":
    main()
