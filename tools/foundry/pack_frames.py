"""Packs the raw Blender passes into the game's toon frame format, one PNG per frame, twice the frame width:

  left half : R skin, G shorts, B board weights (hair is the rest, kept in the right half), A coverage
  right half: R light (0..1, the shader cuts it into bands), G rim, B hair weight, A opaque

Weights, not ids, so the game's smooth texture filtering blends region edges correctly.
Usage: python pack_frames.py <work_dir> <out_dir> <frames> <name>
"""
import sys

import numpy as np
from PIL import Image

SS = 2
RIM_PIXELS = 5  # at the supersampled size
# The key sun sits up and to the left in the image, so the rim runs along the up-left edge.
RIM_STEP = (-1, -1)


def load(path):
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255.0


def down(x):
    h, w = x.shape[:2]
    return x.reshape(h // SS, SS, w // SS, SS, *x.shape[2:]).mean(axis=(1, 3))


def shifted(a, dx, dy):
    out = np.zeros_like(a)
    h, w = a.shape
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = a[ys, xs]
    return out


def pack(mask_path, light_path):
    m, l = load(mask_path), load(light_path)
    a = m[..., 3]
    hair = m[..., :3].min(axis=2)
    skin, shorts, board = (np.clip(m[..., i] - hair, 0, 1) for i in range(3))
    # Edge facing the sun: covered here, empty a few pixels toward the sun.
    toward = shifted(a, -RIM_STEP[0] * RIM_PIXELS, -RIM_STEP[1] * RIM_PIXELS)
    rim = a * (1.0 - toward)
    light = l[..., :3].mean(axis=2)
    cov = down(a)
    safe = np.maximum(cov, 1e-4)
    straight = lambda x: np.clip(down(x * a) / safe, 0, 1)
    left = np.dstack([straight(skin), straight(shorts), straight(board), cov])
    right = np.dstack([np.clip(straight(light), 0, 1), straight(rim), straight(hair), np.ones_like(cov)])
    # Empty pixels carry no weights, so filtering cannot pull colour from nowhere.
    left[cov < 1e-3, :3] = 0
    right[cov < 1e-3, :3] = 0
    return np.concatenate([left, right], axis=1)


def main():
    work, out, frames, name = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    for i in range(frames):
        img = pack(f"{work}/f{i:02d}_mask.png", f"{work}/f{i:02d}_light.png")
        Image.fromarray((img * 255 + 0.5).astype(np.uint8), "RGBA").save(f"{out}/{name}_{i:02d}.png", optimize=True)
    print(f"packed {frames} frames")


main()
