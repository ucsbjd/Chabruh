# CHABRUH: MASTER SPECIFICATION (3D SURFER, CARVING PHYSICS & FINGER-SURF CONTROLS)

Read `CLAUDE.md`, `docs/progress.html`, and inspect `tools/foundry/`, `game/scripts/rider.gd`, `game/scripts/ride_input.gd`, `game/scripts/wave_model.gd`, and `game/scripts/wave_stage.gd`.

---

## IMPLEMENTATION DECISIONS (written after reviewing this spec and simulating it; these win where they differ)

Status: step 9 built the 3D surfer spike; step 10 built the physics (`rider.gd`, dials in `data/tuning.tres` group Carving, with the
interim input: height error becomes a target heading, distance error a drive, keys 1 to 3 and H for testing); step 11 is next.
Original status line: Section 3 (3D surfer, steps 9 and 12) is built as a spike; Sections 4 and 5 are built in step 10 (physics) and
step 11 (controls). The first draft of the equations was simulated against the real `WaveModel` numbers (celerity 5,
peel angle 40 degrees, so the peel speed is 7.8 m/s; `face_angle(u)` runs from 15 degrees at the trough to 55 to 88 at the
crest; wave height 1.4 to 4.4 m). Findings and what we do about them:

### Physics (step 10)
1. **Heading is in the face plane, so height changes need `sin(phi)`.** The draft had `du = v*sin(theta)/H`. Moving a
   distance along the face at heading `theta` gains vertical height `v*sin(theta)*sin(phi)` where `phi = face_angle(u)`.
   Without it the lower face (15 degrees) is crossed about 4x too fast. Use
   `du/dt = (v*sin(theta)*sin(phi) + v_draw) / H`, with `H = max(1.2, crest_height_at(d))`.
2. **Speeds are relative to the wave, not fixed numbers.** The curl advances at `peel = wave.peel_speed()` (7.8 m/s here).
   The draft's trim speed (6.5) would let the curl catch him in about 3 s. Define `MIN_SPEED = 0.45*peel`,
   `TRIM_SPEED = 1.05*peel`, `MAX_SPEED = 1.7*peel`, all re-evaluated when the wave changes. `d += (v*cos(theta) - peel)*dt`
   stays as written (ahead of the peel point while `v*cos(theta) > peel`).
3. **Zero input must hold his line.** The wave's draw (`v_draw`, about 1.1 m/s up the face) lifts him at about 0.4 u/s
   (the crest in about 1.5 s) at `theta = 0`. So the neutral heading is the trim heading that cancels it:
   `theta_trim = -asin(clamp(v_draw / (v*sin(phi)), 0, 0.6))` (about -14 degrees at the trim speed on the mid face).
   `target_theta = theta_trim + input_theta`. The clutch's "coast" decays toward `theta_trim`, not a fixed -4 degrees.
4. **Gravity is gentler and drag is solved, not guessed.** The draft `G_EFF = 11.5` shed 9 m/s of speed in 1 s on a
   +45 degree climb. Start at `G_EFF = 6.0` (tuning dial). Choose `K_WATER` so that terminal speed at the trim heading is
   `TRIM_SPEED`: `K_WATER = G_EFF*sin(phi_mid)*sin(abs(theta_trim)) / TRIM_SPEED^2`, recomputed per wave. `K_CARVE`
   (0.12) and `K_PUMP` (1.8) stay as the starting dials. Keep `a_trim_drive` (the horizontal finger gesture, see below).
5. **Lead-and-follow springs stay as specified** (tier 1 head and chest at once, tier 2 critically damped about 50 ms,
   tier 3 hips about 120 ms). Tier 1 is applied by `Surfer3D` as an extra twist after the pose blend.
6. **Guardrails stay**, plus an explicit soft wipeout: if `d` falls inside the lip's landing zone (behind the curl by more
   than about 1.5 m) and speed is below `peel`, the surfer tumbles softly and paddles back (no fail screen).
7. **Pose weights** follow the spec, but are normalised so the blend of the non-base poses never exceeds 1, and they ease
   in on the 0.12 s spring already in `Surfer3D` (so there is no pop when a label flips).
