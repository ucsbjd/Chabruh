# Chabruh: Wave Modeling, Hydrodynamics & Dynamic Spray Upgrade Spec

Read `CLAUDE.md`, `wave-and-spray-model.md`, `game/scripts/wave_model.gd`, `game/scripts/wave_mesh.gd`, `game/scripts/wave_stage.gd`, `game/scripts/rider.gd`, `game/scripts/surfer_spray.gd`, and `game/shaders/wave3d.gdshader`.

## Goal of This Upgrade
Take our existing parametric 2.5D wave and spray architecture and upgrade it from "geometric approximation" to **"stylized arcade surf physics"** (60 fps on WebGL2 & mobile, zero per-frame mesh rebuilds):
1. **Realistic, Carvable Wave Shoulder & Dynamic "Reef Bowl" Sections:** Fix the concave-everywhere cross-section and static `0.48` height floor so the shoulder rolls smoothly into a convex, gentle slope, while subtle reef bowls create rhythmic steep sections for hitting the lip and getting barreled.
2. **Almond-Ellipse Barrel + True Parabolic Lip Jet + Tube Silhouette:** Widen the barrel horizontally (`0.68 H` vs `0.43 H`) like a real Longuet-Higgins/New (1983) plunging wave, drive the lip along a true ballistic parabola, add a subtle "pocket sweet-spot assist", and let the surfer remain visible through the thin translucent lip curtain.
3. **2D Spatial Water Velocity Field on the Face:** Replace scalar `v_draw` with a position-dependent flow field `(U_d(d,u), U_u(d,u))` that draws up and back into the pocket, launches upward at the lip, and calms on the shoulder.
4. **Rail-Coupled 3D/2.5D Spray Curtains & Lip-Hit Multipliers:** Remove the `0.45 s` cooldown lockout on `SurferSpray`, couple spray ejection angles to the surfboard's 3D rail normal so cutbacks throw sweeping 180-degree arcs and lip snaps throw huge backlit fountains over the crest, and add an advected whitewater carve trail directly on the wave face.

---

## 1. Realistic Wave Shoulder & Rhythmic "Reef Bowl" Sections (`wave_model.gd`)

### 1.1 Diagnosing the Current Shoulder Issues
In our current model:
- `T(d) = 1 - (1 - 0.48) * S(d / L_s)` stops tapering at 48% height, so the far shoulder stays a tall wall.
- `face_angle(u) = lerp(15 deg, lerp(55 deg, 88 deg, h), u^2)` does NOT depend on `d` at all! Gameplay thinks the shoulder at `d = 35 m` is just as vertical (up to 88 deg) as the pocket at `d = 0 m`.
- In `section(d)`, the wave face is always a concave quarter-circle Bezier (`0.5523` handle weights). Real wave shoulders are **convex / trochoidal** near the crest and gently sloped at the base.

### 1.2 Upgraded Outer Envelope & Shoulder Taper
1. **Two-Stage Shoulder Taper `T(d)`:**
   Let the playable shoulder hold enough height for cutbacks from `d = 0..14 m`, then taper down to `0.16 * H0` swelling water out at `L_s`:

    # Inside wave_model.gd
    func taper_at(d: float) -> float:
        if d <= 0.0:
            return 1.0
        var s1: float = smoothstep(0.0, L_s * 0.45, d) # Pocket to mid-shoulder (1.0 -> 0.58)
        var s2: float = smoothstep(L_s * 0.35, L_s, d) # Mid-shoulder to open swell (0.58 -> 0.16)
        return 1.0 - 0.42 * s1 - 0.42 * s2

2. **Rhythmic "Reef Bowl" Section Modulator `bowl_at(d, time)` (Optional 1D Shader/Model Uniform):**
   Real point breaks (like J-Bay) have reef contours where the wave periodically steepens into a "bowl" (hollow lip section to barrel or hit) and then eases into a shoulder for a cutback.
   Define a slow travelling or world-space bowl factor `bowl(d) = 0.5 + 0.5 * sin(0.22 * d - 0.9)`:
   - Boost local peak height `P(d)` by `+0.12 * bowl(d) * smoothstep(18.0, 2.0, abs(d - 3.0))`.
   - Boost local lip throw `tau(d)` on the inside shoulder (`d` in `0..12 m`) by `bowl(d)` so clear "hit-the-lip" sections appear ahead of the surfer.

