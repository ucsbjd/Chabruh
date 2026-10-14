"""Packs the raw Blender passes into the game's toon frame format: one PNG per frame, three frames wide.

  panel 0: R skin, G shorts, B board weights, A coverage
  panel 1: R hair, G tattoo ink, B trim weights, A opaque
  panel 2: R stripe A, G stripe B, B light (0..1, the shader cuts it into bands), A opaque

Weights, not ids, so the game's smooth texture filtering blends region edges correctly. The rim line is found
by the shader from the coverage alpha. Usage: python pack_frames.py <work_dir> <out_dir> <frames> <name>
"""
import sys

import numpy as np
from PIL import Image

SS = 2


def load(path):
    return np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32) / 255.0


def down(x):
    h, w = x.shape[:2]
    return x.reshape(h // SS, SS, w // SS, SS, *x.shape[2:]).mean(axis=(1, 3))


def pack(work, i):
    passes = [load(f"{work}/f{i:02d}_m{g}.png") for g in range(3)]
    light = load(f"{work}/f{i:02d}_light.png")
    cov = down(passes[0][..., 3])
    safe = np.maximum(cov, 1e-4)

    def straight(x, a):
        s = safe[..., None] if x.ndim == 3 else safe
        return np.clip(down(x * (a[..., None] if x.ndim == 3 else a)) / s, 0, 1)

    a = passes[0][..., 3]
    m = [straight(p[..., :3], a) for p in passes]
    lit = straight(light[..., :3].mean(axis=2), a)
    one = np.ones_like(cov)
    p0 = np.dstack([m[0], cov])
    p1 = np.dstack([m[1], one])
    p2 = np.dstack([m[2][..., 0], m[2][..., 1], lit, one])
    out = np.concatenate([p0, p1, p2], axis=1)
    empty = np.concatenate([cov, cov, cov], axis=1) < 1e-3
    out[empty, :3] = 0  # empty pixels carry no weights, so filtering cannot pull colour from nowhere
    return out


def main():
    work, out, frames, name = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
    for i in range(frames):
        Image.fromarray((pack(work, i) * 255 + 0.5).astype(np.uint8), "RGBA").save(f"{out}/{name}_{i:02d}.png", optimize=True)
    print(f"packed {frames} frames")


main()
