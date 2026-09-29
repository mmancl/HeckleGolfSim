"""
Generates high-resolution textures for SpeedTree-style Weeping Willow:
1. willow-crown-green.png / willow-crown-gold.png
   - Lush, voluminous, rounded crown canopy spray with arching branchlets and feathery willow leaves.
   - Used for the high rounded crown dome cap, upper branches, and volumetric filler.
2. willow-curtain-green.png / willow-curtain-gold.png
   - Dense cascading weeping curtains with long hanging tendrils and leafy top collar.
   - Used for the outer cascading veils hanging down towards ground and water.
"""

import os
import math
import random
import numpy as np
from PIL import Image, ImageDraw

TEXTURES_DIR = "addons/shapespark-low-poly-exterior-plants/textures"
os.makedirs(TEXTURES_DIR, exist_ok=True)

def draw_willow_leaf(draw, px, py, angle, length, width, col, midrib=True):
    # Tip of leaf
    tip_x = px + math.cos(angle) * length
    tip_y = py + math.sin(angle) * length

    # Midpoints of blade
    mid_cx = px + math.cos(angle) * (length * 0.42)
    mid_cy = py + math.sin(angle) * (length * 0.42)

    perp_angle = angle + math.pi * 0.5
    half_w = width * 0.5
    left_x = mid_cx + math.cos(perp_angle) * half_w
    left_y = mid_cy + math.sin(perp_angle) * half_w
    right_x = mid_cx - math.cos(perp_angle) * half_w
    right_y = mid_cy - math.sin(perp_angle) * half_w

    draw.polygon([(px, py), (left_x, left_y), (tip_x, tip_y), (right_x, right_y)], fill=col)
    if midrib:
        midrib_col = (max(0, col[0] - 25), max(0, col[1] - 25), max(0, col[2] - 25), 255)
        draw.line([(px, py), (tip_x, tip_y)], fill=midrib_col, width=1)


