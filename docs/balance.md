# Balance: how the surfer stays over his board (step 10, second pass)

The first pass of step 10 turned the board with a stiff spring and welded the body to it, so the board flicked and the body
tipped with it ("in real life he would just fall off"). This pass makes balance the core of every move. The J-Bay clip
(`storyboardimages/jbay_refs/jbay_source_1080p.mp4`, local only) is the reference; `ride_cycle/` next to it holds crops of
0 to 4.1 s at 10 frames a second (bottom turn, climb, top turn, down again).

## What the footage shows

- **The body is the steady part.** Across one cycle the board's axis swings through about 150 degrees (measured from the
  colour of the board in each crop: level in the drive, 60 degrees nose up on the climb, past vertical nose down after
  the snap) while the torso stays within about 25 degrees of upright in the picture. The legs take up the difference.
  From 15.4 to 18.6 s the same: the board goes vertical, flips at the lip and drops vertically under an upright body.
- **Turn rates.** A bottom turn is slow, about 1 rad/s (53 degrees in 0.9 s). The top turn is sharper, 2 to 3 rad/s,
  because the board is light at the lip and gravity helps.
- **Crouch rhythm.** Deepest (hips near knee height, chest folded over the front knee) on the way into the bottom turn;
  extends through the turn; tallest early on the climb; folds again near the lip; extends through the snap; folds on
  the way down. Fold when light, extend against the pull of a turn: the same rhythm pumps a board.
- **Arms.** Low and forward in the drive; wide like wings as he extends out of the bottom turn and up the face; in the
  top turn the back arm is thrown high and the front arm reaches down and forward.

### The lead chain (third pass: the user's notes and Ethan Ewing, "Seamless Technique", youtube.com/watch?v=dgJ4zDv3SoM)

Viewed in the browser pane, not downloaded. Two clean cycles, 2.2 to 6.6 s and 12.2 to 14.4 s:

- **The front (left) arm starts every move.** It points where he is about to go and the head looks there with it; the
  chest follows, then the hips, then the board. At the lip (3.8 s, 13.2 s) the front hand and the head point down the
  wave before the board has come round; in the snap (4.0 s, 13.4 s) the chest has swung round with the arm.