3. **Distance-Aware Face Angle `face_angle(d, u)`:**
   Update `face_angle` so it takes `(d, u)` (keep a default `d = 1.5` overload if needed by tests) and flattens progressively along the shoulder `sigma = shoulder_at(d)`:

    func face_angle_at(d: float, u: float) -> float:
        var sigma: float = shoulder_at(d)
        var whitewater: float = whitewater_at(d)
        var top_steep_deg: float = lerp(55.0, 88.0, hollowness) * (1.0 - 0.65 * sigma) * (1.0 - 0.55 * whitewater)
        var base_deg: float = lerp(15.0, 8.0, sigma)
        var exponent: float = lerp(2.0, 1.15, sigma) # Concave wall in pocket (u^2), linear slope on shoulder (u^1.15)
        return deg_to_rad(lerp(base_deg, max(base_deg + 6.0, top_steep_deg), pow(clamp(u, 0.0, 1.0), exponent)))

### 1.3 Concave-to-Convex Cross-Section Morph (`section(d)`)
In `WaveSection` (part 4, the face cubic Bezier from `face_top = (0, c_y)` to `trough = (z_tr, 0)`):
- In the pocket (`sigma = 0`, `kappa -> 1`), the upper tangent points straight down `(0, -c_y * 0.5523)` to form a hollow concave wall.
- On the shoulder (`sigma -> 1`, `kappa -> 0`), a real wave crest rolls smoothly over the top (horizontal/convex tangent at the crest, inflecting into a gentle slope at the trough).
- Replace the fixed `0.5523` upper Bezier control point with a `sigma`-blended tangent:

    # Part 4: Face cubic Bezier from P0 = (0, c_y) to P3 = (z_tr, 0)
    var sigma: float = shoulder_at(d)
    var p0 := Vector2(0.0, c_y)
    var p3 := Vector2(z_tr, 0.0)
    # In pocket (sigma=0): p1 pulls straight down (0, -0.5523*c_y) for deep concave scoop.
    # On shoulder (sigma=1): p1 pulls forward (+0.32*z_tr, -0.18*c_y) for a smooth, rounded swell face.
    var p1 := Vector2(
        lerp(0.0, 0.32 * z_tr, sigma),
        c_y - c_y * lerp(0.5523, 0.22, sigma)
    )
    var p2 := Vector2(
        z_tr - z_tr * lerp(0.5523, 0.42, sigma),
        lerp(0.0, 0.08 * c_y, sigma)
    )

---

## 2. Elliptical "Almond" Barrel, Ballistic Lip & Tube Visibility

### 2.1 Why Circular Barrels Feel Cramped
Currently, `r = kappa * 0.43 * H` uses a circle for the barrel interior (`A(rho, theta) = (r + rho*cos(theta), c_y + rho*sin(theta))`).
In real hydrodynamics (Longuet-Higgins 1982; New 1983 "A class of elliptical free-surface flows"), an overturning plunging breaker forms an **almond/ellipse** whose horizontal axis is ~1.6x wider than its vertical axis (`r_z = 0.68 * H`, `r_y = 0.42 * H`).
Changing the circle to a horizontal ellipse accomplishes three things immediately:
1. The lip pitches **much further forward** toward the beach (`+z`), creating a spacious, dramatic canopy over the surfer.
2. Looking down the line at `yaw = +24..30 deg`, the camera sees a wide, inviting almond-shaped mouth instead of a narrow slot.
3. The surfer has room to ride high or low inside the tube without their head clipping the roof.

