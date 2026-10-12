# Chabruh: project guide for Claude

A laid-back 2D side-view surfing game for the browser (phone in landscape, or desktop), set in a sun-soaked 80s surf-culture world. The game is about the *feel and vibe* of riding a wave, not about winning.

- Live site: https://chabruh-surf.web.app (Firebase project `chabruh-surf`)
- Repo: https://github.com/ucsbjd/Chabruh (private)
- Replaces an earlier 3D three.js prototype. It is kept at git tag `legacy-3d` (commit `5dd0612`). It was removed from the working tree in step 1. Do not restore it.

## Where we are

Work is split into short numbered steps. The source of truth for status is the `STEPS` array at the top of the script in `docs/progress.html` (each step has `status: "todo" | "done"`; the first step that is not done is "next up"). Read it, plus `git log`, before starting anything. The user pastes a "Start step N" prompt into a fresh context, verifies the result, then pastes "Done with step N" to wrap up. Do not mark a step done on your own.

## Vibe rules (non-negotiable)

- No enemies, no hazards that punish, no points, no score, no timers, no combo counters, no leaderboards.
- No cheesy gags or pop-culture jokes. Warm, sincere, a little dreamy.
- No hard fail. A wipeout is a soft tumble: splash, drift, paddle back to the lineup. No "game over" screen.
- Progress is *felt*, not counted. Good flow shows up as richer light, warmer colour, more music layers, bigger spray. Never as a number.
- Lulls between sets are a feature. Never rush the player.
- Touchstone: Over the Hill says "a driving game, not a racing game". Ours is a surfing game, not a surf contest.

## Art direction