- **The back (right) arm is the anchor.** Its forearm stays along the board with the hand pointing the way the board
  flows; it is thrown out behind as a counterweight while he extends (12.4 to 12.8 s) and goes over his head with the
  forearm horizontal, along the board, at the lip (3.8 s, 13.2 s, and the user's photo 3).
- **A big bottom turn is very deep.** Head down by the hips, back rounded (3.0 to 3.2 s, the user's photo 4); the
  front hand reaches toward the water ahead, and the back hand trails in the water and throws spray (the user's note).
- **Hitting the lip.** Only the tail is in the water, so the board pivots from nearly straight up to straight down in
  about half a second while his body stays over it.
- **A floater.** Both arms push forward over the nose while the board goes weightless.
- **A stall.** Steering back, weight goes over the tail, the nose lifts, he slows and the curl catches up; the deeper
  face near the curl then sends him off again.

### Cutbacks, lip hits and pumping (fourth pass)

Downloaded with the owner's OK to `storyboardimages/ewing_bells/` (Ethan Ewing at Bells, youtube.com/watch?v=AE2isQXw3u0),
`storyboardimages/lip_slowmo/` (slow-motion lip hits from 52 s, r7hQpnmkn7w) and `storyboardimages/pump_slowmo/` (300 fps,
g-C25diaMaM); local only. Seeking in these files is slow, so read them in one decoding pass.

- **Cutback (Bells 0.8 to 3.4 s and 7.6 to 9.8 s).** Climb to the lip with the back arm out behind; at the lip the back
  arm goes over the head; the snap throws the fan and the chest turns to face the beach, front arm pointing down toward
  the curl; the board comes round about 150 to 180 degrees to face the whitewater while he is very compact, knees
  almost touching, arms low; then the foam pivots the board back (about 0.4 s) and he rides back down the line,
  crouched, arms low and forward. About 2 s from the lip back to the line.
- **Lip hits (slow motion 51.6 to 57.5 s).** The back arm straight up, the front arm out toward where the snap goes, the
  fan erupting off the rail along the lip from the middle and front of the board as well as the tail; the board swings
  nose down while he compresses.
- **Pumping (300 fps, 74 to 97 s).** About 1.3 s a pump: fold low (head over the front knee, arms low and forward) as
  the board drops a little, extend tall with the arms spreading as it rises.
- **The user's notes.** He looks at a spot one or two boards ahead of the nose, up the face in a bottom turn, never down
  at the water; the back foot sits where the aqua stripe meets the white tail and the front foot where orange meets
  yellow; on a floater the back arm reaches out behind for balance and the board rides on top of the wave; in the
  barrel he makes himself small, both arms forward and the knees together.

## The model (`scripts/rider.gd`, `scripts/surfer_3d.gd`)

- **Balance is the apparent gravity.** The board's acceleration minus gravity, as a direction from the feet to the
  centre of mass (`Rider.balance`). Riding down the line it is upright; heading straight up or down the face it is
  square to the face (the climb the user described: "normal to the climb, applying pressure to the board"); in a
  bottom turn it leans into the wave, in a top turn out toward the beach. Along the board only water drag and pumping
  tilt it (gravity along the slope, and the arcade drive that stands in for it, move body and board alike).
- **The lean leads, the turn follows.** The input sets a heading to aim for; the turn that needs is turned into the lean
  that holds it (`lean`, from the face's normal), and the centre of mass moves there on a spring at human speed
  (`lean_response`, `lean_rate_max`). The board then carves only as tight as that lean holds:
  `omega = (press * tan(lean) - g * s.y) / v`. So the turn rate is as smooth as the body whatever the input.
- **Snaps pivot.** When the board is light (cresting), high on a face too steep to carve against, or at the lip
  (`LIP_FROM` to `LIP_FULL`, whatever the load: only the tail is in the water) he stays close to the lean that holds his
  line and swings the board round on its tail instead (`pivot_share`), up to `snap_omega` (5.5 rad/s, `SNAP_GAIN`
  per radian still to turn); his body follows only the carving part. Near the top the heading only eases level over
  the last `TOP_EASE` of the face, so he can drive up nearly vertically before he hits the lip.
- **Power bottom turns.** Deep and low, the rail is buried and holds a tighter turn (`BURIED_GRIP`), and a carve may
  lean up to `carve_max` (1.15 rad) past the lean that holds his line: about 2.5 to 3 g at the bottom. The arcade drive
  no longer chases the curl harder than `DRIVE_CAP` times trim speed on steep headings, so he is not too fast to come
  round, and he may point anywhere in the pocket (only inside the barrel, `ROOM_FROM`, is he held along the line).
- **Stall.** Steering behind the pocket while ahead of where he is steered stalls him (`stall`, `stall_drag`): the
  drag leans him back over the tail (pitch, up to 20 degrees) and `Surfer3D` lifts the nose (`NOSE_LIFT`). He can fall
  back to `D_NEAR` (3 m behind the peel point, inside the barrel on a hollow wave).
- **The lead chain in `Surfer3D`.** The front arm points along `Rider.aim` (the heading he is asked for, a little down
  the wave) within about 60 ms, the head within 90 ms (yaw with `lead`, and a nod down when the arm points down), the
  chest within 220 ms; the rider's lean (about a quarter of a second) and then the board follow. The back arm blends
  between its anchor (forearm along the board), wings (out behind), top (over the head), drag (down to `DRAG_POINT` in
  the water, which also throws spray through `SurferSpray.set_hand_drag()`) and floater (forward). In the heart of a
  deep bottom turn the spine folds over (`FOLD_MAX`) so the head drops toward the hips.
- **Board and body are separate.** The board lies flush on the face and rolls onto its rail by part of the turning lean
  (`rail_share`, `trim_rail`, `rail_max`); positive roll puts the wave-side rail down. `Surfer3D` tilts the whole body
  about the point between the feet so the pose's own centre of mass sits along `balance` (a hip-hinged pose is tilted
  less: its hips go back), sinks the hips with compression (`HIP_SINK`), and the leg solver keeps the feet planted.
- **Cutback.** Near the top (`CUT_FROM`) a hard push down (the stick past `CUT_PUSH` and still shoved at `CUT_SHOVE`) lets
  the heading carry on past straight down to `CUTBACK_REACH`, pivoting on the tail the whole way and skidding speed off
  (`PIVOT_SKID`); past `CUT_TURNED` (or low on the face) the stick is pulled back over `REBOUND_TIME` and the board
  pivots back to the line; above `CUT_DONE` he rides on as usual. Round, he is very compact (`round_back` crouch, knees
  together in `Surfer3D`).
- **Pumping.** Behind where he is steered (`PUMP_SLACK`, `PUMP_RANGE`) he pumps: a `PUMP_PERIOD` rhythm of small turns
  (`PUMP_SWING`, folded into the stick so it also feeds the pump's speed) with the crouch folding as the nose goes down.
- **Where he looks.** `Surfer3D._aim_head()` turns the neck and head last, so the face (the head bone's +Z) points at a
  spot `LOOK_AHEAD` ahead of the nose along the heading he is asked for, whatever the torso is doing.
- **Board under him.** The board sits `BOARD_SHIFT` forward; the spray comes off its real tail (`tail_point()`) and, at
  the top of the wave, a second fan off the front foot (`world.gd`, `FRONT_SPRAY_FROM`, `FRONT_SPRAY_SHARE`).
- **Floater and barrel.** On a floater the board lifts toward the crest (`FLOAT_LIFT`) and levels (`FLOAT_LEVEL`); the
  front arm pushes forward and the back arm reaches out behind. In the tube both arms go forward and the knees together.
- **Crouch.** `0.15 + 0.2 * speed + 0.45 * nose_down + 0.35 * round_in_a_cutback + pump + rhythm + barrel`, where the rhythm integrates "light, the face's
  curve pushing up, and the first half of a turn (absorb), minus the second half of a turn as the nose comes up (push
  through it)" with a short memory, so he is deepest in the heart of a bottom turn and extends out of it.
- **Smoothness fixes found on the way.** The face normal was constant along each outline segment and jumped at every
  point (it now blends between point normals); `Surfer3D` was stepped twice a frame; Godot's `get_bone_global_pose()`
  lags a frame behind `set_bone_pose_*()`, so the solvers worked from last frame's joints (`Surfer3D._global()` now
  composes the chain itself); the face's ends are cushioned and the guardrails start while there is still time to turn.

## Fifth pass: controls and flow (the user's notes)

What the user saw, reproduced first with scripted wheel input (a scratch rider simulation, 60 steps a second):

- **"Scroll down and he ricochets back really fast."** Idle, the draw carries him up the face; a quick spin of the wheel
  near the top then met the cutback's trigger, the board pivoted round in half a second and the drive pushed him back
  toward the curl: from 3 m ahead of the peel point to 3 m behind it in 0.6 s (13 m/s), stopped dead at the end of the
  range. Now a cutback needs room on the shoulder (`CUT_ROOM`, 5 m); nearer the curl the same push is a snap. Closing
  on the curl is soft-limited (`BACK_MAX`, the peel speed) and eases to a stop over `CURL_CUSHION`; the drive does
  nothing pointed back toward the curl. The same spin now: snap at the lip, a drop at about 70 degrees, a 2.7 m slide back.
- **"At the top he should change direction completely, not on the way back down."** The scroll's virtual stick faded
  in about half a second, so the bottom turn never finished (he climbed at 27 degrees) and the pivot ran from the top
  to mid face. Now: a push holds once the gesture stops until the board has turned to it or the face has run out that
  way (`stick_hold`), a full push points the board fully the way it was pushed (`STICK_FULL`), a climb steeper than
  `CLIMB_COMMIT` is committed to the lip, and at the lip a reversal commits to a snap (`snapping`): the lip holds the
  tail while the board pivots from up the face to down it (`SNAP_GAIN`, `SNAP_ACCEL`, `snap_omega` 6.5), and he drops
  once the nose is round. In the scripted lip hit he climbs to about 52 degrees on the default wave and the board goes
  from +47 to -42 degrees while he stays at 0.95 to 0.96 up the face. Nearly weightless there, his body stays near
  upright while the board goes vertical (`LIGHT_UPRIGHT`), as in the footage.
- **"Driving back into the curl, he should tuck, get oriented, get his balance and get back to normal."** Near the curl
  (`SETTLE_FROM`) he tucks (`tuck`, a deeper crouch, knees together), steers for a settling height (`SETTLE_HEIGHT`, lower
  in a barrel) and the heading is held along the line, then the drive takes him back to where he is steered.
- **"Too far out in front, the new wave physics."** Down the shoulder the face relaxes and the water's draw and the
  wave's push fade (`WaveModel.draw_at`, `power_at`); the drive and pumping work off that push. Steered all the way
  ahead he runs out to about 15 m, slows from 11 to under 8 m/s and the curl comes back to him; a cutback there brings
  him back to the pocket: carved round on the rail (`CUT_PIVOT`), bleeding speed (`CUT_DRAG`), and the foam pivots the
  board back to the line before he reaches it (the rebound looks ahead by his closing speed).
- **Spray at the top.** Bursts no longer lock out for 0.45 s after the first: each time the turn bites harder another
  goes, so the snap at the lip throws the biggest fan, aimed up and back over the crest (`Rider.spray_dir`).

Scripted checks in `tests/run_tests.gd`: the whole snap happens at the top (above 0.88 when the nose has come round),
a pocket push is a snap and never closes on the curl faster than the soft limit, a shoulder cutback rebounds still
ahead of the peel point, stalling back to the curl eases to a stop, settled by the curl he is tucked and along the
line, one flick carries him to the lip, and steered far out the soft shoulder slows him.

## Too jerky to ride (debug)

He never falls (no hard fail), but `Rider.strain` says when a real surfer would have: the centre of mass more than 0.7
rad behind where the input wants it, the input swinging the wanted lean faster than 4 rad/s, or more than 3 g. The H
readout shows it in red with the reason and a count. Measured with `tests` patterns: a 3 s carve (the footage's rhythm)
never trips it; a scroll notch every quarter second is absorbed (small twitches are fine); full reversals every 0.15 s,
or saturating the stick and reversing it inside a quarter second, trip it. Use it to tune the step 11 controls so
ordinary hands stay under 1, rather than making the physics follow bad input.

| input (scripted, 60 fps, 8 s) | before: peak turn change, rail change | after |
| --- | --- | --- |
| smooth 3 s carve | 16.8 rad/s², 6.3 rad/s | 4.8 rad/s², 1.1 rad/s |
| drop 1 s then climb | 97 rad/s², 42 rad/s | 6.0 rad/s², 1.6 rad/s |
| a scroll notch every 0.25 s | 14.9 rad/s², 4.6 rad/s | 0.8 rad/s², 0.3 rad/s |
| hard reversals every 0.15 s | 44.6 rad/s², 14.7 rad/s | 3.3 rad/s², 1.4 rad/s |

## Judging it against the footage

```powershell
.\tools\capture.ps1 -Out ride.png -Frames 430 -Carve 3 -Surfer3d yes -Snaps (( 60..420 | ? { $_ % 12 -eq 0 }) -join ',')
tools\foundry\.venv\Scripts\python.exe tools\foundry\refs\ride_sheet.py ride ride-sheet.jpg
tools\foundry\.venv\Scripts\python.exe tools\foundry\refs\ride_sheet.py ride ride-vs-footage.jpg --ref storyboardimages\jbay_refs\ride_cycle "drive:5:348" "bottom turn:15:372" "climb:18:228" "top turn:29:108" "down again:40:120"
```

Captures now run at a fixed 60 frames a second of game time (`--fixed-fps 60`), so a frame number is always the same
moment of the ride. `-Carve 3` scrolls up and down smoothly once every 3 s; `-Ride cycle` drops, bottom turns, drives
up and hits the lip every 4.4 s; `-Ride stall` steers hard back for 3 s, then lets go; `-Readout` shows the debug line.
`-Ride cutback`, `-Ride chase` (pumping) and `-Ride floater` show the fourth pass. The track file also records `stall`
and `hand_spray`. In the game, `,` and `.` slow everything down or speed it up (0.5x to 2.5x); the speed is always shown
in the top right corner so it appears in screenshots, and `?speed=1.3` starts the web build at that speed.

## Not yet

- Our camera sits behind him, so a fold toward the wave reads as a hunch rather than the footage's side-on fold.
- The arcade drive still keeps his speed up on a climb (now capped on steep headings), so he reaches the lip faster
  than in the footage; step 11's controls and a look at the drive belong together.
- The back forearm over the head at the lip is hard to read from our camera behind him.
- Spray strength still comes from turn rate; a snap's tail release could drive it directly.
