"""Checks the packed frames and writes a contact sheet for review.
Usage: python check_frames.py <frames_dir> <name> <frames> <contact_png>
Must agree with game/scripts/surfer_sprites.gd (FRAME_SIZE, ANCHOR).
"""
import sys

import numpy as np
from PIL import Image

FRAME_W, FRAME_H = 468, 360
ANCHOR = (203.2, 355.3)
COLORS = np.array([[232, 150, 110], [255, 61, 139], [198, 241, 53], [60, 40, 40]], dtype=np.float32)  # skin, shorts, board, hair
SHADE = np.array([96, 98, 150], dtype=np.float32)


def preview(img):
    left, right = img[:, :FRAME_W], img[:, FRAME_W:]
    w = np.dstack([left[..., :3], right[..., 2]])
    w = w / np.maximum(w.sum(axis=2, keepdims=True), 1e-4)
    base = w @ COLORS
    band = np.where(right[..., 0] > 0.5, 1.0, np.where(right[..., 0] > 0.18, 0.78, 0.0))[..., None]
    lit = base * band + (base * 0.55 + SHADE * 0.45) * (1 - band)
    lit = np.where(right[..., 1:2] > 0.3, [255, 235, 160], lit)
    bg = np.full_like(lit, 70)
    a = left[..., 3:4]
    return lit * a + bg * (1 - a)


def main():
    folder, name, frames, contact = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    problems, tiles = [], []
    for i in range(frames):
        img = np.asarray(Image.open(f"{folder}/{name}_{i:02d}.png").convert("RGBA"), dtype=np.float32) / 255.0
        if img.shape[:2] != (FRAME_H, FRAME_W * 2):
            problems.append(f"frame {i}: size {img.shape[1]}x{img.shape[0]}")
            continue
        board = (img[:FRAME_H, :FRAME_W, 2] > 0.5) & (img[:, :FRAME_W, 3] > 0.5)
        ys, xs = np.nonzero(board)
        if len(xs) == 0:
            problems.append(f"frame {i}: no board")
            continue
        cx, bottom = (xs.min() + xs.max()) / 2, ys.max() + 1
        if abs(cx - ANCHOR[0]) > 8 or abs(bottom - ANCHOR[1]) > 8:
            problems.append(f"frame {i}: board centre ({cx:.1f}, bottom {bottom}) is off the anchor {ANCHOR}")
        tiles.append(preview(img))
    cols = 4
    rows = (len(tiles) + cols - 1) // cols
    sheet = np.full((rows * FRAME_H, cols * FRAME_W, 3), 40, dtype=np.float32)
    for k, t in enumerate(tiles):
        r, c = divmod(k, cols)
        sheet[r * FRAME_H:(r + 1) * FRAME_H, c * FRAME_W:(c + 1) * FRAME_W] = t
    Image.fromarray(sheet.astype(np.uint8)).save(contact)
    if problems:
        print("FOUNDRY CHECK FAILED:\n  " + "\n  ".join(problems))
        sys.exit(1)
    print(f"foundry checks passed: {frames} frames, {FRAME_W}x{FRAME_H}, board on the anchor; contact sheet {contact}")


main()