Look: **Over the Hill meets 80s Miami sunset, in 2D.** Reference screenshots live on its Steam page (https://store.steampowered.com/app/2929250/over_the_hill/). What they show, and what we copy:

- Flat-shaded, chunky, simplified shapes. No outlines. Soft gradients inside big colour planes.
- Warm golden-hour key light with cool violet/blue shadows (complementary pair). Shadows are coloured, never grey or black.
- Hazy atmospheric depth: far layers fade toward the sky colour. A soft sun glow/bloom washes the frame.
- Readable silhouettes over detail. Saturated but harmonised palette.

80s layer: sunset gradient sky (violet, hot pink, peach, pale gold), striped sun, palm and headland silhouettes, pastel art-deco accents, neon colour-blocked wetsuits and bold board graphics, a light film-grain/VHS touch, synth-wave music. See `storyboardimages/images.jpg` for the palette mood.

Starting palette, sampled from the key frames (tune freely, but keep it in one place, the `Palette` autoload):

| Role | Colours |
| --- | --- |
| Sky, top to horizon | `#290756` `#6B3380` `#B45984` `#E8836F` `#F0A878` |
| Sun | `#EBA565` at the top to `#E56F80` at the bottom, with violet `#873F82` gaps between the bars |
| Wave face, light to deep | jade `#25A078`, `#1C776B`, `#135153`, navy `#0C2B4C` at the base; warm rim line `#E8D27A` along the crest |
| Foam and spray | cream `#FDE9DE` lit, violet `#606296` in shade; aqua sea lines `#59D5C1` |
| Neon gear | lime `#C6F135`, pink `#FF3D8B`, ink `#1B1730` |

### The key frames: `storyboardimages/kling/kling-04` (fan A) and `kling-05` (fan B)

The user picked these two AI-generated style frames as **the look that drives every decision**. Judge every visual against them first. The other frames in that folder are secondary: `kling-03` (big barrel C) is the best reference for the barrel and for the wall running down the line, `kling-10` (tube view) is for the tube moment, `kling-06` (small spilling wave) is for small waves. `kling-08` and `kling-09` are misses on the details; ignore them.

- **Flat vector illustration, almost no shading.** The face is 3 or 4 big flat jade bands (light at the top, deep at the base), softly edged, with a thin warm yellow-cream **rim line along the crest**. Optional detail: fine vertical dark streaks and a pale cell-edge network (thin lilac lines forming big polygons) like fan A's lower left.
- **Spray is the hero.** A spiky cream burst at the lip, ringed by **white oval droplets stretched along the radius** and thinning outward, plus a thin white sheet along the board's tail. Where the lip crashes: a serrated cream curtain shaded violet. Foam is cream with violet shade.
- **Sky and sun.** A huge low sun in coral and orange with horizontal bars separated by violet gaps, a violet to pink sky with faint horizontal scanlines, soft cloud shapes, and flat translucent purple palm silhouettes (fan B frames the scene with big ones at the edges).
- **Foreground sea.** Deep teal with flat aqua or cream line networks (fan A: lace cells; fan B: long streaks) and a reflection of the board.
- **Scale and view.** The surfer is **big**: about 0.26 to 0.40 of the screen height, seen from behind with arms wide. The default wave face is about **1.7 times the surfer's height**, with the crest line sloping so the wall recedes a little down the line (left, ahead of the surfer) as in fan B and barrel.jpg. Small waves are about the surfer's height, big barrel waves about 2.4 times. The taller waves in `barrel.jpg` and `kling-01` to `03` are not the target scale.

Look-and-feel is **flat-shaded vector style, not pixel art**. A pixel-crunch/dither pass may come later as an optional toggle. Do not add it unless asked.

### Storyboard references (`storyboardimages/`, local only, copyrighted, never commit or deploy)

14 photos and stills, plus the 12 AI-generated style frames in `storyboardimages/kling/` (described above). What each photo is for:

- `images (1).jpg`: 80s surfer in a neon lime and black wetsuit walking out carrying a board with a bold red graphic. Costume and board look, and the paddle-out intro.
- `images (2).jpg`: low carving turn on a teal face, arms wide, board on its rail, spray fanning behind.
- `images (3).jpg`: deep crouch against a huge green wall with a white lip curtain behind. Barrel framing.
- `images (4).jpg`, `(5)`, `(6)`, `(9)`: snap and top turns with a big radial fan of spray thrown off the tail. **This is the signature effect.** The fan is a wide arc with fine droplets at the edge, much bigger than the surfer.
- `images (7).jpg`, `(8)`: airs and vertical snaps, board nearly upright, one or both arms up.
- `images.jpg`: Vice City style sunset art with palms and pastel buildings. Palette and mood.
- `licensed-image.jpg`: glassy turquoise barrel at golden hour with light glowing through the lip. A tiny surfer inside the tube.
- `licensed-image (1).jpg`: Teahupoo-style barrel, surfer crouched low in the pocket, trailing a hand on the wall.
- `barrel.jpg`: a real barrel seen from the beach, the best guide to wave **shape and scale**. A long wall about six surfers tall. Glassy aqua and translucent at the thin crest, deeper teal at the base, fine veins running up the face. A tall teardrop barrel on the right with a thick lip whose underside is white with air. Backlit wind-blown mist streams off the crest. Foam bursts at the base. The surfer is tiny.
- `wave1.webp`: a heavy closing wave, the guide for **foam**. A huge white-water curtain falls on one side and foam lace (networks of white lines) drapes over a dark olive face. The surfer is tiny at the bottom.

The surfer is seen mostly from behind and slightly from the side. Several storyboard photos show the front, so mirror the idea of each pose (arm shapes, crouch depth, board angle), not the camera angle.

Poses the surfer needs: walk-in with board, prone paddle, pop-up, trim stance, bottom turn crouch, top turn snap (with arms), cutback, deep barrel crouch with hand-drag, air (board vertical, arms up), floater, soft wipeout tumble.

## Game concept

- Side view, as if shot from the beach. The default surfer rides **right to left** across a long peeling wave, **regular stance (left foot forward), frontside**: back to the camera, chest toward the wave face. The curl, lip and barrel are behind the surfer (right of them) and the open shoulder is ahead (left). The camera follows, so the scenery slides left to right. The world is authored for this default; a mirrored goofy-foot option can come later.
- Two axes the player controls: **position along the wave** (ahead of or behind the curl) and **height on the face** (low for bottom turns, high for top turns and snaps). Speed comes from the slope and from pumping up and down the face.
- Too far ahead: the wave shoulders out and you slow down. Too far behind: the lip lands on you (soft wipeout).
- Spray scales with speed times how sharply you turn. Top-of-the-wave snaps throw the big fan. Air and hang-time matter. The tube is the calm, glowing reward.
- Controls: desktop, mouse X steers along the wave and the mouse wheel sets height on the face (arrow keys / WASD as a fallback). Mobile, two-finger drag: horizontal steers, vertical changes height. Smooth and clamp everything. Never let the wheel scroll the page.
- Forgiving by default. Expose feel dials in one tuning resource (dead zone, response curve, reach).

## The wave (decided in step 3)

The wave is the key feature, with the surfer. It is a **parametric, physics-informed model, drawn as a small real 3D mesh** with a flat-shaded shader, inside the otherwise 2D game. It is not wave sprites and not a fluid simulation. (A first version drew the wave as a pure 2D shader. It looked flat, had no perspective down the line and its barrel read as a blob, so the wave body moved to 3D. Everything else stays 2D: sky, ridges, palms, surfer, spray, grading.)

- **Why:** sprites cannot change size or react to the surfer; a fluid sim is too heavy for a phone and cannot be art-directed. A model gives the shader its shape *and* gives gameplay an exact surface to ride, so the two cannot disagree.
- **Inputs:** size (height), hollowness (spilling to plunging), peel speed. Every shape is a function of the distance `d` to the **peel point** (where the wave is breaking right now): the wall builds ahead of it, the lip throws at it, the barrel opens and collapses into whitewater behind it. The surfer's `d` and their height up the face are their coordinates; the camera follows them, so a slower surfer is caught by the barrel and a faster one outruns the wave.
- **Real-world anchors:** peel speed is `Cb / sin(peel angle)`, and 30 to 50 degrees is rideable (below about 27 it is too fast). Steeper seabeds throw bigger, rounder barrels with thicker jets; gentle ones give small spilling waves. The lip is a ballistic jet that lands ahead of the crest. Scale follows the key frames (see Art direction): the surfer is about 0.26 of the screen height and the default wave face is about 1.7 times that.
- **Rendering:** `WaveModel` (`scripts/wave_model.gd`, in **meters**) builds the wave's cross-section at any `d` (`section(d)`, a `WaveSection` outline: back slope, over the crest, thrown lip, back under the lip as the barrel's roof, down the concave face to the trough). `WaveMesh` (`scripts/wave_mesh.gd`) sweeps about 54 stations (dense near the break) into an `ArrayMesh`. Vertex colour carries height fraction, foam, depth inside the barrel and thinness; UV is (metres along the outline, metres along the crest). `WaveStage` (`scripts/wave_stage.gd`) renders the mesh and a sea plane in a transparent `SubViewport` (MSAA 4x, a telephoto `Camera3D`, 21 degree lens, 19 m back, horizon at 0.40 of the screen height) and shows the result as a `TextureRect` layer between the ridges and the surfer. `shaders/wave3d.gdshader` (wave) and `shaders/water3d.gdshader` (sea) are unshaded spatial shaders that turn geometry into the key-frame look: 3 or 4 flat jade bands, warm rim line on steep edges, cell-edge veins, a glowing hollow, and cream/violet foam with a dripping edge. The model also bakes a 512 by 1 half-float profile texture (crest height, trough line, curl, foam by `d`) that the sea shader reads for the foam and shadow at the wave's base. Veins and foam clumps come from two small seamless noise textures generated once at load (`NoiseTextures`, about 40 ms). **The camera always looks down the line**: left from behind the surfer (yaw +30, easing to +24 on a full barrel), with the surfer right of centre (0.58 to 0.62 of the width), so the wave coming toward them fills the screen and the break stays at their back. It never swings round to look into the tube (changed in step 5). `world.gd` frames it so the surfer's feet stay at 0.70 of the screen height and the surfer is about 0.26 of it. Spray is described under "Wave motion and spray" below. The 2D surfer is a sprite, so the lip curtain cannot pass in front of them (a known limit).
- **Using it from gameplay:** `surface_point(d, u)` is a world position (x along the crest and equal to `-d`, y up, z toward the beach and the camera; u is 0 at the trough and 1 at the top of the face), `surface_normal(d, u)`, `crest_point(d)`, `lip_tip_point(d)`, `crest_height_at(d)`, `face_angle(u)`, `zone_at(d)`, `barrel()`, `peel_speed()`. `WaveStage.project(world_point)` turns any of those points into screen pixels, which is how the surfer, the spray and later the board's wake are placed in 2D. The scene's `world.gd` owns the surfer's `d` (`peel_offset`, in meters).
- **Tuning:** `WaveModel` constants (`MIN_HEIGHT`, `SHOULDER_MIN`, `COLLAPSE_LENGTH`, and so on) set the wave's character; `size` and `hollowness` are the two dials.

