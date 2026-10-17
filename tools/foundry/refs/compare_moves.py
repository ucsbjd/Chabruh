"""Side by side: the gold-standard footage (storyboardimages/move_refs) above, the game below, phase by phase, for the
two moves off the top (docs/balance.md, "Gold standard"). Reference only: the sheet is written under storyboardimages/.

The game frames come from a capture made from the beach, like the footage, with the move played by its hotkey:
  tools\\capture.ps1 -Out g_cut.png -Frames 485 -Move cutback -Camera -30 -NoOverlay -Snaps (270..480 | ? {$_ % 3 -eq 0}) -join ','
Each phase picks the first snap whose rider state matches it (from <capture>-track.json).

Usage: python compare_moves.py <lip_hit|cutback> <gold landmarks json> <gold video> <capture base> <out.jpg>
"""
import json
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw

TILE = 300

# Each phase: a label, the gold time (seconds in the slow-motion clip) and a test on the game's track entry.
PHASES = {
    "lip_hit": [
        ("climbing into the lip", 51.0, lambda e: e["theta"] > 50 and 0.55 < e["u"] < 0.85),
        ("front arm up at the lip", 52.25, lambda e: e["u"] > 0.9 and 15 < e["theta"] < 60 and e["omega"] < -1.0),
        ("the snap: board flat", 52.9, lambda e: e["u"] > 0.88 and -15 < e["theta"] < 15),
        ("board down, the fan", 53.75, lambda e: e["u"] > 0.85 and e["theta"] < -45),
        ("coming round, chest open", 55.0, lambda e: e["theta"] < -60 and 0.65 < e["u"] < 0.85),
        ("floating down", 56.75, lambda e: e["theta"] < -45 and 0.35 < e["u"] < 0.55),
    ],
    "cutback": [
        ("rising, back arm out", 39.0, lambda e: e["theta"] > 25 and 0.35 < e["u"] < 0.6),
        ("turn-in: rail and arm up", 40.4, lambda e: e["move"] == "cutback" and e["theta"] > 0),
        ("carve: body opens", 41.75, lambda e: e["move"] == "cutback" and -100 < e["theta"] < -60),
        ("laid back in the carve", 43.0, lambda e: e["move"] == "cutback" and -140 < e["theta"] < -110),
        ("facing back, tall", 45.25, lambda e: e["move"] == "cutback" and e["theta"] < -155),
        ("knocked back: the fold", 47.75, lambda e: e["move"] == "cutback" and -110 < e["theta"] < -40 and e["omega"] > 3),
        ("compact, riding on", 48.5, lambda e: e["move"] != "cutback" and -20 < e["theta"] < 20 and e["frame"] > 300),
    ],
}


def gold_tiles(landmarks, video, times):
    data = json.load(open(landmarks))
    near = [min(data, key=lambda e: abs(e["t"] - t)) for t in times]
    wanted = {e["t"]: e for e in near}
    cap = cv2.VideoCapture(video)
    fps = cap.get(cv2.CAP_PROP_FPS)
    tiles, i, last = {}, 0, max(wanted)
    while True:
        t = i / fps
        if t > last + 0.01:
            break
        hit = [w for w in wanted if abs(w - t) < 0.5 / fps]
        if not hit:
            cap.grab()
            i += 1
            continue
        ok, frame = cap.read()
        i += 1
        x0, y0, c = wanted[hit[0]]["crop"]
        cx, cy, c2 = x0 + c / 2, y0 + c / 2, c * 1.3
        h, w = frame.shape[:2]
        a, b = int(np.clip(cx - c2 / 2, 0, w - c2)), int(np.clip(cy - c2 / 2, 0, h - c2))
        crop = cv2.cvtColor(frame[b:b + int(c2), a:a + int(c2)], cv2.COLOR_BGR2RGB)
        tiles[hit[0]] = Image.fromarray(crop).resize((TILE, TILE), Image.LANCZOS)
    return [tiles[e["t"]] for e in near]


def game_tile(base, entry):
    im = Image.open(f"{base}-{entry['frame']}.png").convert("RGB")
    half = entry["tall"] * 1.15
    cx, cy = entry["x"], entry["y"] - entry["tall"] * 0.5
    return im.crop((int(cx - half), int(cy - half), int(cx + half), int(cy + half))).resize((TILE, TILE), Image.LANCZOS)


def main():
    move, landmarks, video, base, out = sys.argv[1:6]
    phases = PHASES[move]
    track = json.load(open(base + "-track.json"))
    golds = gold_tiles(landmarks, video, [p[1] for p in phases])
    sheet = Image.new("RGB", (TILE * len(phases), TILE * 2 + 18), (20, 20, 30))
    draw = ImageDraw.Draw(sheet)
    for k, (label, t, test) in enumerate(phases):
        sheet.paste(golds[k], (k * TILE, 18))
        draw.text((k * TILE + 4, 3), label, fill=(255, 230, 120))
        entry = next((e for e in track if test(e)), None)
        if entry is not None:
            sheet.paste(game_tile(base, entry), (k * TILE, 18 + TILE))
            note = f"game {entry['frame'] / 60:.2f}s  heading {entry['theta']:.0f}  u {entry['u']:.2f}"
        else:
            note = "game: phase not reached"
        draw.text((k * TILE + 4, 18 + TILE + 3), note, fill=(255, 255, 0))
        draw.text((k * TILE + 4, 21), f"gold {t:.2f}s", fill=(255, 255, 0))
    sheet.save(out, quality=88)
    print(out)


main()