### 2.2 Elliptical Tube + Parabolic Ballistic Lip Equations
Update the cross-section builder in `wave_model.gd`:

    var r_y: float = kappa * 0.42 * H
    var r_z: float = kappa * lerp(0.43, 0.72, smoothstep(0.2, 1.0, kappa)) * H
    var c_y: float = H - r_y - t

    # Elliptical arc point helper: stretches z-reach of the barrel roof and thrown lip
    func arc_point_elliptical(rho_y: float, rho_z: float, theta: float) -> Vector2:
        # Optional slight downward tilt of ellipse major axis as kappa -> 1
        var u_z: float = r_z + rho_z * cos(theta)
        var u_y: float = c_y + rho_y * sin(theta)
        # Add ballistic gravity drop on the overhanging lip tip (when theta < 45 deg)
        var overhang: float = clamp((deg_to_rad(45.0) - theta) / deg_to_rad(85.0), 0.0, 1.0)
        var gravity_drop: float = 0.22 * H * overhang * overhang * kappa
        return Vector2(u_z, max(0.0, u_y - gravity_drop))

And update `lip_landing_point(d)` from the fixed `0.7` heuristic to true horizontal projectile carry from tip velocity `v_jet`:

    # Ballistic trajectory from (z_tip, y_tip) with downward angle theta_tip:
    # Horizontal launch speed scales with sqrt(g * H) and curl kappa
    var t_fall: float = sqrt(max(0.0, 2.0 * y_tip / 9.81))
    var v_jet_z: float = lerp(0.6, 1.45, kappa) * sqrt(9.81 * max(0.5, H))
    var z_land: float = z_tip + v_jet_z * t_fall
    return Vector3(-d, 0.0, z_land)

### 2.3 Fixing the Quadratic Bezier / Arc Vertex Morph (`wave3d.gdshader`)
Currently, `V_yz' = V_yz + (LIFTED - V_yz)*lift + (LANDED - V_yz)*fall` interpolates linearly between two static keys at a time. When morphing from `LIFTED -> THROWN -> LANDED`, linear interpolation cuts across the chord of the arc instead of following an overturning trajectory.
**Fix in `wave3d.gdshader` vertex shader:**
Use a **quadratic Bezier evaluation** across the 3 keys `(P_lifted, P_thrown, P_landed)` stored in `CUSTOM0` and `VERTEX.yz` over the active throwing window `s_throw = clamp(phase / 0.68, 0.0, 1.0)`:

    // Inside wave3d.gdshader vertex():
    // s_throw goes 0.0 (LIFTED crest) -> 0.5 (THROWN apex) -> 1.0 (LANDED impact)
    // Quadratic Bezier through P0=LIFTED, P1=control(pushed out/up from THROWN), P2=LANDED
    vec2 p0 = lifted_yz;
    vec2 p2 = landed_yz;
    // Control point P1 ensures the curve passes right through thrown_yz at s_throw = 0.5:
    vec2 p1 = 2.0 * thrown_yz - 0.5 * (p0 + p2);
    float u_t = smoothstep(0.0, 0.68, lip_phase);
    vec2 ballistic_yz = mix(mix(p0, p1, u_t), mix(p1, p2, u_t), u_t);
    // Blend cleanly back to P0 during the recovery phase (0.68 -> 1.0)
    float recover = smoothstep(0.68, 1.0, lip_phase);
    vec2 final_yz = mix(ballistic_yz, p0, recover);
    VERTEX.yz = mix(VERTEX.yz, final_yz, lip_amount);

This guarantees every lip vertex traces a true parabolic arc through `(y, z)` with zero extra attributes or memory!

### 2.4 Solving the "Surfer Inside the Tube" Visibility & Feel
To make barrels a signature highlight of Chabruh:
1. **Translucent Lip Backlight Silhouette (When the 3D Lip Passes in Front of the 3D Surfer):**
   - Since the 3D surfer and `WaveMesh` share the `WaveStage` depth buffer, whenever the pitching lip (`UV.x` near 0, high `thin` attribute) is in front of the surfer, an opaque `wave3d.gdshader` hides the surfer completely.
   - **Zero-Extra-Viewport Fix:** On the 3D surfer's `MeshInstance3D`, set `material_overlay` (or a `next_pass` on `surfer3d.gdshader`) to a lightweight silhouette shader with `render_mode unshaded, depth_test_inverted, depth_draw_never, blend_mix;`.
   - When the wave lip occludes the surfer (`depth_test_inverted` passes!), draw the surfer as a soft, glowing **dark-teal / sunlit-aqua refracted silhouette (`alpha = 0.42`)** with a warm gold rim! Now, as the thick jade lip pitches in front of the surfer, you clearly see their crouched silhouette glowing *through* the translucent water curtain!
