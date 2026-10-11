# Chabruh

A laid-back 2D surfing game about the feel of riding a wave. No enemies, no points, no timers. It runs in the browser on a phone (landscape) or desktop.

Live: https://chabruh-surf.web.app

The project rules and art direction are in [CLAUDE.md](CLAUDE.md). The build plan is [docs/progress.html](docs/progress.html) (open it by double-click).

## What you need (Windows)

- [Godot 4.7.2](https://godotengine.org) with the matching **export templates**: `winget install -e --id GodotEngine.GodotEngine`, then in the editor, Editor > Manage Export Templates > Download and Install.
- Python 3 (only to serve the build locally), Node and the Firebase CLI (only to deploy a preview).

Open a new terminal after installing so `godot` is on your PATH. The scripts below also find it in the WinGet folder.

## Everyday commands

Run these from the repo root in PowerShell.

| Do this | Command |
| --- | --- |
| Run the tests | `.\tools\test.ps1` |
| Build the web export to `build/web` | `.\tools\build.ps1` |
| Play it at http://localhost:8060 | `.\tools\serve.ps1` |
| Deploy a temporary preview link | `.\tools\preview.ps1 -Step 1` |
| Open the editor | `godot --path game --editor` |
| Save a true-colour screenshot | `.\tools\capture.ps1 -Out shot.png -Size 0.6 -Hollow 0.5 -Peel 3 -Mood sunset -Pose ride` |
| Save the pose gallery | `.\tools\capture.ps1 -Out gallery.png -Gallery -Resolution 1920x1080` |
| Measure the frame time (vsync off) | `.\tools\capture.ps1 -Out shot.png -Perf -Frames 240 -Resolution 1920x1080` |

## Wave controls (temporary, until steering arrives in step 6)

- **Sliders** for size, hollow and peel: add **`?debug`** to the URL or press **D**. They work with a finger. *Size* is how big the wave is, *hollow* goes from a spilling wave to a barrel, and *peel* slides the surfer along the wave, in meters ahead of the break (high is far ahead on the open shoulder, near zero or negative lets the break catch up and puts them under the lip, where a hollow wave has its barrel).
- **Arrow keys**: up and down change the size, left and right slide the surfer along the wave. **`[` and `]`** change hollowness. **R** resets.
- **`?size=0.8&hollow=1&peel=-1`** on the URL start the wave in that state (size and hollow from 0 to 1, peel in meters from -10 to 20).

## Surfer animations (temporary until step 6)

- **`?gallery`** on the URL: every animation in a labelled grid against the wave's colours, plus a big cycler. Tap or click, or use the left and right arrow keys, to step through; space pauses.
- **`?pose=ride`** on the URL starts the surfer in an animation, and **P** steps through them in the main scene. There is one so far, `ride`.
- Try the barrel with **`?size=0.9&hollow=1&peel=1`**. New animations are made with the pipeline in `docs/sprite-pipeline.md`.

## Look controls (temporary)

- **M**, or a click or tap anywhere: cycle the mood (golden hour, sunset, neon dusk). It cross-fades over 1.5 seconds.
- **`?mood=golden`**, **`?mood=sunset`** or **`?mood=neon`** on the URL: start in that mood.
- **`?fps`** on the URL, or the backtick key: show the frame rate.
- **`?dpr=2`** (sharper) or **`?dpr=1`** (fastest): the page caps its render density at 1.5 by default, because the scene costs about 3 ms per megapixel on a laptop GPU. Use this to compare on a phone.

## How it ships

- `firebase.json` serves only `build/web`. Source, docs and reference photos are never published.
- Pushing to `main` runs `.github/workflows/firebase-hosting.yml`: it imports the project, runs the tests, exports the web build in a Godot container, and deploys to the live site.
- Running that workflow by hand on any other branch (`gh workflow run firebase-hosting.yml --ref <branch>`) deploys to a throwaway channel called `ci-test` instead.
- The workflow needs the repo secret `FIREBASE_SERVICE_ACCOUNT`. Without it, the deploy step skips cleanly.
- The web export is single-threaded, so no special server headers are needed.

## Layout

```
game/        the Godot project (project.godot)
tools/       PowerShell scripts for test, build, serve, preview
docs/        the build tracker
build/web/   export output (not committed)
```