def generate_willow_crown(palette="green", out_filename="willow-crown-green.png", seed=301):
    width, height = 1024, 1024
    im = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    rng = random.Random(seed)

    if palette == "green":
        stem_col = (85, 80, 42, 255)
        leaf_colors = [
            (68, 130, 42, 255),   # base lush green
            (88, 160, 52, 255),   # bright leaf green
            (118, 190, 68, 255),  # sunny lime / chartreuse highlight
            (52, 108, 32, 255),   # deep shadow green
            (138, 202, 84, 255),  # sun-dappled crown tip
            (78, 142, 48, 255),   # mid green
            (102, 175, 60, 255),  # vibrant golden-green
        ]
    else:
        stem_col = (130, 110, 40, 255)
        leaf_colors = [
            (210, 175, 45, 255),  # rich golden yellow
            (230, 195, 60, 255),  # bright sunny gold
            (185, 150, 35, 255),  # amber gold
            (242, 212, 85, 255),  # top highlight
            (160, 130, 30, 255),  # deep golden shadow
            (198, 162, 42, 255),  # mid amber
        ]

    # Crown spray architecture:
    # A full, rounded dome spray with fan-shaped arching stems originating from center-bottom (512, 900)
    # spreading upward and outward into a broad rounded canopy dome.
    origin_x = width * 0.5
    origin_y = height * 0.88

    # Primary arching boughs in a rounded fan
    num_boughs = 14
    for b_idx in range(num_boughs):
        # Fan angle from -65 deg to +65 deg off vertical
        fan_t = (b_idx / float(num_boughs - 1)) * 2.0 - 1.0 # -1 to 1
        base_angle = -math.pi * 0.5 + fan_t * (math.pi * 0.38)
        bough_len = rng.uniform(420, 620) * (1.0 - abs(fan_t) * 0.22)

        # Generate smooth curving path arching up and out
        num_steps = 18
        pts = []
        cx, cy = origin_x, origin_y
        for s in range(num_steps):
            t = s / float(num_steps - 1)
            # Arching curvature: curves slightly outward and droops at end
            curv_angle = base_angle + fan_t * (t * 0.35)
            step_len = (bough_len / num_steps)
            cx += math.cos(curv_angle) * step_len + rng.uniform(-4, 4)
            cy += math.sin(curv_angle) * step_len + rng.uniform(-3, 3)
            pts.append((cx, cy))

        # Draw bough stem
        stem_pts = [(int(p[0]), int(p[1])) for p in pts]
        draw.line(stem_pts, fill=stem_col, width=rng.randint(3, 5))

        # Secondary branchlets branching off
        for p_idx in range(3, len(pts) - 1, 2):
            px, py = pts[p_idx]
            sub_len = rng.uniform(90, 180)
            sub_side = 1.0 if rng.random() > 0.5 else -1.0
            sub_angle = base_angle + sub_side * rng.uniform(0.4, 0.9)
            sub_end = (px + math.cos(sub_angle) * sub_len, py + math.sin(sub_angle) * sub_len)
            draw.line([(int(px), int(py)), (int(sub_end[0]), int(sub_end[1]))], fill=stem_col, width=2)

            # Leaves along secondary branchlet
            for st_step in range(6):
                st_t = st_step / 6.0
                lx = px + (sub_end[0] - px) * st_t
                ly = py + (sub_end[1] - py) * st_t
                l_angle = sub_angle + (1.0 if st_step % 2 == 0 else -1.0) * rng.uniform(0.3, 0.7)
                draw_willow_leaf(draw, lx, ly, l_angle, rng.uniform(22, 38), rng.uniform(5.5, 9.0), rng.choice(leaf_colors))

        # Leaves along primary bough
        for p_idx in range(2, len(pts)):
            px, py = pts[p_idx]
            for _ in range(rng.randint(2, 4)):
                l_side = 1.0 if rng.random() > 0.5 else -1.0
                l_angle = base_angle + l_side * rng.uniform(0.4, 1.1) + rng.uniform(-0.2, 0.2)
                draw_willow_leaf(draw, px, py, l_angle, rng.uniform(24, 42), rng.uniform(6.0, 9.5), rng.choice(leaf_colors))

    # Dense rounded dome infill: layered foliage clumps across the top dome
    # Elliptical dome zone: center (512, 450), rx=380, ry=320
    for _ in range(650):
        # Sample point within upper rounded dome
        u = rng.uniform(0, 1)
        theta = rng.uniform(0, math.pi * 2)
        rx = 390 * math.sqrt(u)
        ry = 330 * math.sqrt(u)
        cx = width * 0.5 + math.cos(theta) * rx
        cy = 460 + math.sin(theta) * ry

        # Leaves droop downward more towards perimeter
        dist_from_top = cy / height
        l_angle = (math.pi * 0.5 if rng.random() < 0.6 else math.atan2(cy - 460, cx - width * 0.5)) + rng.uniform(-0.5, 0.5)
        l_len = rng.uniform(24, 44)
        l_wid = rng.uniform(6.0, 10.0)
        draw_willow_leaf(draw, cx, cy, l_angle, l_len, l_wid, rng.choice(leaf_colors))

    # Clean alpha cutoff
    arr = np.array(im)
    alpha = arr[:, :, 3]
    arr[:, :, 3] = np.where(alpha > 80, 255, 0).astype(np.uint8)

    out_im = Image.fromarray(arr, mode="RGBA")
    out_path = os.path.join(TEXTURES_DIR, out_filename)
    out_im.save(out_path, format="PNG")
    print(f"Saved crown texture {out_filename} ({width}x{height})")