2. **Subtle "Barrel Sweet-Spot Assist" in `rider.gd`:**
   - Getting barreled at `V_p = 7.78 m/s` shouldn't feel like balancing on a razor blade.
   - When `barrel_amount(d, u) > 0.4` and the player is holding a slight stall or crouch (`d` between `-3.5 m` and `+1.2 m`, `u < 0.45`), apply a gentle spring attractor toward the optimal tube viewing pocket `d_sweet = -1.2 m`:
     `a_tube_assist = clamp((d_sweet - d) * 2.8, -3.5, 3.5) * barrel_amount`
   - This lets the player settle into the glowing green room, drag their hand on the wall, and then pump forward (`-dx` / nose down) to fly out with the spit!

---

## 3. 2D Spatial Water Velocity Field on the Wave Face (`rider.gd`)

Replace the uniform scalar `v_draw` with a physically grounded 2D surface flow field `(u_water_d, u_water_u)` in meters/sec so different zones of the wave feel distinct underfoot:

    # Returns Vector2(flow_along_d, flow_up_face) in m/s at (d, u)
    func water_velocity_at(d: float, u: float) -> Vector2:
        var H: float = crest_height_at(d)
        var sigma: float = shoulder_at(d)
        var tau: float = throw_at(d)
        var B: float = barrel()

        # 1. Upward face draw (strongest in the pocket & mid-to-upper face, weak on far shoulder)
        var pocket_focus: float = 1.0 - 0.65 * sigma
        var vertical_profile: float = smoothstep(0.0, 0.35, u) * (1.0 + 0.45 * tau * smoothstep(0.5, 0.9, u))
        var v_up: float = 1.25 * clamp(H / 2.5, 0.45, 1.4) * pocket_focus * vertical_profile

        # 2. Horizontal draw along d:
        # - Low/mid face near pocket: water sucks BACKWARD into the curl (-d direction)
        # - Right at the pitching lip (u > 0.78): crest jet pitches FORWARD (+d / beachward boost)
        var suck_back: float = -0.22 * V_p * (1.0 - sigma) * (1.0 - smoothstep(0.65, 0.88, u))
        var lip_forward_boost: float = 0.28 * V_p * tau * (0.4 + 0.6 * B) * smoothstep(0.75, 0.95, u)
        var v_along_d: float = suck_back + lip_forward_boost

        return Vector2(v_along_d, v_up)

**Gameplay Magic from This Field:**
- **In the Pocket:** The `-0.22 * V_p` suck-back naturally pulls the surfer into the curl while strong `v_up` lifts them up the steep wall, making bottom-to-top carves feel snappy and vertical.
- **At the Lip (`u > 0.78`):** `lip_forward_boost` pushes the board forward when doing a `floater` or `hit_the_lip`, rewarding players who climb high!
- **On the Shoulder (`sigma -> 1`):** Upward draw fades away and the wave flattens, naturally prompting the player to carve a roundhouse **cutback** back toward the pocket!

---

## 4. Next-Gen Spray System: Cutback Curtains, Lip Explosions & Carve Tracks

