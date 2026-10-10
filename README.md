# Chabruh

A surfing game about feel. No points, no collectibles: sit in the lineup, wait for a set, and try to stay in the pocket of a peeling barrel.

Runs in the browser (phone in landscape, or desktop). Android comes later.

## Play locally

Any static file server works, for example:

```
npx http-server -c-1 .
```

then open `http://localhost:8080`. three.js loads from jsDelivr, so you need a network connection.

Handy URL flags (put them after `#` or `?`):

- `quick` waits a few seconds between sets instead of 45 to 60.
- `debug` shows speed, position in the wave and frame rate (or press the backtick key).
- `bot` lets an autopilot surf, for testing.

## Controls

Ride it like a fingerboard. Rest two fingers (index and middle) close together anywhere on the screen and slide them; only the movement counts, so keep them low and out of the way of the surfer. The little board at the bottom shows what your fingers are doing.

- Up and down: carve up and down the face. Rock up and down to pump.
- Toward the direction you are riding: weight on the front foot, nose down, more speed.
- Away from it: weight on the back foot, stall (get deeper in the barrel).
- Back and up hard at speed: stomp the tail and snap, or swing into a cutback.

Keyboard: arrow keys (or WASD), hold Shift to push harder.

Too far out on the shoulder and the wave loses its push and rolls through. Too deep behind the curl and the lip lands on you.

## How it works

- `src/waveProfile.js` describes the breaking wave as one cross-section curve per position along the crest. The curve runs from flat water, up the face, over the tube ceiling, around the lip and down the back, so the same mesh goes from swell to barrel to whitewater as the break stage changes along the peel.
- `src/waveMesh.js` builds that mesh; `src/water.js` shades it (sky reflections, light through the thin lip, detail normals that flow up the face, foam) and draws the open ocean with Gerstner swell.
- `src/physics.js` rides the surfer on the face in the peel's frame: gravity along the slope, board grip, drag, pumping, tail stalls, pivots, airs and floaters.
- `src/sky.js` is the Preetham sky, also baked to a cube map for reflections.
- `src/surfer.js` poses a rigged human (`assets/surfer.glb`, the Mixamo X Bot from the three.js examples, recoloured as a wetsuit) with procedural IK; `src/particles.js` and `src/audio.js` are spray and mist, and procedural ocean sound.

`node tools/build-artifact.mjs` writes `dist/artifact.html`, a copy of the page without the document wrapper for hosting as a claude.ai Artifact.