## Wave motion and spray (decided in step 5)

- **Anatomy** (from the surf-anatomy diagram: peak, crest, lip, barrel, face, shoulder, trough, whitewater, spray). `WaveModel` has a `peak_at` bump just ahead of the peel point, a shoulder that eases the wall all the way down to flat water (`SHOULDER_FLOOR`, `shoulder_length()` 30 to 46 m) while the face runs longer and gentler (`shoulder_at`, `trough_z_at`), a lip that builds up over `BUILD_LENGTH` (9 m), whitewater (`whitewater_at`) that carries on behind the break, `mist_at` (spray amount) and `lip_landing_point(d)` (where the spit happens).
- **The lip cycle.** `section_key(d, LipShape)` builds three shapes with identical topology and the same foot: LIFTED (stands up, pitching), THROWN (the steady model) and LANDED (fallen). `WaveMesh` keeps THROWN as the vertex positions, the other two in `CUSTOM0` (y, z of lifted, then landed), and (lip amount, whitewater amount) in `UV2`. `wave3d.gdshader` morphs between them with a phase `fract(time / lip_period + d / lip_spacing)`, so lips along the crest are at different points of the cycle and the pattern travels. Never rebuild the mesh for animation. The constants `LIP_PERIOD`, `LIP_SPACING` and `LIP_LANDING_PHASE` live in `WaveStage` and feed both the shader and the spit.
- **Face flow.** `UV.x` counts meters along the outline from the lip's tip (positive down the face, negative over the back); the shader scrolls the pattern toward the tip (`flow_speed`) and slides it along the crest (`slide_speed`). The whitewater heaves in the vertex shader. A fallen lip adds foam high on the face (`crash`).
- **Look** (key frame `kling-04`/`05` plus the later reference with a pale sun): emerald bands, the sun glowing yellow-green through the thin top (`wave_sunlit`, a mood colour), a crisp pale cell-edge network, and speckled cream-and-violet foam. The cell texture must stay `FRACTAL_NONE` (fractal layers smear it into marble).
- **Spray** (all flat white ovals, tinted by the mood): crest mist is a thin curtain mesh (`WaveMist`, `mist3d.gdshader`) inside the 3D stage; `WaveSpray` fires the lip spit from three points along the break as each lip lands; `SurferSpray` throws the signature fan with `burst(strength)` (0 to 1): 30 radial rays so it reads as spokes, a pool of 3 fans that can overlap, a back layer (fan body, wake) moved behind the Surfer and a front layer (fine edge droplets, splash) in front. `follow()` keeps it on the board's tail; `set_wake()` and `splash()` are ready for step 6. Temporary controls: S throws test bursts of rising strength, `?autoburst` does it every 2.4 s (for a phone).
- **Pitfalls found.** `Key` is Godot's keyboard enum, so the lip enum is `LipShape`. New `class_name` scripts need `godot --headless --import` once before they resolve. `UrlParams.has` calls JavaScript on the web build, so cache it, never ask every frame. Do not initialise a field with `X.new()` and then replace it in `_init`: the first one leaks.

