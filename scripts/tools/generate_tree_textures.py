"""
Generates stylized PBR / alpha-cutout textures for diverse tree varieties:
1. Weeping Willow (golden-lime weeping leaves with cascading hanging tendrils & weathered willow bark)
2. Paper Birch (chalky white bark with dark horizontal lenticels & bright fluttering lime-spring leaves)
3. Autumn Golden Oak/Maple (radiant golden amber & honey-yellow foliage)
4. Autumn Crimson Maple (vibrant scarlet crimson & burnt-orange foliage)
5. Evergreen Pine (deep spruce forest green needle clusters & reddish-brown scaly pine bark)
6. Spring Blossom / Flowering Dogwood (soft pastel pink & white blossom petals)
"""

import os
import math
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TEXTURES_DIR = "addons/shapespark-low-poly-exterior-plants/textures"
os.makedirs(TEXTURES_DIR, exist_ok=True)

def generate_willow_bark():
    width, height = 557, 1024
    im = Image.new("RGB", (width, height), (75, 70, 62))
    draw = ImageDraw.Draw(im)
    rng = random.Random(101)

    # Base vertical furrow lines
    for x in range(width):
        col_offset = rng.randint(-15, 15)
        base_gray = 70 + col_offset
        draw.line([(x, 0), (x, height)], fill=(base_gray + 5, base_gray, base_gray - 8))

    # Add deep vertical bark fissures and ridges
    for _ in range(80):
        x = rng.randint(0, width - 1)
        depth = rng.randint(20, 50)
        thick = rng.randint(2, 6)
        curr_x = float(x)
        for y in range(0, height, 15):
            curr_x += rng.uniform(-2.5, 2.5)
            curr_x = max(0, min(width - 1, curr_x))
            c = (max(0, 50 - depth), max(0, 46 - depth), max(0, 40 - depth))
            draw.line([(int(curr_x), y), (int(curr_x), y + 16)], fill=c, width=thick)

    # Add subtle greenish moss patches on lower half
    for _ in range(25):
        mx = rng.randint(0, width)
        my = rng.randint(height // 2, height)
        mr = rng.randint(15, 50)
        draw.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(68, 76, 52))

    im = im.filter(ImageFilter.GaussianBlur(1.0))
    im.save(os.path.join(TEXTURES_DIR, "willow-bark.jpg"), quality=92)
    print("Saved willow-bark.jpg")


