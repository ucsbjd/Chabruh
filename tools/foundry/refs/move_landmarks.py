"""Reads a move from reference footage in one decoding pass: follows the surfer from a starting point, reads his pose
with MediaPipe's pose landmarker (CPU) on a square crop around him, and writes the crops, a skeleton overlay sheet,
the landmarks and per-frame body measurements (docs/balance.md, "Gold standard"). Reference only: everything lands in
the output folder under storyboardimages/ (gitignored); nothing from the footage is committed.

Usage: python move_landmarks.py <video> <out_dir> <name> <start_s> <end_s> <every_s> <x> <y> <model.task> [slow]
  x, y: where the surfer is at <start_s>, in the video's own pixels. slow: how many times slow the footage is (1 for
  real time), so the measurements also carry real seconds.

Measurements, in the picture (x right, y up, degrees; the surfer rides toward the left of the picture):
  lean     the trunk (mid hip to mid shoulder) from vertical, positive leaning left (the way he rides)
  front_arm / back_arm  shoulder to wrist direction (0 right, 90 up, 180 left), elbow bend (180 straight)
  front_hand_up / back_hand_up  wrist height above its shoulder, in trunk lengths
  knees    the bend at each knee (180 straight); crouch: hips above the ankles, in leg lengths
  over     the trunk's centre left of the mid ankle, in trunk lengths (weight over the front foot when positive)
  feet     the line from the back ankle to the front ankle (the board's angle, roughly)
  head     where the face points from the mid ear: yaw_img (left/right) and pitch_img (up/down), and turned (0 back of the
           head to the camera, 1 face to the camera) from how far apart the ears and nose read
  chest    0 back to the camera, 1 chest to the camera, from the world landmarks' shoulder depth order
"""
import json
import math
import os
import sys

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision

video, out_dir, name = sys.argv[1], sys.argv[2], sys.argv[3]
start, end, every = float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
cx, cy = float(sys.argv[7]), float(sys.argv[8])
model = sys.argv[9]
slow = float(sys.argv[10]) if len(sys.argv) > 10 else 1.0
SIZE = 512
BONES = [(11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (24, 26), (26, 28), (0, 7), (0, 8)]
# A regular-stance surfer riding toward the picture's left, back to the camera: his left side is the front (toward the
# nose). MediaPipe's left and right are the person's own.
FRONT = {"shoulder": 11, "elbow": 13, "wrist": 15, "hip": 23, "knee": 25, "ankle": 27, "ear": 7}
BACK = {"shoulder": 12, "elbow": 14, "wrist": 16, "hip": 24, "knee": 26, "ankle": 28, "ear": 8}

folder = os.path.join(out_dir, name)
os.makedirs(folder, exist_ok=True)
landmarker = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
    base_options=mpt.BaseOptions(model_asset_path=model), min_pose_detection_confidence=0.2, min_pose_presence_confidence=0.2))


def angle(v):
    return math.degrees(math.atan2(v[1], v[0]))


def bend(a, b, c):
    u, w = a - b, c - b
    return math.degrees(math.acos(np.clip(np.dot(u, w) / (np.linalg.norm(u) * np.linalg.norm(w) + 1e-9), -1.0, 1.0)))


def measure(p, world):
    """p: 33 x 2 picture points with y up; world: 33 x 3 metric points (x right, y down, z toward the camera is negative)."""
    sh = (p[11] + p[12]) / 2
    hip = (p[23] + p[24]) / 2
    ank = (p[27] + p[28]) / 2
    trunk = np.linalg.norm(sh - hip) + 1e-9
    leg = (np.linalg.norm(p[23] - p[25]) + np.linalg.norm(p[25] - p[27]) + np.linalg.norm(p[24] - p[26]) + np.linalg.norm(p[26] - p[28])) / 2
    lean = math.degrees(math.atan2(-(sh - hip)[0], (sh - hip)[1]))
    out = {"lean": lean}
    for label, side in (("front", FRONT), ("back", BACK)):
        s, e, w = p[side["shoulder"]], p[side["elbow"]], p[side["wrist"]]
        out[f"{label}_arm"] = angle(w - s)
        out[f"{label}_elbow"] = bend(s, e, w)
        out[f"{label}_hand_up"] = (w - s)[1] / trunk
        out[f"{label}_knee"] = bend(p[side["hip"]], p[side["knee"]], p[side["ankle"]])
    out["crouch"] = (hip - ank)[1] / (leg + 1e-9)
    com = hip * 0.55 + sh * 0.45
    out["over"] = -(com - ank)[0] / trunk
    out["feet"] = angle(p[FRONT["ankle"]] - p[BACK["ankle"]])
    ear = (p[7] + p[8]) / 2
    face = p[0] - ear
    out["head_yaw_img"] = angle(face)
    out["head_pitch_img"] = face[1] / trunk
    ears = np.linalg.norm(p[7] - p[8]) / trunk
    out["head_turned"] = float(np.clip(np.linalg.norm(face) / (ears + 0.15), 0.0, 1.5))
    # In the world landmarks x is the picture's right and z the depth (smaller is nearer the camera). Seen from behind,
    # his left shoulder is on the picture's left (the line from right shoulder to left points left, 180 degrees);
    # side on it points away from or toward the camera (+-90); chest to the camera it points right (0).
    across = world[11] - world[12]
    yaw = math.degrees(math.atan2(across[2], across[0]))
    out["body_yaw"] = yaw
    out["chest"] = 1.0 - abs(yaw) / 180.0
    return out


