# Surfer foundry (step 7: hello world)

Blender renders a throwaway placeholder surfer; the game draws it in the wave's flat colours, tinted by the mood.
The real character and motion come in steps 8 and 9 and reuse every piece here.

## Installed (all free)

- Blender 4.5.10 LTS: `winget install --id BlenderFoundation.Blender.LTS.4.5 --silent` (about 360 MB, needs one
  admin prompt). Found at `%ProgramFiles%\Blender Foundation\Blender 4.5\blender.exe`.
- Python 3.11 env in `tools/foundry/.venv`, made by `uv sync --project tools/foundry` (numpy, pillow,
  opencv-python, mediapipe; mediapipe is for step 9, not used yet).

## One command

```powershell
.\tools\foundry\foundry.ps1            # -Frames 8 -Name placeholder
```

It runs, in order, and takes about 10 s for 8 frames on the dev laptop (Cycles on CPU, 4 samples, 936 x 720 per pass):

1. `render_placeholder.py` (inside `blender -b --python`): builds the figure and board from primitives, poses a
   looping trim cycle, and renders two raw passes per frame into `tools/foundry/work/<name>/`:
   `fNN_mask.png` (flat emission: skin red, shorts green, board blue, hair white) and `fNN_light.png`
   (white diffuse under the key sun only, no bounces).
2. `pack_frames.py`: downsamples 2x (anti-aliasing), turns the mask into region weights, derives the rim from the
   silhouette edge facing the sun, and writes `game/assets/sprites/surfer/<name>_NN.png`.
3. `check_frames.py`: every frame is 936 x 360 (two 468 x 360 halves), the board's centre and underside sit on the
   anchor (`SurferSprites.ANCHOR`, 8 px tolerance), and a contact sheet is written to
   `tools/foundry/work/<name>/contact.png`.

## Frame format ("toon")

One PNG per frame, twice the frame width. Left half: R skin, G shorts, B board weights, A coverage. Right half:
R light (continuous, 0 to 1), G rim, B hair weight, A opaque. Weights, not ids, so texture filtering blends region
edges correctly. `shaders/surfer_toon.gdshader` reads both halves, cuts the light into shade, middle and lit bands,
and colours them from the mood (`surfer_*` properties in `MoodData`): violet-tinted shade, warm lit band, rim
line. Nothing is baked; to re-tint, change the mood. `SurferSprites` marks these animations `"format": "toon"`;
the Kling `ride` frames stay `"flat"`.

Constants that must agree between Blender and Godot: frame size, anchor and `FRAME_METERS` (top of
`render_placeholder.py`, `check_frames.py`, `surfer_sprites.gd`).

## Looking at it

`?pose=placeholder` (or the P key) in the main scene; `?gallery` lists it. Desktop capture:

```powershell
.\tools\capture.ps1 -Out shot.png -Size 0.6 -Hollow 0.5 -Peel 3 -Mood neon -Pose placeholder -Frames 90
```

## Notes

- Swapping the placeholder for the real character means replacing `build_surfer()` and `build_board()`; the camera,
  passes, packer, checks and shader stay.
- The light and rim directions are set once (`SUN_DIRECTION`, `RIM_STEP`); keep them on the same side.
