# Surfer foundry (steps 7 and 8)

Blender renders the surfer in a few poses as flat region passes; the game recolours them with the current mood.
Step 7 proved the pipeline with a placeholder figure; step 8 replaced it with the real character.

## Installed (all free)

- Blender 4.5.10 LTS: `winget install --id BlenderFoundation.Blender.LTS.4.5 --silent` (about 360 MB, one admin prompt).
- MPFB 2.0.18 (MakeHuman for Blender), from the official extensions site:
  `blender --online-mode -b --command extension install --enable mpfb`. Its built-in data is enough; the separate
  MPFB asset pack (clothes, hair, skins) is not used.
- Python 3.11 env in `tools/foundry/.venv`: `uv sync --project tools/foundry` (numpy, pillow, opencv-python,
  mediapipe; mediapipe is for step 9, not used yet).

## One command

```powershell
.\tools\foundry\foundry.ps1            # -Frames 6 -Name surfer; about 10 s of Blender, 14 s in all
```

1. `make_decals.py`: draws the two flat decals (shaka-and-wave tattoo, palm tree) as images.
2. `render_character.py` (inside `blender -b --python`): makes the MPFB human (male, lean, 1.8 m), rigs it with MPFB's
   default skeleton, builds the shorts, hair and board, poses six moves, and renders raw passes per pose at 2x:
   three region passes (`m0`..`m2`, one-hot emission, three regions each) and a `light` pass (white diffuse under the
   key sun only). The sprite pivot (board underside centre) is projected into `meta.json`.
3. `pack_frames.py`: downsamples 2x and writes `game/assets/sprites/surfer/surfer_NN.png`.
4. `check_frames.py`: size, the board pivot on the anchor (`SurferSprites.ANCHOR`, 1 px), the board present, the figure
   not cropped, and a contact sheet at `tools/foundry/work/surfer/contact.png`.

## The character

- Body: MPFB human, macro values gender 1.0, age 0.5, muscle 0.62, weight 0.30, height solved to 1.80 m.
  The shape keys are baked and the helper geometry removed. Skeleton: MPFB `default` rig (not Rigify: not needed
  for sprite rendering). Legs and arms are Blender IK chains; the feet are IK targets parented to the board, so the
  stance follows the board. Torso lean, twist and head turn are world-space bone rotations (`POSES` at the top of
  `render_character.py`).
- Regions (the mask codes): 0 skin, 1 shorts (coral), 2 board (cream), 3 hair (sun-bleached spikes and mullet,
  mustache), 4 tattoo ink, 5 trim (aqua waistband, side stripe, palm print), 6 and 7 board stripes (pink, yellow; the
  coral and aqua bands reuse regions 1 and 5). The shorts are a shell copied from the body between waist and
  mid-thigh; the tattoo is an image decal mapped on the back in body space, so it bends with the body.
- Not done: pocket flap, drawstring, face detail (the camera sees the back), finger poses. Twelve more moves come in step 9.

## Frame format ("toon")

One PNG per frame, three panels wide (468 x 420 each; taller than the Kling frames so a rolled board is not cut off,
same scale and same anchor from the top-left). Panel 0: R skin, G shorts, B board weights, A coverage. Panel 1: R hair,
G ink, B trim. Panel 2: R stripe A, G stripe B, B light (0 to 1). Weights, not ids, so texture filtering blends region
edges correctly. `shaders/surfer_toon.gdshader` cuts the light into shade, middle and lit bands, tints them from the
mood (`surfer_*` properties of `MoodData`, with a violet shade), and finds the rim line from the coverage alpha.
`SurferSprites` marks these animations `"format": "toon"`; the Kling `ride` frames stay `"flat"`.
Constants shared by Blender and Godot: frame size, anchor, pixels per meter (top of `render_character.py`,
`check_frames.py`, `surfer_sprites.gd`).

## Looking at it

`?pose=surfer` (the default) or P in the main scene; `?pose=ride` is the old Kling sprite. The six poses cycle slowly
until step 9 picks them from how the player rides. Desktop capture:

```powershell
.\tools\capture.ps1 -Out shot.png -Size 0.6 -Hollow 0.5 -Peel 3 -Mood sunset -Pose surfer -Frames 60
```

## License and sources

| Piece | Source | License |
| --- | --- | --- |
| Human base mesh, macro targets, rig weights | MPFB 2.0.18 built-in data (MakeHuman project) | CC0 (stated in `base.obj` and the data files) |
| MPFB add-on code (used only to build the mesh) | extensions.blender.org, Joel Palmius | GPL-3.0-or-later; it does not cover the images it makes |
| Shorts, hair, mustache, board, tattoo and palm decals | written for this project (`render_character.py`, `make_decals.py`) | ours |
| Look reference | `storyboardimages/character/surfer-sheet-chatgpt.jpg`, made by the project owner with ChatGPT | local only, not shipped |

No MPFB asset-pack items, no Kling images, and no footage are in the sprites. The sprites are renders of our own
model, so they ship under the project's own terms.