def generate_willow_curtain(palette="green", out_filename="willow-curtain-green.png", seed=101):
    width, height = 1024, 1024
    im = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    rng = random.Random(seed)

    if palette == "green":
        stem_col = (90, 85, 45, 255)
        leaf_colors = [
            (65, 125, 40, 255),   # base lush green
            (85, 155, 50, 255),   # bright leaf green
            (115, 185, 65, 255),  # sunny lime highlight
            (50, 105, 30, 255),   # shadowed leaf
            (135, 195, 80, 255),  # delicate tip highlight
            (75, 135, 45, 255),   # mid green
            (95, 168, 55, 255),   # golden-green sunlit
        ]
    else:
        stem_col = (130, 110, 40, 255)
        leaf_colors = [
            (210, 175, 45, 255),
            (230, 195, 60, 255),
            (185, 150, 35, 255),
            (240, 210, 80, 255),
            (160, 130, 30, 255),
            (195, 160, 40, 255),
        ]

    # Dense foliage header/collar across the top (Y: 0 to 140) to seamlessly merge with canopy
    for _ in range(450):
        cx = rng.uniform(40, width - 40)
        cy = rng.uniform(10, 130)
        l_angle = math.pi * 0.5 + rng.uniform(-0.8, 0.8)
        draw_willow_leaf(draw, cx, cy, l_angle, rng.uniform(22, 38), rng.uniform(6.0, 9.5), rng.choice(leaf_colors))

    # Generate 22 cascading pendulous strands
    num_strands = 22
    x_positions = np.linspace(45, width - 45, num_strands)

    for i, base_x in enumerate(x_positions):
        bx = base_x + rng.uniform(-14, 14)
        start_y = rng.uniform(40, 110)
        strand_length = rng.uniform(height * 0.72, height * 0.95)
        end_y = min(height - 12, start_y + strand_length)

        points = []
        curr_x = bx
        curr_y = start_y
        step_y = 11.0
        sway_freq = rng.uniform(0.005, 0.012)
        sway_phase = rng.uniform(0, math.pi * 2)
        sway_amp = rng.uniform(15, 32)

        while curr_y <= end_y:
            curr_x = bx + math.sin(curr_y * sway_freq + sway_phase) * sway_amp + rng.uniform(-1.5, 1.5)
            points.append((curr_x, curr_y))
            curr_y += step_y

        if len(points) < 4:
            continue

        stem_pts = [(int(p[0]), int(p[1])) for p in points]
        draw.line(stem_pts, fill=stem_col, width=rng.randint(2, 3))

        for p_idx in range(len(points) - 1):
            px, py = points[p_idx]
            t = (py - start_y) / strand_length
            leaf_prob = 0.88 if t < 0.75 else (0.70 if t < 0.92 else 0.45)
            if rng.random() > leaf_prob:
                continue

            sides = [-1, 1] if rng.random() < 0.85 else [rng.choice([-1, 1])]
            for side in sides:
                angle = math.pi * 0.5 + side * rng.uniform(0.35, 0.68) + rng.uniform(-0.1, 0.1)
                leaf_len = rng.uniform(20, 40) * (1.0 - t * 0.32)
                leaf_width = rng.uniform(5.0, 9.0) * (1.0 - t * 0.28)
                draw_willow_leaf(draw, px, py, angle, leaf_len, leaf_width, rng.choice(leaf_colors))

    arr = np.array(im)
    alpha = arr[:, :, 3]
    arr[:, :, 3] = np.where(alpha > 80, 255, 0).astype(np.uint8)

    out_im = Image.fromarray(arr, mode="RGBA")
    out_path = os.path.join(TEXTURES_DIR, out_filename)
    out_im.save(out_path, format="PNG")
    print(f"Saved curtain texture {out_filename} ({width}x{height})")


def main():
    print("Generating Weeping Willow foliage textures (crown & curtain)...")
    generate_willow_crown("green", "willow-crown-green.png", seed=301)
    generate_willow_crown("gold", "willow-crown-gold.png", seed=402)
    generate_willow_curtain("green", "willow-curtain-green.png", seed=101)
    generate_willow_curtain("gold", "willow-curtain-gold.png", seed=202)
    print("All willow textures generated successfully!")

if __name__ == "__main__":
    main()
