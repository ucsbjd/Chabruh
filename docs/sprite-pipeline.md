# Sprite pipeline: real surfing motion to game sprites

How the surfer's animation frames are made, so more animations can be added later without rediscovering any of
this. The first run (the `ride` animation, 35 frames) took one short clip and about 27 Kling credits.

## The idea

Real surfing motion looks right; hand-posed rigs and per-image AI generation did not (see "What did not work").
So the motion comes from real footage and the look comes from a locked original character:

1. **Find a continuous shot** of the move in the reference video (3 to 10 seconds, one camera, no cuts).
2. **Capture its frames** (about 12 per second) through the browser pane.
3. **Make a motion clip** (MP4) from the frames.
4. **Kling motion control** makes our character perform that motion on a flat lilac background.
5. **Extract sprites**: cut the result into frames, key out the background, register every frame on the board,
   scale, and save PNGs.
6. **Add them to the game**: one line in `SurferSprites` and the frames in `game/assets/sprites/surfer/`.

## Steps and commands

Everything lives in `tools/sprites/`. Python needs `pillow`, `numpy` and `imageio_ffmpeg` (which ships its own
ffmpeg; nothing else to install).

1. **Find the shot.** Open the video in the browser pane (decline cookies), paste `capture_frames.js`, then draw a
   labelled contact sheet of frames every 0.25 to 0.75 s over the section you want. A shot change shows as a sudden
   jump of zoom or place. Pick a stretch with no cut that is at least 3 seconds long (shorter shots can be slowed
   down by repeating each captured frame).
2. **Capture frames.** For each time `t` in steps of 1/12 s: run `await __show(t)`, wait 0.5 s, take a full-scale
   screenshot. The tool saves each screenshot as a file (its path is printed); keep them in order. Use
   `browser_batch` with at most 25 actions, so 8 frames per call. A 3.3 s clip is 40 frames.
3. **Make the clip.** `python tools/sprites/make_clip.py frames_dir clip.mp4 --fps 12`
4. **Run motion control.** Upload the clip and `tools/sprites/character_reference.png` (our surfer, centred on a flat
   lilac 16:9 canvas) with `file_upload`, then call `motion_control` with model `kling-video-v3_0`,
   `motionDirection=image_direction`, `resolution=720p`, `keepOriginalSound=false`, and a prompt that names the
   character's look, the moves, "plain flat pale lilac background, no water, no waves, no spray, no shadow", and
   that the whole body and board stay in frame. **Cost: 27 credits for a 3.3 s clip at 720p (about 8 credits per
   second); it is charged when submitted and the price is not shown first.** It takes about 2.5 minutes.
5. **Extract.** `python tools/sprites/extract_sprites.py motion.mp4 game/assets/sprites/surfer --fps 12 --name ride`
   It prints the frame size and anchor. Keying uses the lilac background colour from the frame corners; Kling's
   own lilac spray speckle is removed so the game can draw its own spray; each frame is placed so the board's
   centre (the lowest tenth of the figure) lands on one anchor pixel.
6. **Register it.** In `game/scripts/surfer_sprites.gd` update `FRAME_SIZE` and `ANCHOR` from the printout and add
   the animation to `ANIMATIONS`, `ORDER` and `LABELS`. Import (`godot_console --headless --path game --import`),
   run `tools\test.ps1` (it checks every frame exists, has the right size and sits on the anchor), then look at it
   with `?gallery` or `.\tools\capture.ps1 -Gallery`.

## Tips for the next animations

- **One clip, several animations.** The cost is per second of video, so cut one long clip (up to 10 s) into
  several animations rather than paying for many 3 s clips. Pick footage with the same camera side (surfer seen
  from behind and slightly to the side, travelling left, as in the game). Mirror footage that goes the other way
  with `ffmpeg -vf hflip` before step 4.
- **Which move.** Bottom turn, top turn, cutback, floater, air, barrel crouch, pop-up, paddle. Choose footage where
  the board and body stay in frame and nothing crosses in front of the surfer.
- **Loops.** `ping_pong: true` plays a clip forward then backward, so moves that do not end where they start still
  loop. A move that should play once (an air, a wipeout) wants a one-shot entry instead (not built yet; add a
  `loop` flag to `ANIMATIONS` when the first one is needed).
- **Blending** between animations is a hard switch for now. A 0.1 s cross-dissolve (a second `AnimatedSprite2D`
  fading out) is the cheap fix; do it when step 6 starts switching animations from how the player rides.
- **Mood.** The frames have baked colours. If a mood needs a tint, multiply with a mood colour in a small shader
  (a mood role in `MoodData`, not a hard-coded colour).
- **Size.** 35 frames at 468x360 are 2.4 MB in the export. Keep each new animation to about 12 to 24 frames and
  lower `TARGET_HEIGHT` in `extract_sprites.py` if the pack grows past about 6 MB.
- **Footage is reference only.** The source video is never downloaded, committed or shipped, and the sprites show
  an original character. Frames are captured through the pane and kept in the scratch folder only.

## What did not work (so it is not retried)

| Attempt | What happened |
| --- | --- |
| Jointed 2D rig with posed joints (step 4's first try) | Stiff and mannequin-like next to the key frames, whatever the proportions. |
| Stick-figure sketches as the pose guide for Kling | The model followed the sketch literally and the poses looked unathletic. |
| Several poses on one generated sheet, one photo each | The model ignored the individual photos and drew the same crouch three times, and added skateboard wheels. |
| Restyling one photo per sprite (`kling-image-o1`, 1 credit each) | Good single images, but the camera angle and style drift between images, so they do not match as a set. |
| Locking the character with a reference image plus a pose photo (round 2) | Much better consistency, but the poses only roughly followed the source. Fine for stills, not for animation. |
| **Real motion video through `motion_control`** | **Works: one character, one camera, real mechanics, 35 consistent frames.** |

Prompt lessons: the key frame alone as the style reference works; do not pass a previous sheet as a reference
(the model copies its figures); say "surfboard, no wheels" or it draws skateboards; avoid the words "reference
sheet" (it adds a title).