8. **`wave.barrel_amount_at(d, u)` does not exist**; add it from `zone_at(d)` and `barrel()` (zero outside the tube).

9. **Bugs found by playing it (step 10).** (a) The draft's `t_face = n_surf x t_crest` points down the face, so the board's nose
   turned the wrong way; it is `t_crest x n_surf`. (b) The board must turn about the back foot (a pivot turn): the surface point is the
   tail pivot and the board centre sits `0.36 m` ahead of it along the heading, so the tail stays put while the nose swings. (c) The stick
   must be fed from the amount pushed (`RideInput.take_height_push()`), not from the clamped height, or scrolling does nothing at an end stop.
   (d) Hand targets are relative to the shoulders and turn with the chest, never fixed in the model.

### Controls (step 11)
1. **One virtual stick, relative deltas only.** Finger motion integrates into two numbers: `stick_y` (carve up or drop,
   which sets `input_theta`) and `stick_x` (drive or stall). Both spring back to zero when the fingers lift (the coast), so
   a re-centring hand never moves the board. This works the same for touch and trackpad.
2. **Horizontal sweeps drive speed; they do not teleport him.** Moving left pumps (`a_trim_drive` proportional to the
   leftward finger speed, capped), moving right drags (`a_trim_drive` negative), so down-the-line position stays a result of
   physics. Vertical sweeps set the heading (up carves up, down drops).
3. **Response curve** as drafted (dead zone about 0.08 with calm micro-trim, then a curved ramp), with `FULL_CARVE_SWEEP`
   personalised from the player's own sweeps, and a lower bound so a tiny hand still reaches full carve.
4. **Clutching** as drafted: relative deltas, discard the last 30 ms of a lift-off, coast while fewer than two fingers are
   down, ramp the gain back in over about 60 ms. The coast also pauses any move that depends on a held gesture.
5. **Platform limits (from the step 6 recordings).** On Windows the two-finger trackpad arrives as mouse-wheel steps, so
   there are no finger positions, no twist and no spread; `Magnify` is the pinch (and browsers also use it to zoom, so
   the page must swallow it). Features `f6` (twist) and finger spread exist on touch screens only. On desktop, whip and
   snap are read from path curvature, speed and jerk of the integrated stick. Touch uses true two-finger data.