### 4.1 Fixing the 3 Flaws in `SurferSpray` (`surfer_spray.gd`)
1. **Remove the `0.45 s` Cooldown Lockout:**
   - Currently, `if power > 0.16 and cooldown <= 0: cooldown = 0.45`. This fires at turn entry (`power = 0.17`) and blocks spray during the peak of the cutback or lip snap 200 ms later!
   - **Fix:** Replace the single `0.45 s` lockout with:
     a) **Continuous Rail Curtain Stream:** Fires micro-slices every `0.055 s` (18 Hz) using a 6-emitter ring pool whenever `power > 0.18`, dynamically updating its ejection angle every slice so a cutback sweeps a continuous curved fan across the screen!
     b) **Apex Snap Detonation:** Whenever `power` reaches a local peak above `0.45` (or when hitting the lip at `u > 0.70` with `omega < -1.5`), fire an immediate high-density **Apex Burst** (`strength = 1.0`), even if a stream slice just fired!

2. **Couple Spray Ejection Angle to the 3D Board Rail & Maneuver Type:**
   Instead of launching every fan around a hardcoded `-40 deg` screen angle, compute the 3D ejection direction from the board's physical turn state and project it through `WaveStage.project()`:

    # In Surfer3D / Rider -> SurferSpray:
    # f = board forward unit vector on wave face
    # s = board lateral vector (points toward inside rail on +omega, outside rail on -omega)
    # n = wave surface normal
    var spray_side: Vector3 = -sign(omega) * s # Spray always blasts off the OUTSIDE / buried rail!
    var lip_hit_factor: float = smoothstep(0.68, 0.90, u) * wave.throw_at(d) * smoothstep(0.0, 1.5, -omega)

    # Base 3D spray direction: backward off the tail + outward off the buried rail + lofted off the wave face
    var dir_3d: Vector3 = (-0.45 * f + 0.85 * spray_side + (0.35 + 0.65 * lip_hit_factor) * n).normalized()
    # When hitting the lip, bias spray straight UP (+Y) and over the back of the crest (-Z)!
    dir_3d = dir_3d.lerp(Vector3(0.25, 0.85, -0.45).normalized(), lip_hit_factor * 0.75).normalized()

    var p_tail_2d: Vector2 = wave_stage.project(tail_world_pos)
    var p_dir_2d: Vector2 = wave_stage.project(tail_world_pos + dir_3d * 1.5)
    var dynamic_axis_angle: float = (p_dir_2d - p_tail_2d).angle()

   **How This Transforms Every Move Visually:**
   - **Bottom Turn (`omega > 0`, low `u`):** `spray_side` points down and right toward the trough; the fan blasts low and behind the tail across the teal water.
   - **Roundhouse Cutback (`omega < 0`, out on shoulder):** As the surfer wraps 180 degrees from climbing to dropping back toward the curl, `dynamic_axis_angle` sweeps through a 120-degree arc across 6 overlapping stream slices, painting a giant curved white ribbon of spray!
   - **Hitting the Lip (`u > 0.70`, `omega < -1.5`):** `lip_hit_factor` approaches `1.0`. The spray blasts **high above the wave crest against the sunset sky**, with a **1.8x droplet count and 1.35x launch speed multiplier**, lingering in the air as the surfer drops back down the face!

3. **Break Up the Rigid "30 Spokes" Bicycle-Wheel Look:**
   - Adding a small per-ray jitter `angle_i = base_angle_i + randf_range(-0.4, 0.4) * ray_step` and coupling initial velocity to directional ray index `v_i = v_peak * (1.0 - 0.35 * pow(abs(ray_norm), 1.6))` turns the 30 spokes into a ** crescent-shaped hydrodynamic sheet** (fastest in the center of the gouge, trailing off into fine mist at the wings).
   - **Fix Godot Particle Damping Note (§6.1):** You correctly noted in `wave-and-spray-model.md` that Godot's `CPUParticles2D.damping_min/max` is in **linear `px/s^2`**, so `0.7..1.3` on a `600 px/s` particle is a complete no-op (`0.1%` slowdown)! Set `damping_min = 220.0 * ppm_scale`, `damping_max = 480.0 * ppm_scale` (or use `scale_amount_curve` + velocity curve over lifetime) so high-speed droplets burst out fast off the rail and then decelerate in the air like real mist!

