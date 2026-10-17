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
  mid-thigh; (the back tattoo was dropped in the second round: it kept appearing and vanishing as the torso turned).
- Not done: pocket flap, drawstring, face detail (the camera sees the back), finger poses. Twelve more moves come in step 9.

## Reference footage and rig checks (step 8, second round)

- The first 20 s of the JBay clip (https://www.youtube.com/watch?v=wiDVI0hUFQ0, never downloaded or committed) was
  read in the browser pane with `tools/sprites/capture_frames.js`-style code: frames painted to a canvas, the red or
  yellow board found by colour to follow the surfer, and a zoomed contact sheet screenshotted. The surfer is only
  about 25 px tall in the 854 x 480 stream, so MediaPipe cannot read it; the poses were set by eye against zoomed
  crops: a low drive with the torso almost horizontal and one arm trailing (bottom turn, about 1 s), the board on its
  rail with the body thrown back at the lip (top turn, about 3 s), a crouched cutback with the head turned back (4.5 s).
- Compare any pose from another side with a debug camera yaw: `blender -b --python render_character.py -- out decals 6 90`
  (90 is a side view, 0 is straight on), then `pack_frames.py` and `check_frames.py` as usual.
- Fixed: the shorts were deformed twice (the copy already carried the body's Armature modifier and I added a second),
  which stretched them below the knees in crouches. They now fit the hips; a Corrective Smooth modifier relaxes bends.

## Move poses from footage (`tools/foundry/refs/`)

The 1080p60 source was downloaded with the owner's OK to `storyboardimages/jbay_refs/` (gitignored). Per move:
`scout.py` (contact sheet to find the shot), `extract_move.py` (tracks the board by colour, crops a square that follows
the surfer, upscales to 512, writes `SHEET_<move>.jpg`), `pose_landmarks.py` (MediaPipe pose landmarker, CPU; needs
`pose_landmarker_heavy.task` from Google's MediaPipe model bucket, about 30 MB, in the same folder), and
`solve_pose.py` (landmarks to the parametric poses in `poses/<move>.json`). Then
`.\tools\foundry\foundry.ps1 -Frames 8 -Name bottom_turn` renders the move, and a yaw-0 render next to the crops
makes `COMPARE_<move>.png`. Done so far: bottom turn (0 to 1.2 s of the clip; the torso fold is floored at about 35
degrees in the later frames because MediaPipe under-reads it there). Not yet for the sprites: the other seven moves.

## The real-time surfer (step 9)

`blender -b --python tools/foundry/export_surfer_glb.py` writes `game/assets/models/surfer.glb` (about 0.8 MB, about 6.8k
triangles): the MPFB body, shorts and hair as one skinned mesh (decimated, normals copied from a capsule stand-in so the
light bands are big and flat), the board as a second mesh, the 8 regions as vertex colours (red = region / 10), and
the poses `trim`, `crouch` and `bottom_turn` baked as one-frame actions with IK already applied and the board level.
In the game `Surfer3D` (`scripts/surfer_3d.gd`) lives inside `WaveStage`'s viewport and `shaders/surfer3d.gdshader`
colours it from the mood. Open it with `?surfer3d` or the 3 key; 1 and 2 toggle the bottom turn and the crouch, which
ease in and out over about 0.12 s and can be reversed at any moment. Capture with `tools\capture.ps1 -Surfer3d bottom_turn`.

### Step 12: the whole library, normals, the face, the details

- **Poses** (board level; the game drives the arms, the legs' bend and the balance, so these give the spine, hips, head
  and hands): `trim`, `crouch` (refined: deeper hinge, back knee in), `bottom_turn`, `top_turn`, `snap` (sitting back
  over the tail, chest open, head turned down the face, hands open), `barrel` (compact, knees together), `floater`
  (taller, weight centred), `air` (knees drawn up), `tumble` (curled up, hands holding the head: `hands_at="head"`) and
  `sit` (astride the board facing the nose, hips `SIT_HIP` above the deck, feet hanging in the water, hands on the rails:
  `sit=True`, `hands_at="board"`, foot targets `fl`/`fr` and knee poles `kl`/`kr`). Every pose curls the fingers
  (`FINGER_CURL`, `THUMB_CURL`, scaled by the pose's `fingers`).
- **Mute the IK before exporting.** The actions already hold the IK's result; the glTF exporter samples each action with
  constraints live, so a live IK pulls every pose's legs and arms toward wherever the last pose left the targets (it is
  why the old model's baked right arm pointed up). `export_glb` mutes every constraint first.
- **Normals.** The capsule stand-in has no end caps (a cap inside an end sphere handed its axis to the skin round it),
  the face, hands and feet keep their own normals (`own_normals`: the stand-in has no nose, fingers or toes), and
  `keep_normals_outward` pulls any corner normal that leans into its face back out. Together they fixed the lit patches
  on his upper back, hands and feet.
- **Decimation that keeps the face.** The face (`face_keep`, the face bones' weights) is decimated to `FACE_RATIO` and the
  rest to `BODY_RATIO`, each as its own edit-mode selection. Do not use the Decimate modifier's vertex group for this: it
  makes zero-weight vertices uncollapsible and eats the rest of the mesh to reach the count (it took his legs off).
  About 10k triangles, 1.6 MB.
- **Details.** The palm print is a decal (`game/assets/textures/palm_print.png`, from `make_decals.py`): the green and blue
  of each corner's vertex colour say where it falls in the print's square (`palm_decal`, `DECAL_SPAN` of the colour
  range, the same constant in `surfer3d.gdshader`), drawn in the trim colour. The back pocket's flap (region 6) and
  button (region 4, ink) are a small patch laid on the shorts and skinned like them (`add_pocket`, `POCKET_BOX`).
- **After exporting**, run `godot_console --headless --path game --import` or the game keeps the old import.
- **Looking at it:** `capture.ps1 -Events 'pose:sit@60' -Snaps 130` holds a baked pose (`Surfer3D.held_pose`) for a
  contact sheet; `-Events 'wipeout@60'` shows the tumble and the lull's sit in context.

## Posing by hand in Blender

1. Make the scene file once: `blender -b --python tools/foundry/render_character.py -- tools/foundry/work/rig tools/foundry/work/decals 1 18 surfer tools/foundry/work/character.blend`
   (about 4 MB, gitignored). Open it in Blender (File > Open).
2. Objects: `Human.rig` (the skeleton), `board`, and empties `foot_L/R` (IK targets, children of the board),
   `knee_L/R` (poles, children of the board), `hand_L/R` and `elbow_L/R` (world space). Legs and arms are IK: move the
   foot and hand targets, not the limb bones. In Pose mode rotate `root` (hips), `spine05` to `spine01`, `neck01` to
   `neck03` and `head`; move or rotate the `board` in Object mode. The board's origin is the sprite anchor.
3. Save the pose: Scripting tab, open `tools/foundry/save_pose.py`, set `SET` (the move, such as `bottom_turn`), `POSE_NAME`
   and `POSITION`, Run Script. It writes into `tools/foundry/poses/<SET>.json` (reusing a name replaces that frame).
   A pose saved this way carries a `raw` block and is rendered exactly as posed.
4. Render: `.\tools\foundry\foundry.ps1 -Frames <count> -Name <SET>`.

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
