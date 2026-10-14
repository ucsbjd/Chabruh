"""Run inside Blender (Scripting tab, open this file, Run Script) after posing the character by hand in
work/character.blend. It saves the pose into tools/foundry/poses/<SET>.json, replacing a pose of the same name, so
render_character.py renders it exactly as posed. Pose by moving: the board (Object mode), the hand and foot targets,
the knee and elbow poles (the empties), and rotating spine, neck and head bones in Pose mode. Leave the IK limbs to IK.
"""
import json
import os

import bpy

SET = os.environ.get("POSE_SET", "bottom_turn")        # which move this pose belongs to (the file poses/<SET>.json)
POSE_NAME = "bottom_turn_03"  # the frame's name; reuse a name to replace it, use a new one to add a frame
POSITION = None            # None appends at the end; 0, 1, 2... inserts at that place in the sequence

rig = bpy.data.objects["Human.rig"]
board = bpy.data.objects["board"]
pose = {
    "name": POSE_NAME,
    "raw": {
        "board": {"location": list(board.location), "rotation": list(board.rotation_euler)},
        "empties": {n: list(bpy.data.objects[n].location) for n in
                    ("foot_L", "foot_R", "knee_L", "knee_R", "hand_L", "hand_R", "elbow_L", "elbow_R")},
        "bones": {},
    },
}
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION" if pb.rotation_mode != "QUATERNION" else pb.rotation_mode
    if any(abs(x) > 1e-5 for x in pb.location) or any(abs(a - b) > 1e-5 for a, b in zip(pb.rotation_quaternion, (1, 0, 0, 0))):
        pose["raw"]["bones"][pb.name] = list(pb.location) + list(pb.rotation_quaternion)
path = os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "poses", SET + ".json"))
poses = json.load(open(path)) if os.path.exists(path) else []
poses = [p for p in poses if p["name"] != POSE_NAME]
poses.insert(len(poses) if POSITION is None else POSITION, pose)
json.dump(poses, open(path, "w"))
print("saved", POSE_NAME, "to", path, f"({len(poses)} poses)")