## The surfer (decided in step 4)

A **sprite animation of an original character**: a lean, tanned surfer with bare torso, bright 80s board shorts (hot pink, aqua, yellow) and a rainbow-striped shortboard, seen from behind and slightly from the side, riding toward the screen's left. The frames come from **real surfing motion run through Kling's motion control**, so the movement is genuinely athletic. A jointed 2D rig and several image-generation routes were tried first and dropped (they looked stiff or drifted in style); `docs/sprite-pipeline.md` records every attempt, the working pipeline, its commands and costs. **Read it before adding or changing any animation.**

- **Catalog:** `SurferSprites` (`scripts/surfer_sprites.gd`) lists the animations (`ANIMATIONS`, `ORDER`, `LABELS`), the frame size, and the `ANCHOR` (the board's centre in frame pixels). Frames are `game/assets/sprites/surfer/<name>_NN.png`. Right now there is one animation, `ride` (35 frames, 12 fps, ping-pong).
- **Node:** `Surfer` (`scripts/surfer.gd`, an `AnimatedSprite2D` inside a `Node2D`). Its origin is the board's centre. `place(board_px, pixels_tall)` scales so a 1.8 m person is `pixels_tall` high (`STANDING_HEIGHT` is that many frame pixels); `set_ground_angle(degrees)` tilts the surfer to the wave face, which `world.gd` does from the slope under their feet (never past `MAX_GROUND_ANGLE`); `set_pose(name)` plays an animation (unknown names are ignored).
- **Adding an animation:** follow `docs/sprite-pipeline.md`: find a continuous shot of the move, capture frames, make a clip, run motion control, extract, then add the lines to `SurferSprites`. `tests/run_tests.gd` checks that every frame exists, has the right size and puts the board on the anchor.
- **Looking at it:** `?gallery` shows every animation in a grid plus a big cycler; `?pose=ride` and the P key choose the animation in the main scene (temporary until step 6 picks them from how the player rides).
- **Limits and next steps:** the colours are baked in (no mood tint yet); switching animations is a hard cut (add a 0.1 s cross-dissolve when step 6 starts switching); the surfer is a flat sprite, so the lip curtain cannot pass in front of them (step 7's tube moment needs a second render pass for just the lip); a goofy-foot option can mirror it with `scale.x = -1`.
- **Credits and sources:** Kling motion control cost 27 credits for a 3.3 s clip at 720p (about 8 per second, charged on submit, not shown first). Source footage is a reference only: it is never downloaded, committed or shipped (`storyboardimages/` and the scratch folder stay local), and the sprites show an original character.

## Tech

- **Godot 4.7.2 stable**, GDScript only, **Compatibility renderer** (the only one that exports to web), **single-threaded web export** (no COOP/COEP headers needed on Firebase Hosting). Android export may come later, so avoid web-only hacks where a plain Godot feature exists.
- All art is procedural to begin with (code, shaders, `Polygon2D`, `CPUParticles2D`, and one small 3D mesh for the wave) so it can be authored as text and iterated fast. Hand-made or generated sprites can replace pieces later. Do not add asset packs or addons without asking.
- Hosting: Firebase Hosting serves `build/web` (set in `firebase.json`). Pushing to `main` deploys live through GitHub Actions. The repo secret `FIREBASE_SERVICE_ACCOUNT` already exists. Never print it, read it, or commit a service-account JSON.

## Repo layout

```
CLAUDE.md                 this file
README.md                 human run / export / deploy notes
docs/progress.html        step tracker with copy-paste prompts (open by double-click, not deployed)
game/                     the Godot project (project.godot)
  scenes/ scripts/ shaders/ data/ tests/
tools/                    build, serve and preview scripts (PowerShell)
build/web/                export output (gitignored, this is what Firebase serves)
storyboardimages/         local-only reference photos (gitignored)
firebase.json  .firebaserc  .github/workflows/
```

## Commands (Windows, PowerShell)

Shortcuts that wrap the commands below: `tools\test.ps1`, `tools\build.ps1`, `tools\serve.ps1` (port 8060), `tools\preview.ps1 -Step N`. The browser pane can serve the build with `preview_start` using the `web` entry in `.claude/launch.json`. Headless runs print shader and script errors but still exit 0, so `tools\test.ps1` and CI scan the output for them. GPU-specific problems only show in the browser console, so check that too.

`godot` is on PATH only in a new shell. If it is missing, use `%LOCALAPPDATA%\Microsoft\WinGet\Links\godot_console.exe`. Use `godot_console`, not `godot`, for command-line runs. The GUI build swallows stdout on Windows.

```powershell
# a true-colour screenshot (see Gotchas: the browser pane distorts colour), plus the average frame time
.\tools\capture.ps1 -Out shot.png -Size 0.6 -Hollow 0.5 -Peel 3 -Mood sunset -Pose ride
# several moments in one run (-Snaps saves out-60.png and so on) and a spray burst at a frame (strength@frame)
.\tools\capture.ps1 -Out shot.png -Frames 160 -Snaps '70,90,110' -Burst '1.0@60'
# the pose gallery in one image
.\tools\capture.ps1 -Out gallery.png -Gallery -Resolution 1920x1080
# the same with vsync off, to measure what the GPU can sustain (also -Resolution 1920x1080)
.\tools\capture.ps1 -Out shot.png -Perf -Frames 240

# tests and parse check (must pass before saying anything works)
godot_console --headless --path game --script res://tests/run_tests.gd

# web export (needs the 4.7.2 export templates installed, and an export preset named "Web")
godot_console --headless --path game --export-release "Web" ../build/web/index.html

# serve the export locally, then open http://localhost:8060
python -m http.server 8060 -d build/web

# open the editor
godot --path game --editor

# temporary preview URL on Firebase (expires in a few days), used to check a step on a phone
firebase hosting:channel:deploy step-N --project chabruh-surf --expires 7d
```

Export templates must match the editor version exactly (4.7.2.stable), in `%APPDATA%\Godot\export_templates\4.7.2.stable\`.

## How to work (the step loop)

0. Work for step N happens on branch `step-N`. `main` is the live site and only changes when the user says Done.
1. **Plan first.** Before changing any files, post a short plan: files you will touch, the approach, and how you will verify it. Wait for the user's OK.
2. Build the smallest complete version of the step. Surgical edits, no speculative abstractions, no unrelated refactors.
3. **Verify for real.** Run the headless tests. Export the web build. Serve it, open it in the built-in browser pane, and take screenshots (compare against the references above). Read the browser console for errors. Say exactly what was and was not tested. Never claim something passed that you did not run.
4. Deploy a Firebase preview channel `step-N` and give the user the URL plus the verify checklist from the tracker. Stop there. The user decides when a step is done.
5. On "Done with step N": re-run the tests, set that step's `status` to `"done"` in `docs/progress.html`, commit on `step-N`, merge it into `main` (fast-forward), push `main`, confirm the GitHub Action succeeded and the live site works.

## Code conventions

- Typed GDScript (`var speed: float`), `snake_case` files and functions, `PascalCase` classes.
- One script per scene or node. Small functions. Comments explain *why*, never *what*.
- Anything that affects feel is a named constant or `@export` var, and the feel dials live in one tuning resource. No magic numbers.
- Colours come from the `Palette` autoload, never as scattered hex literals. The look is a set of **moods** (`MoodData` resources defined in `palette.gd`: golden, sunset, neon) that cross-fade. A shader uniform with the same name as a `MoodData` property is fed automatically by `world.gd`. To add a colour: add the property to `MoodData`, give it a value in every mood, and declare a uniform of that name.
- Scene layout: the 2D layers are in height units (1.0 is the screen height, x runs 0 to the aspect ratio), so shapes keep their proportions on any screen. The 3D wave stage is in meters (the surfer is 1.8 m); `WaveStage.project()` converts a world point to screen pixels.
- Keep per-frame work cheap (target 60 fps on a mid-range phone). Prefer shaders and `CPUParticles2D` over per-frame node churn.
- Size budget: the engine's `index.wasm` is about 38 MB raw (measured on 4.7.2), so judge by *transferred* size, not file size. Keep everything a player downloads under about 25 MB over the wire, and keep our own `index.pck` small (under about 10 MB). Measure with `curl -H "Accept-Encoding: br,gzip" -sI <url>` or the browser network panel.
- Free anything you instantiate in headless tests (`queue_free()` / `free()`), or Godot prints leak warnings at exit.

## Gotchas

- Browsers block audio until the first user gesture. Start sound after the first tap or click.
- Godot web needs `touch-action: none` and `overflow: hidden` on the page, or touch drags scroll the page. Use a small custom HTML shell if needed.
- Name the export `index.html`.
- The scene is fill-rate bound. Measured on an Intel Arc 140V laptop GPU with vsync off: 417 fps at 1280x720, 172 at 1920x1080, about 89 at 2560x1440, so roughly 3 ms per megapixel for the old flat 2D wave. The 3D wave of step 3 is cheaper: 2.0 ms at 1280x720, 4.6 ms at 1920x1080 and 8.7 ms at 2560x1440 for the big barrel (`tools\capture.ps1 -Perf`). The old figure came from (`godot_console --path game --rendering-driver opengl3 --disable-vsync --print-fps --resolution 1280x720 --quit-after 600`). A phone at 3x density would draw about 3.6 megapixels, so `web/shell.html` caps `devicePixelRatio` at 1.5 (`?dpr=` overrides it). Budget new full-screen layers against this.
- Scripts with a `class_name` that `tests/run_tests.gd` refers to (like `Surfer` and `PoseGallery`) are compiled before the autoloads exist, so they must not name `Palette` directly. Use `get_node("/root/Palette")`. Scripts that are only loaded through a scene (like `world.gd`) can name it.
- `WaveStage.rebuild()` (the mesh sweep, in GDScript) costs about 15 ms on a laptop CPU, measured by changing the wave every frame for 200 frames. That is fine while a slider or key is held, but steps 5 and 7 must not rebuild every frame: change the wave in steps a few times a second, or move the work into the shader.
- The browser pane throttles `requestAnimationFrame` to about 30 fps, or stalls it, whenever it is hidden, so in-pane frame rates are only valid while the pane is visible. Prefer the desktop `--print-fps` run above for performance numbers.
- `--script` test mode does not register autoloads as global names; reach their code through `preload("res://scripts/palette.gd")`.
- Do not judge colours from browser-pane screenshots. The display is wide-gamut and the capture is colour-managed, so everything looks washed out (a plain CSS `#E8559A` swatch captures as `#CF6299`). Use `tools\capture.ps1`, which runs the game in a real window and saves the true pixels, and compare that with the key frames. It is also much faster than exporting: it runs straight from the project.
- The Compatibility renderer (WebGL2) supports fewer features than Forward+. Test every shader and effect in the web build, not just the editor.
- The old `.firebaserc` project is `chabruh-surf`. `firebase.json` must serve `build/web`, never the repo root (that would publish the source and the reference photos).