### 4.2 Advected Whitewater Carve Track on the 3D Wave Face (`WaveCarveTrail`)
Right now, the surfer leaves no mark on the wave face mesh (`§5.6`). Adding an advected foam trail on the 3D wave surface anchors the surfer to the water and makes big open-face carves look incredible:
1. **32-Node Ring Buffer in Wave Space `(d, u)`:**
   - Every `0.04 s`, record a trail node `(d_i, u_i, width_i, alpha_i)` at the surfboard tail:
     - `width_i = lerp(0.18, 0.85, clamp(power * 1.6, 0.0, 1.0))` meters (thin wake during trim, wide white gouge during a bottom turn or cutback).
     - `alpha_i = clamp(0.35 + power * 0.65, 0.0, 1.0)`.
2. **Advect Every Node with the Wave Each Frame:**
   - Each frame (`dt`), update every active trail node using the wave's peel speed and local surface velocity `water_velocity_at(d_i, u_i)`:
     - `d_i += (flow.x - V_p) * dt`
     - `u_i += (flow.y / max(1.2, wave.crest_height_at(d_i))) * dt`
     - `width_i += 0.25 * dt` (foam track spreads out slightly as it ages over `1.4 s`).
3. **Render as a Lightweight 64-Vertex Triangle Strip in `WaveStage`:**
   - Project each `(d_i, u_i)` onto `wave.surface_point(d_i, u_i) + wave.surface_normal(d_i, u_i) * 0.03` and build a 32-segment `ImmediateMesh` / `ArrayMesh` ribbon using the exact same `foam_lit` / `foam_shade` speckled edge math as `wave3d.gdshader`.
   - Because its coordinates live in `(d, u)` and advect with `water_velocity_at(d, u)`, when you carve a deep bottom turn or roundhouse cutback, **your whitewater gouge stays painted on the green face, gets sucked up the wall, and pitches over the falls with the lip!**

### 4.3 Enhanced Barrel Spit (`WaveSpray`)
When the surfer is inside or exiting the barrel (`d` in `[-4.0, +2.0]`) and a lip phase crosses `0.68`:
- Boost the spit horizontal velocity along `+d` (out of the barrel mouth toward screen left, `-15 deg` to `+25 deg` around the tube exit vector) so a dense cloud of backlit mist blasts **out of the almond tube opening right past/around the surfer**, rewarding tube rides with a signature "spit" moment.

---

## 5. Implementation Checklist for Claude

1. **Step 1 (`wave_model.gd` & `wave3d.gdshader`):**
   - Implement the two-stage shoulder height taper `taper_at(d)`, distance-aware `face_angle_at(d, u)`, concave-to-convex shoulder Bezier handles (`p1`, `p2` blended by `sigma`), elliptical barrel dimensions (`r_z`, `r_y`), projectile `lip_landing_point(d)`, and quadratic Bezier vertex morph in `wave3d.gdshader`.
2. **Step 2 (`surfer3d.gdshader` & `rider.gd`):**
   - Add the `depth_test_inverted` translucent lip silhouette pass on the 3D surfer so they glow softly through the pitching lip inside the barrel.
   - Add `water_velocity_at(d, u)` and the subtle barrel sweet-spot pocket assist in `rider.gd`.
3. **Step 3 (`surfer_spray.gd` & `wave_carve_trail.gd`):**
   - Replace the `0.45 s` lockout in `SurferSpray` with the continuous 18 Hz rail-curtain emitter + apex snap detonation, driven by the 3D rail normal (`dynamic_axis_angle`) and `lip_hit_factor`, and fix `CPUParticles2D` linear damping (`220..480 * ppm_scale`).
   - Add the 32-segment advected 3D carve ribbon (`WaveCarveTrail`) in `WaveStage` so bottom turns and cutbacks leave a real foam gouge that flows up the wave face.
4. **Step 4 (Verification):**
   - Run `godot_console --headless --path game --script res://tests/run_tests.gd` and capture comparison shots (`tools\capture.ps1`) of:
     a) The wave shoulder transition (`d = 0..35 m`)
     b) The almond barrel interior + translucent lip silhouette
     c) A roundhouse cutback spray curtain + advected foam carve track
     d) A vertical lip snap fountain high above the crest.