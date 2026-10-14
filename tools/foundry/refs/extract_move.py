"""Tracks the surfer in the source clip by the colour of his board, crops a square around him, upscales it to 512,
and writes the crops plus a contact sheet. Reference only: everything lands in storyboardimages/ (gitignored).
Usage: python extract_move.py <video> <out_dir> <name> <start> <end> <fps> <board_color: yellow|red> [crop_px]
"""
import json
import os
import sys

import cv2
import numpy as np

video, out_dir, name, start, end, fps, color = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6]), sys.argv[7]
crop = int(sys.argv[8]) if len(sys.argv) > 8 else 260
folder = f"{out_dir}/{name}"
os.makedirs(folder, exist_ok=True)
cap = cv2.VideoCapture(video)


def board_center(frame):
    hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
    yellow = cv2.inRange(hsv, (18, 120, 150), (35, 255, 255))
    red = cv2.inRange(hsv, (0, 140, 110), (12, 255, 255)) | cv2.inRange(hsv, (170, 140, 110), (180, 255, 255))
    m = yellow | red  # the board is yellow with a red rail and shows red when rolled; either keeps the crop on him
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, _, stats, cents = cv2.connectedComponentsWithStats(m)
    if n < 2:
        return None
    k = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
    return (cents[k][0], cents[k][1], stats[k, cv2.CC_STAT_AREA]) if stats[k, cv2.CC_STAT_AREA] > 25 else None


times = np.arange(start, end, 1.0 / fps)
raw = []
for t in times:
    cap.set(cv2.CAP_PROP_POS_MSEC, t * 1000)
    ok, f = cap.read()
    raw.append((f, board_center(f) if ok else None))
pts = np.array([[p[0], p[1]] if p else [np.nan, np.nan] for _, p in raw])
for ax in (0, 1):  # fill gaps, then smooth, so the crop does not jitter
    good = ~np.isnan(pts[:, ax])
    pts[:, ax] = np.interp(np.arange(len(pts)), np.where(good)[0], pts[good, ax])
    pts[:, ax] = np.convolve(np.pad(pts[:, ax], 2, mode="edge"), np.ones(5) / 5, mode="valid")
tiles, meta = [], []
for i, ((f, _), (cx, cy)) in enumerate(zip(raw, pts)):
    # the surfer stands above the board, so shift the window up a little
    x0, y0 = int(cx - crop / 2), int(cy - crop * 0.68)
    x0 = max(0, min(f.shape[1] - crop, x0))
    y0 = max(0, min(f.shape[0] - crop, y0))
    c = cv2.resize(f[y0:y0 + crop, x0:x0 + crop], (512, 512), interpolation=cv2.INTER_LANCZOS4)
    lab = cv2.cvtColor(c, cv2.COLOR_BGR2LAB)
    lab[..., 0] = cv2.createCLAHE(2.0, (4, 4)).apply(lab[..., 0])  # light contrast normalisation
    c = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)
    cv2.imwrite(f"{folder}/f_{i:02d}.png", c)
    meta.append({"t": float(times[i]), "box": [x0, y0, crop], "board": [float(cx), float(cy)]})
    tiles.append(cv2.putText(cv2.resize(c, (256, 256)), f"{times[i]:.2f}", (4, 16), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1))
cols = 6
rows = (len(tiles) + cols - 1) // cols
sheet = np.zeros((rows * 256, cols * 256, 3), np.uint8)
for k, t in enumerate(tiles):
    r, c = divmod(k, cols)
    sheet[r * 256:(r + 1) * 256, c * 256:(c + 1) * 256] = t
cv2.imwrite(f"{out_dir}/SHEET_{name}.jpg", sheet, [cv2.IMWRITE_JPEG_QUALITY, 82])
json.dump(meta, open(f"{folder}/track.json", "w"))
print(len(tiles), "frames", sheet.shape)
