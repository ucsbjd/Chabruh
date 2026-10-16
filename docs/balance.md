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

## Sixth pass: the rhythm of a turn off the top (timing from the Bells footage)

The user's notes: going up for a cutback he should accelerate up, come to a stop at the top where all the energy goes
into the cutback and a giant spray, then float down. Instead he did the cutback and then accelerated down the middle of
the face, so the most energy was on the way down. `docs/updated_physics_reco_ARGO.md` (an outside AI's spec) proposed
a fix; section 7c of `docs/wave-and-spray-model.md` says what of it went in and why.

### What the footage shows (Bells, `storyboardimages/ewing_bells`, decoded once at 12 fps)

Six turns off the top (0.5 to 3.7 s, 4.0 to 7.0 s, 7.3 to 9.8 s, 15.0 to 18.3 s, 46.0 to 49.5 s, 50.0 to 53.0 s):

| phase | time | what happens |
| --- | --- | --- |
| bottom turn | 0.3 to 0.6 s | deep crouch, rail spray low on the face |
| climb | 0.3 to 0.5 s | from the foot of the face to the lip, fast: the board projects up the face |
| at the top | 0.5 to 0.8 s | board vertical, back arm up; the fan erupts 0.15 to 0.2 s after he arrives and is biggest 0.3 to 0.5 s in; the board comes round (150 to 180 degrees in a cutback) while he stays up there, nearly stopped |
| down | 1.0 to 1.5 s | compact, under the hanging spray; the foam or the curl catches up and he comes down in it |
| whole cycle | 2.5 to 3.2 s | climb to descent is about 1 : 3 |

### What was wrong (traced with `tests/ride_trace.gd`)

The old cutback: 0.5 s up with the speed falling slightly; at the top his speed *rose* (+4.5 m/s2) while the board came
round; then he dropped from the lip to the bottom in 0.45 s (a third of the footage's time) and reached 13 m/s
(1.7 times the peel speed) in the middle of the face. Four causes:

- **`u` was treated as height.** The face's points are spaced along its outline, so `u` is close to a share of the
  face's *length*, but the rise was the vertical speed divided by the wave's height. He crawled up the gentle foot of the
  face and rushed down the steep top three times too fast. Now `rise = (v sin theta + draw) / face_length`
  (`WaveModel.face_length_at`), and the trim heading and the turn guards use the same rate.
- **Big moves counted as pumping.** The pump reads the rhythm of the stick; a reversal at the lip or the stick coming
  back after a cutback looked like a huge stroke and added up to 12 m/s2. Strokes are now capped at `PUMP_HEADING`,
  only count near the line, and not during or after a turn off the top.
- **Nothing took his speed at the top**, and **gravity and the drive were both full on the way down.**
- **Spray came from current speed times turn rate**, so it peaked on the fast way down.

### The model (`Rider._update_cycle`)

- **Explode up (`charge`).** Loaded low on the face (the press of the bottom turn and its turn rate) he stores a
  charge, and as the nose comes up he spends it: `LAUNCH_ACCEL` (12 m/s2 at full charge) up the face below the top,
  over about half a second. Below the top the water rushing up the face takes `LIFT_SHARE` of gravity's brake on the
  climb. Speed now rises through the climb and peaks two thirds of the way up.
- **Stop at the top (`release`).** High on the face (`TOP_FROM` to `TOP_FULL`) and turning down hard, his speed falls
  toward `STALL_SPEED` (0.3 of the peel speed) with a time constant of `RELEASE_TIME` (0.15 s): the board goes light
  and pivots round, and the top holds him (`RELEASE_HOLD`) while it comes round. It is only as big as the climb before
  it (`_approach`: none below 26 degrees nose up, all of it from 60), so a steep climb into the lip is a full stop, a
  shallow one a carved top turn that keeps its flow, and trimming high then diving is just a drop.
- **Float down (`afloat`).** After a release he feels only `FLOAT_GRAVITY` of the pull down the face, the water holds him
  back above `FLOAT_SPEED`, the drive waits, the water no longer lifts a board that has stopped planing (he sinks
  `FLOAT_SINK` with the lip and foam), and the section he hit carries him (`FLOAT_CARRY` of the curl's pace, fading
  over `CARRY_FADE` once he is down) so the curl does not swallow him. The float lasts the descent and ends low on the
  face (`FLOAT_END`), where the next bottom turn gets the wave's power.
- **Spray from the speed he sheds.** Turning off the top the rail throws the speed it is shedding (the speed he carried
  up the face, times how hard he is releasing), so the biggest fan comes right as he stops at the top; it is a giant
  fan (`SurferSpray.burst(..., giant)`: 40 percent more droplets, 30 percent faster, hanging 40 percent longer) that
  hangs while he floats down under it. Floating down, the rail throws 70 percent less. A burst that was not full yet is
  topped up to a full one; a full one is not thrown again. The carve trail's width follows the same spray power, so the
  gouge at the top is wide and the float down leaves a light track.

### Measured after (60 fps, `tests/run_tests.gd`, "turn off the top")

| | footage | lip hit (pocket) | cutback (shoulder) |
| --- | --- | --- | --- |
| climb, quarter way up to the top | 0.3 to 0.5 s | 0.35 s, 9.3 to 10.3 m/s | 0.38 s, 8.5 to 9.4 m/s |
| speed at the top | nearly stopped | 2.3 m/s | 2.3 m/s |
| where the board comes round | at the top | 0.95 up the face | 0.85 up the face |
| biggest fan | at the top as he stops | 1.0 at 0.95, at the hardest stop | 1.0 at 0.94, at the hardest stop |
| down to the lower face | 1.0 to 1.5 s | 0.8 s | 0.9 s |
| fastest down the middle of the face | slow | 4.0 m/s (13.3 before) | 2.7 m/s (10.7 before) |

Lip hits every 4.4 s (`ride_trace.gd -- ride=cycle`) keep him at the curl and climbing to about 11.5 m/s each time;
cutbacks every 5 s (`ride=cutbacks`) run him out along the shoulder and back to the pocket. After a hit in the pocket
he comes down in the foam one to two meters behind the peel point, as in the footage, and the next bottom turn takes him
out again.

```powershell
godot_console --headless --path game --script res://tests/ride_trace.gd -- ride=cutback every=3
```

## Seventh pass: hitting the lip and the cutback are two moves, told apart by where the turn starts

The user's notes: a turn started before the very top of the lip is not a hit off the lip but a long sweeping turn along
the face, all the way back. Hitting the lip (Bells at about 19 s) is a steep rise, a violent snap that pivots the board on
its tail, all the energy released, then down with the wave. The cutback: get out in front a bit, start the turn below
the lip and hold it (keep scrolling or holding down) until he faces back toward the curl with his chest to the camera;
let go and the board pivots back almost 180 degrees. Gold standard: `storyboardimages/lip_slowmo` from 37 to 49 s.

### What the footage shows (every frame)

- **Hitting the lip, Bells 19.3 to 21.2 s.** Bottom turn 19.33 to 19.8 s, a climb of only 0.2 s, at the lip 20.0 s with
  the back arm up and the board vertical, the snap 20.17 to 20.5 s (the board pivots on its tail, the spray erupts),
  down into the foam by 21.2 s. The sixth pass already models this.
- **The cutback, Bells 22.6 to 24.0 s.** Out ahead of the whitewater he rises at a moderate angle (22.33 to 22.5 s). The
  turn starts at about two thirds of the way up the face, well below the lip (22.58 s: rail engaged, back arm thrown).
  The board's nose swings round through the top of a wide arc (22.83 to 23.1 s) and sweeps down the face with a big
  curving curtain of spray behind it (23.17 to 23.42 s), until he faces back toward the whitewater, chest to the camera,
  arms out, mid face (23.5 to 23.67 s): about 180 degrees in about 0.9 s. He meets the foam and the board pivots back
  (23.75 to 24.0 s), about 180 degrees in about 0.3 s, compact.
- **The slow-motion cutback, lip_slowmo 37.5 to 49.5 s** (about 4 to 5 times slow, judged by matching its phases to
  Bells): out on the shoulder, the turn starts mid face (40.0 to 40.5), the fan arcs up and round (41 to 42.5), he lays
  back into the turn as the board comes round (42 to 43.5), faces back toward the whitewater standing taller with his
  arms out (44.75 to 46.5), meets it (46.75), and the board pivots back in the foam (47 to 48.3). In real time: about a
  second of carve, a moment riding back, about 0.3 s of pivot.

### The model (`Rider._update_cutback`, `MovePlayer`)

- **Where the turn starts decides it.** A push down that starts below the lip (`CUT_TOP`) off a climb that is not
  committed to it (nose up between `CUT_START_HEADING` and `CLIMB_COMMIT`, under about 49 degrees) is a carve and can
  never become a snap or a release, even if the climb carries him up near the lip. A steep, committed climb's reversal
  still waits for the lip and snaps there (the sixth pass).
- **Out in front, held hard, it is a cutback.** If the turn started out in front (`CUT_ROOM`, 4 m ahead of the peel
  point) and the push stays hard (the stick past `CUT_PUSH`) for `CUT_HOLD_TIME` (0.4 s), it commits. A quicker push is a
  carved top turn, and a slow gentle scroll is just a carve, so S-turns down the line never turn into cutbacks.
- **Held, it swings round.** While the push is held (pushes no more than `CUT_HOLD_GAP` apart) the turn sweeps on round
  at a steady rate (`CUT_SWEEP`), mostly on the rail (`CUT_PIVOT` of it on the tail, `CUT_GRIP` more grip), to
  `CUTBACK_REACH` (172 degrees), and he rides back toward the curl for as long as it is held.
- **Let go, it pivots back.** Let go once past straight down (`CUT_PAST`), or meet the foam or the bottom, and the board
  pivots straight back toward the line (the push is dropped at once, up to `REBOUND_OMEGA` 10 rad/s at `REBOUND_ACCEL`).
  Let go before straight down and the turn just ends, a long carve down the face.
- **Spray.** The fan goes as the turn bites at the top of its arc, and the rail throws a steady curtain the whole way round
  (`Rider.rail_spray`, `SurferSpray.set_rail`), aimed off the outside rail each frame so it paints a curving sheet.
- **No stop at the top in a cutback.** The release (stop, giant fan, float) is the lip hit's alone, and only up by the lip
  (`TOP_FROM` 0.8 to `TOP_FULL` 0.9).

### Measured (60 fps, `tests/run_tests.gd`, "cutback")

| | footage | game |
| --- | --- | --- |
| where the turn starts | about two thirds up the face, below the lip | 0.40 up the face (commits at 0.91, never a snap, no release) |
| carve until facing back | about 0.9 to 1.1 s | 1.45 s, mostly carved (pivot share 0.39), top of the arc 0.93 |
| holding on | riding back at the whitewater | stays facing back (0.3 s held in the test, -151 degrees at most) |
| pivot back after letting go | about 0.3 s | 0.45 s back to within 35 degrees of the line (0.35 s in the hotkey trace, peak 8.5 rad/s) |
| let go before straight down | | a long carve down the face, no pivot back |
| in the pocket (no room) | | a carved top turn, no cutback, no snap |

### Hotkeys (`MovePlayer`, `scripts/move_player.gd`)

L hits the lip, C cuts back (holding the push until he faces back, then letting go), F floats along the top, T steers back
into the barrel and crouches there (making the wave hollow first if it cannot barrel), P chases down the line pumping.
Each move works the same controls a player does, a phase at a time, watching where he is; any scroll, drag, arrow key
or real mouse move takes the controls back. The move playing is shown next to the game speed. The sprite animation
cycler moved from P to O. `tools\capture.ps1 -Move cutback` and `ride_trace.gd -- move=cutback` play them too.

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
- The back forearm over the head at the lip is hard to read from our camera behind him.
- With no input after a hit in the pocket he recovers slowly at the flat foot of the face (about 3 s to the curl's pace);
  a player's next bottom turn takes him out at once. Step 11's controls should make that bottom turn easy to start.
- The 3D surfer has no pose of its own for the stop at the top or the float (it reads the existing crouch, lean and
  lead); a hang pose (back arm up, compact) would sell the stop.