def generate_birch_bark():
    width, height = 557, 1024
    im = Image.new("RGB", (width, height), (228, 226, 220))
    draw = ImageDraw.Draw(im)
    rng = random.Random(202)

    # Subtle vertical paper grain
    for x in range(width):
        v = rng.randint(-8, 8)
        draw.line([(x, 0), (x, height)], fill=(225 + v, 223 + v, 218 + v))

    # Prominent dark horizontal lenticel dashes (iconic birch markings)
    for _ in range(350):
        x = rng.randint(0, width - 60)
        y = rng.randint(0, height)
        len_w = rng.randint(12, 65)
        h = rng.randint(2, 5)
        darkness = rng.randint(25, 45)
        draw.rectangle([x, y, x + len_w, y + h], fill=(darkness, darkness + 2, darkness + 4))
        # Smudge / rough edges on lenticels
        draw.line([(x - 4, y + 1), (x + len_w + 4, y + 1)], fill=(darkness + 35, darkness + 35, darkness + 35), width=1)

    # Larger dark knot patches
    for _ in range(12):
        kx = rng.randint(20, width - 60)
        ky = rng.randint(50, height - 50)
        kw = rng.randint(20, 45)
        kh = rng.randint(15, 30)
        draw.polygon([(kx, ky + kh//2), (kx + kw//2, ky), (kx + kw, ky + kh//2), (kx + kw//2, ky + kh)], fill=(32, 30, 28))
        draw.polygon([(kx - 3, ky + kh//2), (kx + kw//2, ky - 3), (kx + kw + 3, ky + kh//2), (kx + kw//2, ky + kh + 3)], outline=(75, 70, 65), width=2)

    im = im.filter(ImageFilter.GaussianBlur(0.8))
    im.save(os.path.join(TEXTURES_DIR, "birch-bark.jpg"), quality=92)
    print("Saved birch-bark.jpg")


def generate_pine_bark():
    width, height = 557, 1024
    im = Image.new("RGB", (width, height), (98, 62, 48))
    draw = ImageDraw.Draw(im)
    rng = random.Random(303)

    # Reddish-brown scaly bark plates
    for x in range(width):
        v = rng.randint(-12, 12)
        draw.line([(x, 0), (x, height)], fill=(96 + v, 60 + v, 46 + v))

    # Furrows and scaly plates
    for _ in range(120):
        x = rng.randint(0, width - 1)
        depth = rng.randint(25, 45)
        thick = rng.randint(2, 5)
        curr_x = float(x)
        for y in range(0, height, 18):
            curr_x += rng.uniform(-3, 3)
            curr_x = max(0, min(width - 1, curr_x))
            c = (max(0, 65 - depth), max(0, 38 - depth), max(0, 28 - depth))
            draw.line([(int(curr_x), y), (int(curr_x), y + 19)], fill=c, width=thick)

    # Warm reddish-orange bark plate highlights
    for _ in range(80):
        px = rng.randint(0, width - 30)
        py = rng.randint(0, height - 30)
        pw = rng.randint(10, 30)
        ph = rng.randint(15, 45)
        draw.ellipse([px, py, px + pw, py + ph], fill=(125, 78, 58))

    im = im.filter(ImageFilter.GaussianBlur(1.0))
    im.save(os.path.join(TEXTURES_DIR, "pine-bark.jpg"), quality=92)
    print("Saved pine-bark.jpg")


def process_branch_variant(base_rel_path, out_rel_path, palette_type, add_weeping_vines=False, rng_seed=42):
    base_full = os.path.join(TEXTURES_DIR, base_rel_path)
    if not os.path.exists(base_full):
        print(f"Skipping {base_rel_path}: file not found")
        return

    base_im = Image.open(base_full).convert("RGBA")
    arr = np.array(base_im)
    alpha = arr[:, :, 3]
    rgb = arr[:, :, :3].astype(np.float32)

    rng = random.Random(rng_seed)
    h, w = alpha.shape

    # Distinguish stem vs leaf pixels
    is_solid = alpha > 100
    is_stem = is_solid & (rgb[:, :, 0] > (rgb[:, :, 1] - 8)) & (rgb[:, :, 2] > 40)
    is_leaf = is_solid & (~is_stem)

    new_rgb = np.copy(rgb)

    if palette_type == "willow":
        # Weeping willow: Golden-olive lime-green with soft yellow highlights & silvery underside
        leaf_count = np.sum(is_leaf)
        # Gradient from top to bottom
        y_coords, x_coords = np.where(is_leaf)
        y_norm = y_coords / float(h)
        noise = np.array([rng.uniform(-0.15, 0.15) for _ in range(leaf_count)])

        # Golden-olive tones
        r_leaf = np.clip(135 + noise * 40 - y_norm * 25, 80, 185)
        g_leaf = np.clip(168 + noise * 35 - y_norm * 20, 110, 215)
        b_leaf = np.clip(62 + noise * 30 + (1.0 - y_norm) * 20, 35, 110)

        new_rgb[is_leaf, 0] = r_leaf
        new_rgb[is_leaf, 1] = g_leaf
        new_rgb[is_leaf, 2] = b_leaf

        # Willow stems: Slender golden-brown / olive-yellow twigs
        new_rgb[is_stem, 0] = np.clip(rgb[is_stem, 0] * 1.15 + 25, 0, 255)
        new_rgb[is_stem, 1] = np.clip(rgb[is_stem, 1] * 1.18 + 22, 0, 255)
        new_rgb[is_stem, 2] = np.clip(rgb[is_stem, 2] * 0.95 + 10, 0, 255)

    elif palette_type == "birch":
        # Birch: Light shimmering fluttery spring/lime green
        leaf_count = np.sum(is_leaf)
        noise = np.array([rng.uniform(-0.12, 0.15) for _ in range(leaf_count)])
        new_rgb[is_leaf, 0] = np.clip(115 + noise * 45, 70, 180)
        new_rgb[is_leaf, 1] = np.clip(178 + noise * 40, 125, 230)
        new_rgb[is_leaf, 2] = np.clip(54 + noise * 30, 25, 100)

        # Light grayish-brown twigs
        new_rgb[is_stem, 0] = np.clip(rgb[is_stem, 0] * 0.9 + 40, 0, 255)
        new_rgb[is_stem, 1] = np.clip(rgb[is_stem, 1] * 0.9 + 35, 0, 255)
        new_rgb[is_stem, 2] = np.clip(rgb[is_stem, 2] * 0.9 + 30, 0, 255)

    elif palette_type == "autumn_gold":
        # Radiant golden amber & honey yellow
        leaf_count = np.sum(is_leaf)
        y_coords, x_coords = np.where(is_leaf)
        noise = np.array([rng.uniform(-0.15, 0.15) for _ in range(leaf_count)])
        new_rgb[is_leaf, 0] = np.clip(224 + noise * 35, 160, 255)
        new_rgb[is_leaf, 1] = np.clip(162 + noise * 40, 110, 220)
        new_rgb[is_leaf, 2] = np.clip(26 + noise * 25, 5, 75)

    elif palette_type == "autumn_red":
        # Vibrant crimson scarlet & burnt orange
        leaf_count = np.sum(is_leaf)
        noise = np.array([rng.uniform(-0.15, 0.15) for _ in range(leaf_count)])
        # Mix of fiery crimson and warm orange
        mix = np.array([rng.random() for _ in range(leaf_count)])
        r_crimson = 195 + noise * 40
        g_crimson = 42 + noise * 30
        b_crimson = 28 + noise * 20

        r_orange = 225 + noise * 30
        g_orange = 95 + noise * 35
        b_orange = 25 + noise * 15

        new_rgb[is_leaf, 0] = np.clip(mix * r_crimson + (1.0 - mix) * r_orange, 120, 255)
        new_rgb[is_leaf, 1] = np.clip(mix * g_crimson + (1.0 - mix) * g_orange, 20, 150)
        new_rgb[is_leaf, 2] = np.clip(mix * b_crimson + (1.0 - mix) * b_orange, 10, 60)

    elif palette_type == "pine":
        # Evergreen pine: Deep forest spruce emerald
        leaf_count = np.sum(is_leaf)
        noise = np.array([rng.uniform(-0.12, 0.12) for _ in range(leaf_count)])
        new_rgb[is_leaf, 0] = np.clip(38 + noise * 25, 15, 75)
        new_rgb[is_leaf, 1] = np.clip(82 + noise * 30, 45, 125)
        new_rgb[is_leaf, 2] = np.clip(44 + noise * 25, 20, 85)

        # Reddish pine twig
        new_rgb[is_stem, 0] = np.clip(rgb[is_stem, 0] * 1.2 + 20, 0, 255)
        new_rgb[is_stem, 1] = np.clip(rgb[is_stem, 1] * 0.8, 0, 255)
        new_rgb[is_stem, 2] = np.clip(rgb[is_stem, 2] * 0.7, 0, 255)

    elif palette_type == "blossom":
        # Flowering cherry / dogwood blossom petals
        leaf_count = np.sum(is_leaf)
        noise = np.array([rng.uniform(-0.1, 0.1) for _ in range(leaf_count)])
        is_pink = np.array([rng.random() > 0.35 for _ in range(leaf_count)])

        new_rgb[is_leaf, 0] = np.where(is_pink, np.clip(248 + noise * 15, 220, 255), np.clip(255 + noise * 10, 240, 255))
        new_rgb[is_leaf, 1] = np.where(is_pink, np.clip(192 + noise * 25, 160, 225), np.clip(242 + noise * 15, 220, 255))
        new_rgb[is_leaf, 2] = np.where(is_pink, np.clip(212 + noise * 20, 180, 240), np.clip(246 + noise * 15, 225, 255))

    out_arr = np.zeros((h, w, 4), dtype=np.uint8)
    out_arr[:, :, :3] = np.clip(new_rgb, 0, 255).astype(np.uint8)
    out_arr[:, :, 3] = alpha

    out_im = Image.fromarray(out_arr, mode="RGBA")

    # If weeping willow, draw cascading pendulous strands hanging downwards!
    if add_weeping_vines:
        draw = ImageDraw.Draw(out_im)
        vine_rng = random.Random(rng_seed + 999)
        # Find candidate branch endpoints and edges to hang vines from
        y_vals, x_vals = np.where(is_solid)
        if len(y_vals) > 0:
            # Pick ~60 points across the lower and middle branch regions
            indices = list(range(len(y_vals)))
            vine_rng.shuffle(indices)
            vines_drawn = 0
            for idx in indices:
                vx = x_vals[idx]
                vy = y_vals[idx]
                # Hang vines downwards towards the bottom
                if vy < h - 180 and vy > 120 and vine_rng.random() < 0.08:
                    strand_len = vine_rng.randint(70, 220)
                    end_y = min(h - 10, vy + strand_len)
                    curr_x = float(vx)
                    pts = [(int(curr_x), vy)]
                    for sy in range(vy + 10, end_y, 12):
                        curr_x += vine_rng.uniform(-3.5, 3.5)
                        pts.append((int(curr_x), sy))

                    # Draw thin vine
                    v_color = (130 + vine_rng.randint(-15, 25), 162 + vine_rng.randint(-15, 25), 58 + vine_rng.randint(-15, 20), 255)
                    if len(pts) > 1:
                        draw.line(pts, fill=v_color, width=2)
                        # Add hanging leaflets along the strand
                        for px, py in pts[1:]:
                            leaf_w = vine_rng.randint(3, 6)
                            leaf_h = vine_rng.randint(7, 14)
                            leaf_col = (142 + vine_rng.randint(-20, 25), 175 + vine_rng.randint(-20, 25), 65 + vine_rng.randint(-15, 25), 255)
                            draw.ellipse([px - leaf_w, py, px + leaf_w, py + leaf_h], fill=leaf_col)

                    vines_drawn += 1
                    if vines_drawn >= 55:
                        break

    out_full = os.path.join(TEXTURES_DIR, out_rel_path)
    out_im.save(out_full, format="PNG")
    print(f"Saved {out_rel_path}")


def main():
    print("Generating tree textures...")
    generate_willow_bark()
    generate_birch_bark()
    generate_pine_bark()

    # 1. Weeping Willow branch textures (with cascading hanging tendrils!)
    process_branch_variant("branch-01.png", "willow-branch-01.png", "willow", add_weeping_vines=True, rng_seed=11)
    process_branch_variant("branch-02.png", "willow-branch-02.png", "willow", add_weeping_vines=True, rng_seed=12)
    process_branch_variant("branch-1-01.png", "willow-branch-1-01.png", "willow", add_weeping_vines=True, rng_seed=13)
    process_branch_variant("branch-1-02.png", "willow-branch-1-02.png", "willow", add_weeping_vines=True, rng_seed=14)

    # 2. Birch branch textures
    process_branch_variant("branch-01.png", "birch-branch-01.png", "birch", add_weeping_vines=False, rng_seed=21)
    process_branch_variant("branch-02.png", "birch-branch-02.png", "birch", add_weeping_vines=False, rng_seed=22)

    # 3. Autumn Golden Oak textures
    process_branch_variant("branch-01.png", "autumn-gold-branch-01.png", "autumn_gold", add_weeping_vines=False, rng_seed=31)
    process_branch_variant("branch-02.png", "autumn-gold-branch-02.png", "autumn_gold", add_weeping_vines=False, rng_seed=32)

    # 4. Autumn Crimson Maple textures
    process_branch_variant("branch-1-01.png", "autumn-red-branch-01.png", "autumn_red", add_weeping_vines=False, rng_seed=41)
    process_branch_variant("branch-1-02.png", "autumn-red-branch-02.png", "autumn_red", add_weeping_vines=False, rng_seed=42)

    # 5. Evergreen Pine needle textures
    process_branch_variant("branch-2-01.png", "pine-branch-01.png", "pine", add_weeping_vines=False, rng_seed=51)
    process_branch_variant("branch-2-02.png", "pine-branch-02.png", "pine", add_weeping_vines=False, rng_seed=52)

    # 6. Spring Flowering Blossom textures
    process_branch_variant("branch-01.png", "blossom-branch-01.png", "blossom", add_weeping_vines=False, rng_seed=61)
    process_branch_variant("branch-02.png", "blossom-branch-02.png", "blossom", add_weeping_vines=False, rng_seed=62)

    print("All tree textures successfully created!")


if __name__ == "__main__":
    main()