cap = cv2.VideoCapture(video)
fps = cap.get(cv2.CAP_PROP_FPS)
W, H = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
crop = 0.24 * H
results, tiles = [], []
i, next_t = 0, start
while True:
    t = i / fps
    if t > end:
        break
    if t < next_t - 0.5 / fps:
        if not cap.grab():
            break
        i += 1
        continue
    ok, frame = cap.read()
    if not ok:
        break
    i += 1
    next_t += every
    half = crop / 2
    x0, y0 = int(np.clip(cx - half, 0, W - crop)), int(np.clip(cy - half, 0, H - crop))
    sq = cv2.resize(frame[y0:y0 + int(crop), x0:x0 + int(crop)], (SIZE, SIZE), interpolation=cv2.INTER_CUBIC)
    res = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(sq, cv2.COLOR_BGR2RGB)))
    vis = sq.copy()
    entry = {"t": round(t, 3), "real": round((t - start) / slow, 3), "crop": [x0, y0, int(crop)]}
    if res.pose_landmarks:
        im, wl = res.pose_landmarks[0], res.pose_world_landmarks[0]
        pix = np.array([[l.x * SIZE, (1.0 - l.y) * SIZE] for l in im])  # y up
        world = np.array([[l.x, l.y, l.z] for l in wl])
        entry["image"] = [[round(l.x, 4), round(l.y, 4), round(l.visibility, 3)] for l in im]
        entry["world"] = world.round(4).tolist()
        entry.update({k: round(v, 3) for k, v in measure(pix, world).items()})
        for a, b in BONES:
            cv2.line(vis, (int(im[a].x * SIZE), int(im[a].y * SIZE)), (int(im[b].x * SIZE), int(im[b].y * SIZE)), (0, 255, 0), 2)
        for k, colour in ((15, (255, 0, 255)), (16, (0, 128, 255)), (0, (0, 255, 255))):
            cv2.circle(vis, (int(im[k].x * SIZE), int(im[k].y * SIZE)), 5, colour, -1)
        # Follow him: the crop centres on his trunk and grows or shrinks with his size on screen.
        body = np.array([[l.x, l.y] for l in im])[[11, 12, 23, 24, 27, 28]]
        mid = body.mean(axis=0)
        cx, cy = x0 + mid[0] * crop, y0 + mid[1] * crop
        span = (body[:, 1].max() - body[:, 1].min()) * crop
        crop = float(np.clip(0.75 * crop + 0.25 * max(span * 2.4, 0.16 * H), 0.14 * H, 0.5 * H))
    cv2.putText(vis, f"{t:.2f}s{'' if 'image' in entry else ' MISS'}", (6, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
    cv2.imwrite(os.path.join(folder, f"t{t:06.2f}.jpg"), vis, [cv2.IMWRITE_JPEG_QUALITY, 88])
    tiles.append(cv2.resize(vis, (192, 192)))
    results.append(entry)
cols = 10
rows = (len(tiles) + cols - 1) // cols
sheet = np.zeros((rows * 192, cols * 192, 3), np.uint8)
for k, tile in enumerate(tiles):
    r, c = divmod(k, cols)
    sheet[r * 192:(r + 1) * 192, c * 192:(c + 1) * 192] = tile
cv2.imwrite(os.path.join(out_dir, f"POSE_{name}.jpg"), sheet, [cv2.IMWRITE_JPEG_QUALITY, 85])
json.dump(results, open(os.path.join(out_dir, f"{name}_landmarks.json"), "w"))
print(f"{name}: {sum('image' in r for r in results)}/{len(results)} frames read")
