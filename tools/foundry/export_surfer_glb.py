"""Exports game/assets/models/surfer.glb (the real-time surfer) from the same MPFB character the sprites use.
Run: blender -b --python tools/foundry/export_surfer_glb.py
Poses are baked into the file as one-frame actions (trim, crouch, bottom_turn) with the IK already applied, board level.
"""
import os
import runpy
import sys

here = os.path.dirname(os.path.abspath(__file__))
repo = os.path.normpath(os.path.join(here, "..", ".."))
work = os.path.join(here, "work", "glb")
os.makedirs(work, exist_ok=True)
sys.argv = [sys.argv[0], "--", work, os.path.join(here, "work", "decals"), "99", "18", "glb", "",
            os.path.join(repo, "game", "assets", "models", "surfer.glb")]
runpy.run_path(os.path.join(here, "render_character.py"), run_name="__main__")
