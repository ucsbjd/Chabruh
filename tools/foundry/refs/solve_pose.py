"""Turns MediaPipe landmarks of a tracked move into the parametric poses render_character.py reads.
The footage is a side view, so image-plane angles and offsets are meaningful; depth is not trusted.
Usage: python solve_pose.py <jbay_refs_dir> <name> <first> <last> <out_json> <frame_indices comma list>
"""
import json
import math
import sys

import numpy as np

ref_dir, name, first, last, out, picks = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], [int(x) for x in sys.argv[6].split(",")]
lm = {int(k): v for k, v in json.load(open(f"{ref_dir}/{name}/landmarks.json")).items()}
idx = list(range(first, last + 1))
STAND_HIP_ABOVE_DECK = 0.86  # meters, the rig standing straight on the board
TORSO_M = 0.49  # hip to shoulder, meters, in the rig


def series(fn):
    vals = np.array([fn(lm[i]["image"]) if i in lm else np.nan for i in idx], float)
    good = ~np.isnan(vals)
    vals = np.interp(np.arange(len(idx)), np.where(good)[0], vals[good])
    return np.convolve(np.pad(vals, 1, mode="edge"), np.ones(3) / 3, mode="valid")  # light smoothing


def P(im, k):
    return np.array(im[k][:2]) * 512.0


mid = lambda im, a, b: (P(im, a) + P(im, b)) / 2
sh = lambda im: mid(im, 11, 12)
hp = lambda im: mid(im, 23, 24)
torso = lambda im: np.linalg.norm(sh(im) - hp(im))
mpp = TORSO_M / np.median([torso(lm[i]["image"]) for i in idx if i in lm])  # meters per pixel
ank = lambda im: mid(im, 27, 28)
bend = series(lambda im: math.degrees(math.atan2(abs(sh(im)[0] - hp(im)[0]), max(hp(im)[1] - sh(im)[1], 1.0))))
hip_h = series(lambda im: (ank(im)[1] - hp(im)[1]) * mpp)
# the arm that reaches farther left is the front (left) one; offsets are shoulder-relative, image right = +X, up = +Z
wl = lambda im: min((P(im, 15), P(im, 16)), key=lambda p: p[0])
wr = lambda im: max((P(im, 15), P(im, 16)), key=lambda p: p[0])
sx = lambda f, a: series(lambda im: (f(im)[a] - sh(im)[a]) * mpp * (1 if a == 0 else -1))
hlx, hlz, hrx, hrz = sx(wl, 0), sx(wl, 1), sx(wr, 0), sx(wr, 1)
poses = []
n = len(picks)
for j, i in enumerate(picks):
    k = i - first
    u = j / max(n - 1, 1)
    poses.append(dict(
        name=f"{name}_{j:02d}", roll=-8 - 10 * u, pitch=2 + 4 * u, lift=0,
        down=float(0.12 + 0.26 * min(bend[k], 70) / 70),  # the hips fold down as the torso folds forward (the ankles are lost in spray)
        yaw=22, bend=float(np.clip(max(bend[k], 44 - 12 * u), 0, 68)), lean=6 + 6 * u, twist=-14, look=42,
        hl=(float(np.clip(hlx[k], -0.6, 0.2)), 0.30, float(np.clip(hlz[k], -0.55, 0.3))),
        hr=(float(np.clip(hrx[k], -0.2, 0.62)), 0.05, float(np.clip(hrz[k], -0.55, 0.3))),
        knee_r_in=0.22 * (1 - u) + 0.1,
    ))
json.dump(poses, open(out, "w"), indent=1)
print(f"mpp {mpp:.4f} m/px;", "bend", [round(p['bend']) for p in poses], "down", [round(p['down'], 2) for p in poses])
