"""Averages a calibration run (game/../calibration/session-*.json) and suggests input dials.

    python tools/analyze_calibration.py [session.json]      (default: the newest session)

Writes calibration/summary.json and calibration/summary.png next to the session. Needs only numpy and pillow.
Event rows are [time, kind, amount_x, amount_y, position_x, position_y]; kinds are pan (two-finger scroll),
wheel (amount_x is the Godot button index: 4 up, 5 down, 6 left, 7 right), touch_drag, key and mouse.
"""
import glob
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDER = os.path.join(ROOT, "calibration")
MOVE_ORDER = ["up_down", "bottom_to_top", "cutback", "hit_lip", "floater", "trim"]
WHEEL = {4: (0.0, 1.0), 5: (0.0, -1.0), 6: (1.0, 0.0), 7: (-1.0, 0.0)}  # (ahead, up) per notch


def signals(events):
    """Turns raw events into time-ordered (t, ahead, up) steps: positive means ahead (left) and up."""
    steps = []
    for t, kind, ax, ay, _px, _py in events:
        if kind in ("pan", "touch_drag"):
            steps.append((t, -ax, -ay))      # fingers moving left or up are positive
        elif kind == "wheel":
            dx, dy = WHEEL.get(int(ax), (0.0, 0.0))
            steps.append((t, dx * ay, dy * ay))
        elif kind == "key":
            steps.append((t, ax, ay))
    return steps


def strokes(values, min_size):
    """Sizes of the swings between successive turning points of a cumulative signal."""
    if len(values) < 3:
        return []
    turning = [values[0]]
    direction = 0
    for previous, current in zip(values, values[1:]):
        step = current - previous
        if step == 0:
            continue
        sign = 1 if step > 0 else -1
        if direction and sign != direction:
            turning.append(previous)
        direction = sign
    turning.append(values[-1])
    sizes = [abs(b - a) for a, b in zip(turning, turning[1:])]
    return [s for s in sizes if s >= min_size]


def analyse_trial(trial):
    steps = signals(trial["events"])
    t = np.array([s[0] for s in steps]) if steps else np.zeros(0)
    ahead = np.cumsum([s[1] for s in steps]) if steps else np.zeros(0)
    up = np.cumsum([s[2] for s in steps]) if steps else np.zeros(0)
    kinds = {}
    for row in trial["events"]:
        kinds[row[1]] = kinds.get(row[1], 0) + 1
    trace = np.array(trial["trace"]) if trial["trace"] else np.zeros((0, 5))
    mouse_x = [row[4] for row in trial["events"] if row[1] == "mouse"]
    rate = lambda v: float(np.max(np.abs(np.diff(v)) / max(np.min(np.diff(t)), 1e-3))) if len(v) > 2 else 0.0
    return {
        "duration": trial["duration"], "kinds": kinds, "t": t, "ahead": ahead, "up": up, "trace": trace,
        "up_range": float(up.max() - up.min()) if len(up) else 0.0,
        "ahead_range": float(ahead.max() - ahead.min()) if len(ahead) else 0.0,
        "up_strokes": strokes(list(up), 0.5), "ahead_strokes": strokes(list(ahead), 0.5),
        "first_up": float(up[min(len(up) - 1, 3)]) if len(up) else 0.0,
        "mouse_range": float(max(mouse_x) - min(mouse_x)) if mouse_x else 0.0,
        "u_max": float(trace[:, 2].max()) if len(trace) else 0.0, "u_min": float(trace[:, 2].min()) if len(trace) else 0.0,
        "speed_max": float(trace[:, 3].max()) if len(trace) else 0.0, "sharp_max": float(trace[:, 4].max()) if len(trace) else 0.0,
    }


def draw(summary, per_move, path):
    cell_w, cell_h = 560, 330
    image = Image.new("RGB", (cell_w * 3, cell_h * 4), (24, 14, 40))
    pen = ImageDraw.Draw(image)
    for i, move in enumerate(MOVE_ORDER):
        if move not in per_move:
            continue
        ox, oy = (i % 3) * cell_w, (i // 3) * cell_h * 2
        pen.text((ox + 8, oy + 6), "%s   (%d trials)" % (move, len(per_move[move])), fill=(255, 235, 200))
        for row, (key, colour) in enumerate((("up", (120, 230, 190)), ("ahead", (255, 170, 120)))):
            top = oy + 24 + row * 150
            pen.rectangle((ox + 8, top, ox + cell_w - 8, top + 140), outline=(80, 60, 110))
            pen.text((ox + 12, top + 2), "raw two-finger: %s (cumulative)" % key, fill=colour)
            scale = max(1e-6, max((np.abs(r[key]).max() if len(r[key]) else 0) for r in per_move[move]))
            for r in per_move[move]:
                if len(r["t"]) < 2:
                    continue
                points = [(ox + 12 + t / 15.0 * (cell_w - 24), top + 70 - v / scale * 62) for t, v in zip(r["t"], r[key])]
                pen.line(points, fill=colour, width=1)
    image.save(path)


def main():
    files = sorted(glob.glob(os.path.join(FOLDER, "session-*.json")))
    path = sys.argv[1] if len(sys.argv) > 1 else (files[-1] if files else None)
    if not path:
        sys.exit("No calibration session found in " + FOLDER)
    data = json.load(open(path))
    per_move = {}
    for trial in data["trials"]:
        per_move.setdefault(trial["move"], []).append(analyse_trial(trial))
    summary = {"session": os.path.basename(path), "moves": {}}
    for move, trials in per_move.items():
        mean = lambda key: round(float(np.mean([r[key] for r in trials])), 3)
        kinds = {}
        for r in trials:
            for k, v in r["kinds"].items():
                kinds[k] = kinds.get(k, 0) + v
        summary["moves"][move] = {
            "trials": len(trials), "duration": mean("duration"), "events_by_kind": kinds,
            "up_range": mean("up_range"), "ahead_range": mean("ahead_range"),
            "up_strokes_median": round(float(np.median(sum((r["up_strokes"] for r in trials), []) or [0])), 3),
            "ahead_strokes_median": round(float(np.median(sum((r["ahead_strokes"] for r in trials), []) or [0])), 3),
            "mouse_range_px": mean("mouse_range"), "surfer_u_range": [mean("u_min"), mean("u_max")],
            "surfer_speed_max": mean("speed_max"), "surfer_sharpness_max": mean("sharp_max"),
        }
    suggestions = {}
    up_down = per_move.get("up_down", [])
    if up_down:
        stroke = float(np.median(sum((r["up_strokes"] for r in up_down), []) or [0]))
        if stroke > 0:
            suggestions["pan_height_gain"] = round(0.8 / stroke, 5)
        first = float(np.mean([r["first_up"] for r in up_down]))
        suggestions["invert_pan_height"] = bool(first < 0)
        suggestions["note"] = "invert_pan_height is true when the opening UP stroke came out as down; stroke is the median swing in raw units."
    sideways = [r for m in ("cutback", "bottom_to_top") for r in per_move.get(m, [])]
    if sideways:
        stroke = float(np.median(sum((r["ahead_strokes"] for r in sideways), []) or [0]))
        if stroke > 0:
            suggestions["pan_steer_gain"] = round(0.5 / stroke, 5)
    summary["suggested_tuning"] = suggestions
    out = os.path.join(os.path.dirname(path), "summary")
    json.dump(summary, open(out + ".json", "w"), indent=1)
    draw(summary, per_move, out + ".png")
    print(json.dumps(summary, indent=1))
    print("wrote", out + ".json and .png")


if __name__ == "__main__":
    main()
