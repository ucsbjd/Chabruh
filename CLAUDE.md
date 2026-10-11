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

Starting palette (a first guess, tune freely, but keep it in one place, the `Palette` autoload):

| Role | Colours |
| --- | --- |
| Sky, top to horizon | `#2B1B5E` `#7B3FA0` `#E8559A` `#FF9A6B` `#FFD79A` |
| Sun | `#FFE3A3` with `#FF7A8A` stripes |
| Wave face, light to deep | `#7AF2E0` (light through the lip) `#19C9C0` `#0B7C8C` `#25306B` (shadow) |
| Foam and spray | `#FFF4E6` lit, `#C7A8E0` in shade |
| Neon gear | lime `#C6F135`, pink `#FF3D8B`, ink `#1B1730` |

Look-and-feel is **flat-shaded vector style, not pixel art**. A pixel-crunch/dither pass may come later as an optional toggle. Do not add it unless asked.

### Storyboard references (`storyboardimages/`, local only, copyrighted, never commit or deploy)

12 photos and stills. What each is for:

- `images (1).jpg`: 80s surfer in a neon lime and black wetsuit walking out carrying a board with a bold red graphic. Costume and board look, and the paddle-out intro.
- `images (2).jpg`: low carving turn on a teal face, arms wide, board on its rail, spray fanning behind.
- `images (3).jpg`: deep crouch against a huge green wall with a white lip curtain behind. Barrel framing.
- `images (4).jpg`, `(5)`, `(6)`, `(9)`: snap and top turns with a big radial fan of spray thrown off the tail. **This is the signature effect.** The fan is a wide arc with fine droplets at the edge, much bigger than the surfer.
- `images (7).jpg`, `(8)`: airs and vertical snaps, board nearly upright, one or both arms up.
- `images.jpg`: Vice City style sunset art with palms and pastel buildings. Palette and mood.
- `licensed-image.jpg`: glassy turquoise barrel at golden hour with light glowing through the lip. A tiny surfer inside the tube.
- `licensed-image (1).jpg`: Teahupoo-style barrel, surfer crouched low in the pocket, trailing a hand on the wall.

The surfer is seen mostly from behind and slightly from the side. Several storyboard photos show the front, so mirror the idea of each pose (arm shapes, crouch depth, board angle), not the camera angle.

Poses the surfer needs: walk-in with board, prone paddle, pop-up, trim stance, bottom turn crouch, top turn snap (with arms), cutback, deep barrel crouch with hand-drag, air (board vertical, arms up), floater, soft wipeout tumble.

## Game concept

- Side view, as if shot from the beach. The default surfer rides **right to left** across a long peeling wave, **regular stance (left foot forward), frontside**: back to the camera, chest toward the wave face. The curl, lip and barrel are behind the surfer (right of them) and the open shoulder is ahead (left). The camera follows, so the scenery slides left to right. The world is authored for this default; a mirrored goofy-foot option can come later.
- Two axes the player controls: **position along the wave** (ahead of or behind the curl) and **height on the face** (low for bottom turns, high for top turns and snaps). Speed comes from the slope and from pumping up and down the face.
- Too far ahead: the wave shoulders out and you slow down. Too far behind: the lip lands on you (soft wipeout).
- Spray scales with speed times how sharply you turn. Top-of-the-wave snaps throw the big fan. Air and hang-time matter. The tube is the calm, glowing reward.
- Controls: desktop, mouse X steers along the wave and the mouse wheel sets height on the face (arrow keys / WASD as a fallback). Mobile, two-finger drag: horizontal steers, vertical changes height. Smooth and clamp everything. Never let the wheel scroll the page.
- Forgiving by default. Expose feel dials in one tuning resource (dead zone, response curve, reach).

## Tech

- **Godot 4.7.2 stable**, GDScript only, **Compatibility renderer** (the only one that exports to web), **single-threaded web export** (no COOP/COEP headers needed on Firebase Hosting). Android export may come later, so avoid web-only hacks where a plain Godot feature exists.
- All art is procedural to begin with (code, shaders, `Polygon2D`, `CPUParticles2D`) so it can be authored as text and iterated fast. Hand-made or generated sprites can replace pieces later. Do not add asset packs or addons without asking.
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
- Scene layout: everything is in height units (1.0 is the screen height, x runs 0 to the aspect ratio), so shapes keep their proportions on any screen.
- Keep per-frame work cheap (target 60 fps on a mid-range phone). Prefer shaders and `CPUParticles2D` over per-frame node churn.
- Size budget: the engine's `index.wasm` is about 38 MB raw (measured on 4.7.2), so judge by *transferred* size, not file size. Keep everything a player downloads under about 25 MB over the wire, and keep our own `index.pck` small (under about 10 MB). Measure with `curl -H "Accept-Encoding: br,gzip" -sI <url>` or the browser network panel.
- Free anything you instantiate in headless tests (`queue_free()` / `free()`), or Godot prints leak warnings at exit.

## Gotchas

- Browsers block audio until the first user gesture. Start sound after the first tap or click.
- Godot web needs `touch-action: none` and `overflow: hidden` on the page, or touch drags scroll the page. Use a small custom HTML shell if needed.
- Name the export `index.html`.
- The scene is fill-rate bound. Measured on an Intel Arc 140V laptop GPU with vsync off: 417 fps at 1280x720, 172 at 1920x1080, about 89 at 2560x1440, so roughly 3 ms per megapixel (`godot_console --path game --rendering-driver opengl3 --disable-vsync --print-fps --resolution 1280x720 --quit-after 600`). A phone at 3x density would draw about 3.6 megapixels, so `web/shell.html` caps `devicePixelRatio` at 1.5 (`?dpr=` overrides it). Budget new full-screen layers against this.
- The browser pane throttles `requestAnimationFrame` to about 30 fps, or stalls it, whenever it is hidden, so in-pane frame rates are only valid while the pane is visible. Prefer the desktop `--print-fps` run above for performance numbers.
- `--script` test mode does not register autoloads as global names; reach their code through `preload("res://scripts/palette.gd")`.
- Do not judge colours from browser-pane screenshots. The display is wide-gamut and the capture is colour-managed, so everything looks slightly desaturated (a plain CSS `#E8559A` swatch captures as `#CF6299`). Godot's canvas matched CSS in a side-by-side check, so trust the values in `Palette` and judge shape, contrast and mood from screenshots.
- The Compatibility renderer (WebGL2) supports fewer features than Forward+. Test every shader and effect in the web build, not just the editor.
- The old `.firebaserc` project is `chabruh-surf`. `firebase.json` must serve `build/web`, never the repo root (that would publish the source and the reference photos).
