"""Runs MediaPipe BlazePose (CPU) on the 512 crops of a move and saves world landmarks plus a skeleton overlay sheet.
Usage: python pose_landmarks.py <out_dir> <name> <first> <last>
"""
import json
import sys

import cv2
import mediapipe as mp
import numpy as np

out_dir, name, first, last = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
from mediapipe.tasks import python as mpt
from mediapipe.tasks.python import vision

MODEL = f"{out_dir}/pose_landmarker_heavy.task"
BONES = [(11, 12), (11, 13), (13, 15), (12, 14), (14, 16), (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (24, 26), (26, 28)]
landmarker = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
    base_options=mpt.BaseOptions(model_asset_path=MODEL), min_pose_detection_confidence=0.3, min_pose_presence_confidence=0.3))
result, tiles = {}, []
for i in range(first, last + 1):
    img = cv2.imread(f"{out_dir}/{name}/f_{i:02d}.png")
    res = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB)))
    vis = img.copy()
    if res.pose_world_landmarks:
        w, im = res.pose_world_landmarks[0], res.pose_landmarks[0]
        result[i] = {"world": [[l.x, l.y, l.z, l.visibility] for l in w], "image": [[l.x, l.y, l.visibility] for l in im]}
        for a, b in BONES:
            cv2.line(vis, (int(im[a].x * 512), int(im[a].y * 512)), (int(im[b].x * 512), int(im[b].y * 512)), (0, 255, 0), 2)
    cv2.putText(vis, f"{i} {'ok' if i in result else 'MISS'}", (6, 24), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)
    tiles.append(cv2.resize(vis, (256, 256)))
cols = 6
rows = (len(tiles) + cols - 1) // cols
sheet = np.zeros((rows * 256, cols * 256, 3), np.uint8)
for k, t in enumerate(tiles):
    r, c = divmod(k, cols)
    sheet[r * 256:(r + 1) * 256, c * 256:(c + 1) * 256] = t
cv2.imwrite(f"{out_dir}/POSE_{name}.jpg", sheet, [cv2.IMWRITE_JPEG_QUALITY, 82])
json.dump(result, open(f"{out_dir}/{name}/landmarks.json", "w"))
print(f"{len(result)}/{last - first + 1} frames detected")
