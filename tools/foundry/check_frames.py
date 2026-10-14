"""Checks the packed frames and writes a contact sheet for review.
Usage: python check_frames.py <frames_dir> <name> <frames> <contact_png> <meta_json>
Must agree with game/scripts/surfer_sprites.gd (FRAME_SIZE, ANCHOR).
"""
import json
import sys

import numpy as np
from PIL import Image

FRAME_W, FRAME_H = 468, 420
ANCHOR = (203.2, 355.3)
# skin, shorts, board, hair, ink, trim, stripe A, stripe B
COLORS = np.array([[225, 150, 100], [255, 100, 90], [250, 235, 215], [210, 170, 90], [50, 35, 40],
                   [60, 200, 190], [255, 61, 139], [255, 220, 90]], dtype=np.float32)
SHADE = np.array([96, 98, 150], dtype=np.float32)


def weights(img):
    p0, p1, p2 = (img[:, i * FRAME_W:(i + 1) * FRAME_W] for i in range(3))
    w = np.dstack([p0[..., 0], p0[..., 1], p0[..., 2], p1[..., 0], p1[..., 1], p1[..., 2], p2[..., 0], p2[..., 1]])
    return w, p0[..., 3], p2[..., 2]


def preview(img):
    w, a, light = weights(img)
    base = (w / np.maximum(w.sum(axis=2, keepdims=True), 1e-4)) @ COLORS
    band = np.where(light > 0.5, 1.0, np.where(light > 0.18, 0.8, 0.0))[..., None]
    lit = base * band + (base * 0.6 + SHADE * 0.4) * (1 - band)
    bg = np.full_like(lit, 70)
    return lit * a[..., None] + bg * (1 - a[..., None])


def main():
    folder, name, frames, contact, meta_path = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
    meta = json.load(open(meta_path))
    problems, tiles = [], []
    for i in range(frames):
        img = np.asarray(Image.open(f"{folder}/{name}_{i:02d}.png").convert("RGBA"), dtype=np.float32) / 255.0
        if img.shape[:2] != (FRAME_H, FRAME_W * 3):
            problems.append(f"frame {i}: size {img.shape[1]}x{img.shape[0]}")
            continue
        w, a, _ = weights(img)
        px, py = meta["frames"][i]["pivot"]
        if abs(px - ANCHOR[0]) > 1.0 or abs(py - ANCHOR[1]) > 1.0:
            problems.append(f"frame {i}: board pivot ({px:.1f}, {py:.1f}) is off the anchor {ANCHOR}")
        if ((w[..., 2] + w[..., 6] + w[..., 7]) * a > 0.5).sum() < 200:
            problems.append(f"frame {i}: the board is missing")
        edge = max(a[0].max(), a[:, 0].max(), a[:, -1].max())
        if edge > 0.05:
            problems.append(f"frame {i}: the figure touches the frame edge (cropped)")
        tiles.append(preview(img))
    cols = 3
    rows = (len(tiles) + cols - 1) // cols
    sheet = np.full((rows * FRAME_H, cols * FRAME_W, 3), 40, dtype=np.float32)
    for k, t in enumerate(tiles):
        r, c = divmod(k, cols)
        sheet[r * FRAME_H:(r + 1) * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W] = t
    Image.fromarray(sheet.astype(np.uint8)).save(contact)
    if problems:
        print("FOUNDRY CHECK FAILED:\n  " + "\n  ".join(problems))
        sys.exit(1)
    print(f"foundry checks passed: {frames} frames, {FRAME_W}x{FRAME_H}, board pivot on the anchor; contact sheet {contact}")


main()