6. **Recognition is rule-based first.** Snap, floater and cutback fire when the gesture feature (whip, hold up at the crest,
   wide arc back) crosses a per-player threshold AND the physical state allows it (as drafted: snap needs `u > 0.68` and
   `theta > 0.25`; floater `u > 0.72`; cutback `u > 0.40` and `d > 1.5`). Template matching on the 8-feature vector is
   only added if the rules misfire, and then with a floor on each deviation (about 25% of that feature's global range) so
   five trials cannot produce a brittle match, and a robust centre (median, dropping the worst trial).
7. **Calibration** reuses the step 6 recorder and tools (`tools/calibrate.ps1`, `analyze_calibration.py`, `replay.ps1`):
   five actions, five trials, saved to `user://control_profile.json`, with the replay tool as the regression test.

### Order of work
Step 10 builds the physics with the old input mapped to heading and drive. Step 11 replaces the input. Step 12 finishes
the surfer's poses, lighting and details. Keyboard and mouse always stay as fallbacks.

---

## SECTION 1: ARCHITECTURAL OVERVIEW & TARGET PLATFORMS

1. **Target Platforms:**
   - **Desktop Web Browsers** (for rapid testing and Firebase previews).
   - **Native Android & iOS Apps** (for final release) — NOT mobile phone web browsers.
   - This eliminates mobile Safari WebGL2 vertex-skinning risks and allows a real-time 3D skinned surfer inside `WaveStage`.
2. **Core Upgrade Summary:**
   - **3D Skinned Surfer (`Surfer3D`):** Export our existing MPFB human, shorts, spiky mullet/mustache, decals, and 5-band surfboard from `tools/foundry/render_character.py` as a single `game/assets/models/surfer.glb` placed directly inside `WaveStage`.
   - **True 3D Barrel Occlusion:** Because `Surfer3D` shares the `WaveStage` 3D depth buffer with `WaveMesh` and `WaveMist`, the pitching lip curtain naturally passes in front of the surfer inside the tube.
   - **Snowboard/Surf Arcade Physics (`Rider`):** Replace timed animation clips with a continuous heading (`theta`), turn rate (`omega`), speed (`v`), and compression (`c`) model on the wave manifold `(d, u)`.
   - **"Two Fingers = Two Feet" Controls & Calibration (`RideInput` & `Calibration`):** Smooth finger-surfboard control for laptop trackpads and phone touchscreens, complete with edge-reset "clutching" (lifting and resetting fingers to center without losing momentum) and a 5-trial per-user gesture calibration system.

---

## SECTION 2: J-BAY MOVE REFERENCE MANIFEST (`wiDVI0hUFQ0`)

All timestamps below are relative to `00:00` of the actual 3m49s video content (`https://www.youtube.com/watch?v=wiDVI0hUFQ0`, ignoring any YouTube pre-roll/mid-roll ads). John John Florence rides regular stance (left foot forward, right foot back), which maps 1-to-1 to our Blender rig's `.L` (front) and `.R` (back) bones:

| Move ID | Video Window | Peak Still | Biomechanical Breakdown for Blender Pose Library |
| :--- | :--- | :--- | :--- |
| `trim` | `00:40.0 - 00:42.0` | `00:41.0` | High-line speed generation, relaxed athletic crouch, weight centered 55/45, left arm leading down the line. |
| `bottom_turn` | `00:00.2 - 00:02.0` | `00:01.0` | Deep knee/hip compression at trough, board rolled +45 deg onto inside rail, back knee (`lowerleg01.R`) tucked inward, right hand brushing water, head looking up at lip. |
| `top_turn` | `00:02.0 - 00:04.2` | `00:03.0` | Extending out of compression high on face, torso opening back toward trough, arms wide for rotational leverage. |
| `hit_the_lip` | `01:08.0 - 01:10.2` | `01:09.0` | Board pitched 80-90 deg vertical into crest (`vert_snap`), back leg kicking tail out, upper body counter-rotated down the slope. |
| `cutback` | `01:11.5 - 01:14.5` | `01:13.0` | Full 180 deg roundhouse wrap back toward pocket, head and shoulders leading turn, heel/outside rail buried. |
| `floater` | `00:25.0 - 00:28.5` | `00:26.5` | Planing horizontally atop breaking lip crest, wide low center-of-gravity squat absorbing drop. |
| `barrel` | `00:47.0 - 00:51.5` | `00:48.5` | Maximum pig-dog / tube crouch inside pocket, rear knee dropped close to deck, trailing right hand dragging wave wall. |
| `air` | `00:10.2 - 00:12.8` | `00:11.2` | Launched above section, knees tucked tight to chest keeping board glued to feet, both arms raised high. |

*Note on MediaPipe Extraction:* If extracting landmarks from `wiDVI0hUFQ0`, first crop a tight square bounding box (`1.6x` surfer height) around the surfer and upscale to `512x512` via `cv2.INTER_LANCZOS4` before running MediaPipe `Pose(model_complexity=2)`. MediaPipe downscales full frames to `224x224` internally, which is why wide shots fail without ROI cropping.

---

## SECTION 3: 3D SURFER MODEL & SHADER (`export_surfer_glb.py` & `surfer3d.gdshader`)

### 1. Blender `.glb` Export (`tools/foundry/export_surfer_glb.py`)
Adapt `tools/foundry/render_character.py` to export `game/assets/models/surfer.glb` headless via `blender -b --python`:
- **Poly Budget & Graphic Normals:**
  - Decimate/clean the MPFB body and shorts shell to ~4,000-6,000 triangles total.
  - Smooth or transfer vertex normals from a simplified capsule/ellipsoid proxy onto the torso and limbs so the toon shader produces big, flat vector light bands rather than noisy anatomical muscle shadows.
- **Polish Details from Step 8:**
  - **Finger Curl:** Rotate MPFB finger bones (`finger1..5`) by 15-25 deg per phalanx into a relaxed athletic surf hand.
  - **Keep Back Tattoo Visible:** Distribute `spine_bend` forward flexion across `spine05..spine01` with lumbar-heavy weights `[0.35, 0.30, 0.20, 0.10, 0.05]` so the upper thoracic back (`spine02/01`, where the shaka tattoo sits) stays angled toward the camera during deep crouches.
  - **Rear Pocket Flap:** Include the right-hip pocket flap outline in Region 5 (aqua trim) and button dot in Region 4 (tattoo ink) on the shorts UV decal.
  - **Back-Knee Drop:** Tuck `lowerleg01.R` pole angle inward during `bottom_turn`, `cutback`, and `barrel`.
- **Single-Draw-Call Region Encoding:**
  - Bake the 8 region IDs (`0 skin, 1 shorts, 2 board, 3 hair, 4 tattoo ink, 5 trim, 6 stripe A, 7 stripe B`) into Vertex Colors (`COLOR`) plus the tattoo/palm UV decal texture so the entire character renders in 1 draw call.
- **Baked Pose Library & Foot Locking:**
  - Keep the surfboard underside center at local origin `(0, 0, 0)`.
  - Bake 10 key poses into the `.glb` `AnimationLibrary`: `trim`, `crouch`, `bottom_turn`, `top_turn`, `cutback`, `vert_snap`, `barrel`, `floater`, `air`, `wipeout`.
  - Every pose must be baked with `foot.L` and `foot.R` locked via IK to the exact same board-local deck coordinates (and optionally pinned at runtime with Godot 4.7 `TwoBoneIK3D` / `SkeletonModifier3D` nodes parented to the board) so blending poses never causes foot sliding.

### 2. Spatial Toon & Mood Shader (`game/shaders/surfer3d.gdshader`)
Create an unshaded spatial shader (`shader_type spatial; render_mode unshaded, cull_back;`):
- Reads the vertex color region ID / decal weights and tints each region using the active `MoodData` uniforms (`surfer_*` fed by `world.gd`).
- Evaluates `dot(NORMAL, light_dir)` and quantizes into 3 flat bands: lit, mid, and cool-violet shadow (never grey or black).
- Computes a crisp view-space silhouette rim highlight (`1.0 - max(0.0, dot(NORMAL, VIEW))`) on the sunlit crest side.

---

## SECTION 4: SNOWBOARD/SURF ARCADE CARVING PHYSICS (`game/scripts/rider.gd`)

### 1. State Variables on the Wave Manifold `(d, u)`
- `d`: distance (m) ahead of the peel point (`+d` = toward open shoulder / screen left; `0` = pocket/break).
- `u`: height on wave face in `[0.0, 1.0]` (`0.0` = trough, `1.0` = crest/lip).
- `theta`: board heading angle in `[-1.45, +1.55]` rad (`0` = straight down the line toward `+d`; `theta < 0` = nose down toward trough; `theta > 0` = nose up toward lip).
- `omega`: angular turn rate `d(theta)/dt` in rad/s (`+omega` = inside-rail bottom turn / climb; `-omega` = outside-rail top turn / cutback).
- `speed`: tangential speed along heading in m/s (`MIN_SPEED = 2.2`, `MAX_SPEED = 12.5`, `TRIM_SPEED = 6.5`).
- `compression`: body crouch in `[0.0, 1.0]` (`0.0` = extended, `1.0` = deep crouch).

### 2. Three-Tier "Lead-and-Follow" Spring Hierarchy
1. **Tier 1 — Head & Upper-Torso Anticipation (0 ms lag):**
   - `lead_delta = clamp(target_theta - theta, -0.80, 0.80)`
   - Applied immediately on frame 1 to neck, head, and upper-chest twist so the surfer looks and torques into the turn first.
2. **Tier 2 — Board Heading Critically Damped Spring (~50 ms response, `omega_n = 18.0`, `zeta = 1.0`):**

    var spring_k: float = 324.0 # 18.0 * 18.0
    var spring_d: float = 36.0  # 2.0 * 18.0 * 1.0
    var speed_auth: float = clamp(remap(speed, MIN_SPEED, MAX_SPEED, 0.55, 1.15), 0.55, 1.15)
    var theta_accel: float = (spring_k * (target_theta - theta) - spring_d * omega) * speed_auth + snap_impulse
    omega = clamp(omega + theta_accel * dt, -MAX_OMEGA, MAX_OMEGA)
    theta = clamp(theta + omega * dt, -1.45, 1.55)

3. **Tier 3 — Hip Compression Spring (~120 ms response, `omega_n = 10.0`, `zeta = 0.85`):**

    var target_crouch: float = clamp(0.22 + abs(omega) * 0.25 + barrel_prox * 0.65 + manual_crouch * 0.5, 0.1, 1.0)
    var c_accel: float = 100.0 * (target_crouch - compression) - 17.0 * compression_vel
    compression_vel += c_accel * dt
    compression = clamp(compression + compression_vel * dt, 0.0, 1.0)

### 3. Energy Exchange, Wave Draw & Boundary Guardrails

    # 1. Slope Gravity (dropping gains speed, climbing trades speed for height)
    var steepness: float = sin(wave.face_angle(u))
    var a_slope: float = -G_EFF * steepness * sin(theta)

    # 2. Water Drag & Carve Rail Bleed
    var a_drag: float = -K_WATER * speed * speed - K_CARVE * abs(omega) * speed

    # 3. Unweighting Pump Boost (extending out of crouch during mid-face carve)
    var unweight_rate: float = max(0.0, -compression_vel)
    var mid_face_weight: float = clamp(1.0 - abs(u - 0.45) * 1.8, 0.0, 1.0)
    var a_pump: float = K_PUMP * abs(omega) * unweight_rate * mid_face_weight * max(0.2, cos(theta))

    # 4. Integrate Speed & Position (including upward water draw on the face)
    speed = clamp(speed + (a_slope + a_drag + a_pump + a_trim_drive) * dt, MIN_SPEED, MAX_SPEED)
    var face_h: float = max(1.2, wave.crest_height_at(d))
    var v_draw: float = V_DRAW_BASE * clamp(face_h / 2.5, 0.4, 1.3)

    d += (speed * cos(theta) - wave.peel_speed()) * dt
    u += ((speed * sin(theta) + v_draw) / face_h) * dt

    # 5. Soft Guardrails (Trough Auto-Scoop & Crest Lip Cushion)
    if u < 0.15 and target_theta < 0.0:
        target_theta = lerp(0.0, target_theta, clamp(u / 0.15, 0.0, 1.0))
    if u > 0.88 and target_theta > 0.0 and not can_launch_or_float:
        target_theta = lerp(target_theta, 0.0, clamp((u - 0.88) / 0.12, 0.0, 1.0))

*Starting Constants (`data/tuning.tres`):* `G_EFF = 11.5`, `K_WATER = 0.035`, `K_CARVE = 0.12`, `K_PUMP = 1.8`, `V_DRAW_BASE = 1.1`, `MAX_OMEGA = 4.5`.

### 4. 3D Surface Orientation, Rail Roll & Continuous Pose Blending (`Surfer3D`)
1. **3D Wave Basis & Rail Roll (`phi`):**
   - `pos = wave.surface_point(d, u)`
   - `n_surf = wave.surface_normal(d, u).normalized()`
   - `t_crest = Vector3(-1.0, 0.0, 0.0)`
   - `t_face = n_surf.cross(t_crest).normalized()`
   - `t_crest = t_face.cross(n_surf).normalized()`
   - `forward = (t_crest * cos(theta) + t_face * sin(theta)).normalized()`
   - `rail_roll = clamp(omega * speed * 0.038, -0.78, 0.78)` (rolls board onto inside rail during bottom turn, outside rail during top turn/cutback).
2. **Continuous Bone Pose Blending (`Quaternion.slerp`):**
   - Start from `trim` base pose and blend bone rotations using continuous state weights:
     - `w_bottom_turn = clamp(omega / 2.2, 0.0, 1.0) * clamp(1.0 - u, 0.2, 1.0)`
     - `w_top_turn = clamp(-omega / 2.0, 0.0, 1.0) * clamp(u, 0.3, 1.0)`
     - `w_cutback = clamp(-omega / 2.5, 0.0, 1.0) * clamp((d - 2.0) / 3.0, 0.0, 1.0)`
     - `w_vert_snap = clamp(theta / 1.1, 0.0, 1.0) * clamp(-omega / 2.2, 0.0, 1.0) * clamp((u - 0.65) / 0.3, 0.0, 1.0)`
     - `w_barrel = wave.barrel_amount_at(d, u) * clamp(compression, 0.4, 1.0)`
     - `w_crouch = compression * (1.0 - w_barrel)`
   - Add `lead_delta` rotation to neck, head, and upper spine bones.

---

## SECTION 5: "TWO FINGERS = TWO FEET" CONTROLS, CLUTCHING & CALIBRATION

### 1. Core Control Mapping
The player's **index finger (front foot)** and **middle finger (back foot)** glide on the trackpad or screen like a finger-surfboard:
- **Move Fingers Left (`-dx`):** Drive down the line (ahead of the break toward `+d`, pumping for speed).
- **Move Fingers Right (`+dx`):** Stall / draw back toward the pocket/curl (`-d` for barrels, or wrapping into a `cutback`).
- **Move Fingers Up (`-dy`):** Carve up the wave face (`+target_theta`).
- **Move Fingers Down (`+dy`):** Drop down the wave face (`-target_theta`).
- **Rotate/Whip Fingers at Crest:** Trigger a Lip Snap (`hit_the_lip`).
- **Push Both Fingers Up & Hold at Crest:** Trigger a `floater` across the lip.

### 2. Forgiving Response Curve ("Big Sweeps to Carve")
Normalize pad delta into a sweep fraction `s` in `[-1.0, 1.0]` where `1.0` equals a wide sweep across ~65% of the pad (`FULL_CARVE_SWEEP_PX = 420.0`, personalized during calibration):

    func apply_forgiving_curve(s: float, deadband: float = 0.08, expo: float = 1.85) -> float:
        var mag: float = abs(s)
        if mag <= deadband:
            return s * 0.20 # Calm micro-trim inside deadband
        var u_s: float = clamp((mag - deadband) / (1.0 - deadband), 0.0, 1.0)
        var curved: float = lerp(u_s * 0.35, pow(u_s, expo), u_s)
        return sign(s) * curved

### 3. The 4-Part "Clutching" Engine (Lifting & Resetting Fingers at Pad Edges)
When fingers reach the left, right, top, or bottom edge of the trackpad/screen, the user lifts them and resets to the middle. This must never jerk the surfer:
1. **Pure Relative Deltas:** Never map absolute pad coordinates `(x, y)` to wave position. Only integrate deltas `(dx, dy)` while fingers are down.
2. **50 ms Anti-Flick Ring Buffer:** Buffer the last 3 frames (`50 ms`) of deltas. When a lift-off occurs, discard the final `32 ms` so uneven fingertip liftoff roll doesn't flick the board backward.
3. **Momentum-Preserving `COAST_STATE`:** When touch count drops below 2 (or trackpad pan events pause for `> 45 ms`), enter `COAST_STATE`:
   - Hold the current line and decay `target_theta` slowly (`0.85 s` time constant) toward a safe trim angle (`-4 deg`).
   - Preserve active `barrel` or `floater` states while the hand resets to the center of the pad.
4. **60 ms Touchdown Ramp:** When fingers touch back down in the center, reset the delta origin and ramp input gain from `0.0 -> 1.0` over `60 ms`.

### 4. Dual-Input Hardware Abstraction (`FingerBoardFrame`)
- **On Android / iOS Touchscreens (`InputEventScreenTouch` / `Drag`):**
  - Read both fingers directly (`front_foot = min_x`, `back_foot = max_x`), giving exact 2D glide `delta_pos`, true 2-finger board rotation `finger_angle_delta`, and `finger_spread_delta`.
- **On Desktop Trackpads (`InputEventPanGesture` / Windows Two-Finger Wheel + `MagnifyGesture`):**
  - Read compressed 2D pan deltas `(dx, dy)` for glide, path curvature `(vx*ay - vy*ax)/|v|^3` for whip/snap rate, and pinch/magnify delta for relative finger twist.

### 5. Per-User 5-Trial Calibration System (`Calibration`)
In `--calibrate` mode (and via an in-game "Calibrate Controls" option), prompt the user to perform 5 repetitions (`1.5 s` window each) of 5 core actions:
1. `trim_and_clutch` (x5): Slide left to race down the line, lift fingers, and reset to center.
2. `open_carve` (x5): Sweep a big, smooth bottom-to-top carve.
3. `hit_the_lip` (x5): Ride up and rotate/whip fingers at the top to snap the lip.
4. `floater` (x5): Push both fingers straight up into the crest and hold to float across the top.
5. `cutback` (x5): Sweep fingers right and around in a wide arc back toward the curl.

For each trial, record the 8-dimensional gesture feature vector over a `350 ms` window:
- `f0`: Net horizontal sweep `dx_norm` (`-1` left to `+1` right)
- `f1`: Net vertical sweep `dy_norm` (`-1` down to `+1` up)
- `f2`: Total arc length swept `L_arc`
- `f3`: Peak finger speed `v_peak`
- `f4`: Peak whip acceleration/jerk `j_peak`
- `f5`: Signed path angular turn rate `omega_path`
- `f6`: Two-finger rotation/twist delta `dtheta_fingers`
- `f7`: Fraction of window spent holding upward `tau_upper`

**Outlier Rejection & Runtime Matching:**
- For each maneuver `M`, drop the 1 trial furthest from the coordinate-wise median of the 5 trials, then compute mean `mu_M[0..7]` and standard deviation `sigma_M[0..7]` from the 4 clean trials and save to `user://control_profile.json`.
- During live gameplay, compute the normalized distance `D_M` between the live `350 ms` window `f(t)` and `mu_M`, yielding `intent_M = exp(-0.5 * D_M * D_M)` in `[0.0, 1.0]`:
  - If `intent_floater > 0.60` near the upper face (`u > 0.72`), assist climb onto the lip (`u -> 0.94`), level `target_theta -> 0`, and blend into `floater`.
  - If `intent_snap > 0.60` near the crest (`u > 0.68`, `theta > 0.25`), inject a downward rotational snap impulse (`-3.2 rad/s`), blend into `vert_snap`, and fire `SurferSpray.burst(1.0)`.
  - If `intent_cutback > 0.60` on the face (`u > 0.40`, `d > 1.5`), smoothly wrap `target_theta` back toward the pocket, roll onto the outside rail, and blend into `cutback`.

---

## SECTION 6: EXECUTION ORDER FOR CLAUDE

1. **Inspect & Plan:** Check `CLAUDE.md`, `docs/progress.html`, `tools/foundry/`, and `game/scripts/`, then post a brief implementation plan.
2. **Step A (3D Surfer Spike):** Build `tools/foundry/export_surfer_glb.py`, `game/shaders/surfer3d.gdshader`, and `game/scripts/surfer_3d.gd` inside `WaveStage`. Verify look, mood colors, barrel depth occlusion, and frame time (`tools\capture.ps1 -Perf`).
3. **Step B (Carving Physics & Pose Blending):** Upgrade `game/scripts/rider.gd` with the heading kinematics, 3-tier lead-and-follow springs, rail roll, and continuous 3D skeleton pose blending.
4. **Step C (Finger-Surf Controls & Calibration):** Upgrade `game/scripts/ride_input.gd` and `game/scripts/calibration.gd` with the forgiving S-curve, 4-part clutching engine, and 5-trial gesture calibration profile.