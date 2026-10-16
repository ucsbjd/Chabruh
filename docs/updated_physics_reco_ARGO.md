# Chabruh: Complete Wave, Cutback Energy Cycle & Dynamic Spray Upgrade Spec

Read `CLAUDE.md`, `wave-and-spray-model.md`, `game/scripts/wave_model.gd`, `game/scripts/wave_mesh.gd`, `game/scripts/wave_stage.gd`, `game/scripts/rider.gd`, `game/scripts/surfer_spray.gd`, and `game/shaders/wave3d.gdshader`[cite: 1].

---

## 0. Architecture & Baseline Context (Self-Contained Reference)

* **Engine & Target:** Godot 4.7, GDScript, GLSL-like shaders, Compatibility/WebGL2 renderer running at 60 fps on mobile/browser with zero per-frame mesh rebuilds[cite: 1, 2].
* **2.5D Parametric Wave (`WaveModel` / `WaveMesh`):** The wave body is a 3D mesh swept across ~54 stations along the crest parameter `d` (distance in meters ahead of the peel point, where world `x = -d`, `y` is up, and `z` points toward the beach/camera) and 56 points per cross-section[cite: 2]. The surfer rides on the wave surface in coordinates `(d, u)`, where `u in [0.06, 0.96]` is the normalized height up the 10-segment face polyline (`0 = trough`, `1 = top`)[cite: 2].
* **Core Physical Constants & Envelopes:**
  * Peel speed: `V_p = c / sin(alpha) = 7.78 m/s` (`c = 5 m/s`, `alpha = 40 deg`), base height `H0 = lerp(1.4, 4.4, s)`, shoulder length `L_s = lerp(30, 46, s)`[cite: 2].
  * Shoulder factor: `sigma(d) = S(5, 0.75 * L_s, d)` (`0` in the pocket/wall, relaxing toward `1` down the shoulder)[cite: 2].
  * Lip throw activity: `tau(d) = 1 - S(d / 9)` for `d >= 0` and `1 - S(2.8, 7, -d)` for `d < 0`; curl `kappa(d) = tau(d) * lerp(0.18, 1.0, B)`[cite: 2].
  * Up-face water draw: `D(d, u) = clamp(H / 2.5, 0.4, 1.3) * (1 - 0.65 * sigma) * lerp(0.55, 1, S(0, 0.35, u)) * (1 + 0.45 * tau * S(0.5, 0.9, u))` with `v_draw = 1.1 * D(d, u)`[cite: 2].
  * Wave push: `W(d) = T(d) * (1 - 0.85 * sigma) * lerp(1, 0.6, whitewater)`[cite: 2].
* **Tangent Frame on the Wave Face (`rider.gd`):**
  * `P = surface_point(d, u)`, `n = surface_normal(d, u)`, local slope `phi = acos(n_y)`, `H = max(crest_height_at(d), 1.2)`[cite: 2].
  * `t_crest = (-1, 0, 0)`, `t_face = t_crest x n`, `t_crest <- n x t_face`[cite: 2].
  * Heading `theta` in the tangent plane: `0 = down the line (+d)`, `+ = climbing toward the lip`, `- = dropping toward the trough`[cite: 2].
  * Board forward vector `f = t_crest * cos(theta) + t_face * sin(theta)`; lateral vector `s = t_face * cos(theta) - t_crest * sin(theta)`[cite: 2].
* **What Was Already Implemented from Argon's First Spec:**
  * Two-stage shoulder taper `T(d)` and `sigma`-blended concave-to-convex face Bezier cross-section[cite: 1, 2].
  * Almond barrel cross-section (`aspect a = 1.4`)[cite: 2].
  * Up-face draw field `D(d, u)` and wave push `W(d)`[cite: 2].
  * Peak-triggered spray bursts (if `power` rises `0.15` above the last burst during the `0.45 s` pause), 3D outside-rail spray direction projection, and pixel-scaled particle damping[cite: 1, 2].

---

## 1. Primary Bug to Fix: Inverted Cutback & Top-Turn Physics Timing

### 1.1 Symptoms Observed in Gameplay
1. **Sluggish Climb:** When the surfer turns up the face for a cutback, he does not accelerate/explode upward like a real surfboard projecting out of a bottom turn.
2. **No Stall/Stop at the Top:** Instead of releasing all his kinetic energy into a hard gouge and coming to a near-stop at the top of the wave, he keeps carrying speed through the top and finishes the turn late.
3. **Mid-Wave Rocket Acceleration on the Way Down:** Once he finishes the cutback and reaches the middle of the wave pointing down, he suddenly accelerates hard down the mid-face—putting the peak energy and speed on the way down instead of on the way up.
4. **Spray Peaks in the Middle/Descent Instead of Exploding at the Top:** Because speed is highest when accelerating down the middle of the face, the spray system fires its biggest bursts late instead of exploding at the apex of the cutback.

### 1.2 Mathematical Root Causes in `rider.gd` and `surfer_spray.gd`
Currently, `rider.gd` models the wave like a **static snowboard hill** rather than an upward-rushing hydrodynamic sheet[cite: 2]:

| Maneuver Phase | Current Equation in `rider.gd` / `surfer_spray.gd`[cite: 2] | Why It Causes the Bug |
| :--- | :--- | :--- |
| **1. Going Up (`theta > 0`)** | `a_slope = -g * sin(phi) * sin(theta)` (`g = 9`) and `a_drive *= S(-0.1, 0.4, cos(theta))`[cite: 2] | Static uphill gravity immediately brakes the surfer the moment he points up (`theta > 0`), and `a_drive` shuts off as the board points steeply upward (`cos(theta) -> 0`)[cite: 2]. |
| **2. Vertical Climb Rate (`u'`)** | `rise = (v * sin(theta) * sin(phi) + v_draw) / H`[cite: 2] | Since `u` already measures distance along the curved face polyline[cite: 2], multiplying `v * sin(theta)` by `sin(phi)`[cite: 2] double-penalizes the climb and cuts upward speed by `50-75%` on the gentler shoulder slope (`phi = 15..30 deg`). |
| **3. Cutback at the Top** | `v in [0.45 * V_p, 2.1 * V_p]`, `omega_n = 8 rad/s`, `omega_cap = min(3.5, grip / max(v, 4))`, `light = S(0.78, 0.9, u)`[cite: 2] | 1) The `0.45 * V_p` (`3.5 m/s`) floor makes stalling at the top impossible[cite: 2]. 2) `light` only activates above `u = 0.78`[cite: 2], so shoulder cutbacks (`u = 0.50..0.78`) don't unweight/pivot. 3) The `8 rad/s` 2nd-order lean filter + `1/v` `omega_cap` delay peak turn rate by `~0.3 s`[cite: 2], pushing the actual whip down into the middle of the wave (`u ≈ 0.5`). |
| **4. Dropping Down (`theta < 0`)** | `a_slope = -g * sin(phi) * sin(theta) > 0` + full `a_drive`[cite: 2] | Pointing down in the steep mid-wave (`u ≈ 0.5`, `theta < 0`) yields maximum downhill gravity acceleration PLUS re-engages `a_drive` as `cos(theta)` rises above `0`[cite: 2], rocketing the surfer down the middle of the wave. |
| **5. Spray Trigger (`power`)** | `power = speed * sharpness * (1 + 0.5 * lip_hit)`[cite: 2] | Multiplying by *instantaneous* `speed`[cite: 2] means if the surfer slows down at the top, spray dies; when he accelerates in the middle of the wave on the way down, `speed * sharpness` peaks! Real spray is driven by **kinetic energy dumped (`-dv/dt` and entry speed)** at the apex. |

---

## 2. Phase-by-Phase Cutback & Top-Turn Physics Overhaul (`rider.gd`)

### 2.1 New State Variables in `rider.gd`
Add these state variables to track the 4-phase hydrodynamic energy cycle:

```gdscript
var bottom_turn_charge: float = 0.0   # 0..1 stored rail/fin compression from bottom turn
var v_entry_peak: float = 0.0         # Latched peak speed entering the climb/top turn (m/s)
var apex_gouge: float = 0.0           # 0..1 active cutback/top-turn energy dump at the top
var apex_hang_timer: float = 0.0      # Brief stall/suspension timer at the cutback apex (s)
var post_cutback_float: float = 0.0   # 0..1 buoyant float-down state after releasing energy at the top
var prev_v: float = 0.0               # Previous frame speed to measure -dv/dt kinetic energy dump
var decel_impulse: float = 0.0        # Low-passed deceleration spike (-dv/dt in m/s^2) for spray
```

### 2.2 Phase 1: "Explode Up" — Bottom-Turn Slingshot & Upward Jet Projection
In real surfing, carving at the bottom of the wave loads the fins and rail against the upward-rushing water sheet (`D(d, u)`). Pointing up the face (`theta > 0`) releases that stored compression and rides the upward water jet to **accelerate up the wall**:

1. **Compute `bottom_turn_charge` and Upward Projection Thrust (`a_up_jet`):**
```gdscript
# 1. Charge compression when carving or loaded in the lower/mid wave (u < 0.48)
var low_face: float = 1.0 - smoothstep(0.28, 0.55, u)
if low_face > 0.1 and (omega > 0.4 or load_g > 1.15 or sin(theta) > 0.2):
    var charge_rate: float = (
        0.8 * clamp(omega / 2.5, 0.0, 1.0)
        + 0.7 * clamp(load_g - 1.0, 0.0, 1.0)
        + 0.5
    ) * (0.4 + 0.6 * W)
    bottom_turn_charge = clamp(bottom_turn_charge + charge_rate * dt * 3.2, 0.0, 1.0)
else:
    bottom_turn_charge = move_toward(bottom_turn_charge, 0.0, dt * 1.1)

# 2. Upward Hydrodynamic Projection (Explode Up!)
var climbing: float = clamp(sin(theta), 0.0, 1.0)
var climb_window: float = 1.0 - smoothstep(0.68, 0.90, u) # Accelerates all the way up to the top zone
# Upward-rushing water + stored bottom-turn charge overpower static uphill gravity (-g*sin(phi)*sin(theta)):
var a_up_jet: float = climbing * climb_window * (
    g * sin(phi) * 1.18                                         # Cancels uphill gravity brake + net upward lift
    + (3.8 + 5.2 * bottom_turn_charge) * (0.35 + 0.65 * D_draw) # Explosive projection burst up the wall
)

# Expend bottom_turn_charge as it propels the surfer into the upper face
if climbing > 0.25 and u > 0.35:
    bottom_turn_charge = move_toward(bottom_turn_charge, 0.0, dt * 1.8)
```

2. **Un-Choke Vertical Climb Rate `rise` (`§5.2`):**
Replace `sin(phi)` in `rise = (v * sin(theta) * sin(phi) + v_draw) / H`[cite: 2] with `face_arc_factor = lerp(0.72, 1.0, sin(phi))` and a climb projection boost so the surfer shoots briskly up both the pocket wall and the shoulder:
```gdscript
var face_arc_factor: float = lerp(0.72, 1.0, sin(phi))
var climb_boost: float = 1.0 + 0.35 * climbing * (1.0 - smoothstep(0.65, 0.88, u))
var rise: float = (v * sin(theta) * face_arc_factor * climb_boost + v_draw) / H

# Latch peak entry speed achieved during the climb so the apex cutback knows how much energy to release
if climbing > 0.2 and u < 0.78:
    v_entry_peak = max(v_entry_peak, v)
else:
    v_entry_peak = move_toward(v_entry_peak, v, dt * 1.2)
```

### 2.3 Phase 2: "Come to a Stop at the Top" — Zero-Lag Whip & Apex Energy Dump
When the surfer reaches the upper wave (`u > 0.46` on the shoulder or `u > 0.60` in the pocket) and initiates a cutback or top turn (`theta* < theta` or `omega < 0`), **all kinetic energy must release right at the top** before he drops back down.

1. **Detect the Apex Cutback / Top Turn (`apex_gouge`):**
```gdscript
# Top zone starts lower on the sloped shoulder (u = 0.46) and higher on the steep pocket wall (u = 0.60)
var top_zone_start: float = lerp(0.60, 0.46, sigma)
var in_top_zone: float = smoothstep(top_zone_start, top_zone_start + 0.18, u)

# Detect turning down/back from a climb or high trim
var turn_down_intent: float = clamp((theta - theta_star) / 0.75, 0.0, 1.0)
var active_top_carve: float = clamp(-omega / 2.2, 0.0, 1.0)
var apex_trigger: float = in_top_zone * max(turn_down_intent, active_top_carve) * smoothstep(-0.85, 0.15, theta)

apex_gouge = move_toward(apex_gouge, apex_trigger, dt * (9.0 if apex_trigger > apex_gouge else 3.5))
```

2. **Remove Turn-Rate Lag at the Top (`light`, `omega_n`, and `omega_cap`):**
Update the steering/lean equations (§5.4)[cite: 2] so the board unweights and whips around **immediately at the top** instead of lagging into the mid-face:
```gdscript
# Include apex_gouge in 'light' so shoulder cutbacks (u = 0.48..0.78) unweight and engage tail pivot immediately!
var light: float = max(
    max(clamp((1.0 - load_g) / 0.5, 0.0, 1.0), steep),
    max(smoothstep(0.75, 0.88, u), apex_gouge * 0.92)
)

# Boost 2nd-order lean response speed from 8.0 to 18.0 rad/s during an apex gouge to eliminate rail-roll lag
var omega_n_eff: float = lerp(8.0, 18.0, apex_gouge)
lean_vel += (omega_n_eff * omega_n_eff * (lean_target - lean) - 2.0 * omega_n_eff * lean_vel) * dt
lean_vel = clamp(lean_vel, -5.2, 5.2)

# Relax omega_cap at the apex so high entry speed DOES NOT force a wide, slow radius down into the mid-wave
var omega_cap_eff: float = lerp(omega_cap, 5.8, apex_gouge)
```

3. **Dump All Kinetic Energy at the Apex (`a_apex_dump` & `apex_hang_timer`):**
Convert upward speed into a sharp deceleration spike right at the top, lowering the speed floor from `0.45 * V_p`[cite: 2] down to **`0.16 * V_p`** and holding a brief `~0.2 s` apex suspension:
```gdscript
# Target stall speed at the apex of a cutback (0.16..0.24 V_p)
var v_stall_target: float = (0.16 + 0.08 * (1.0 - sigma)) * V_p
var excess_top_speed: float = max(0.0, v - v_stall_target)

# Hard rail-gouge braking force at the top of the wave
var a_apex_dump: float = -14.5 * apex_gouge * (0.4 + 0.6 * clamp(abs(omega) / 3.0, 0.0, 1.0)) * excess_top_speed

if apex_gouge > 0.35:
    apex_hang_timer = max(apex_hang_timer, 0.24 * apex_gouge)
    post_cutback_float = 1.0

if apex_hang_timer > 0.0:
    apex_hang_timer = max(0.0, apex_hang_timer - dt)
    # Pause vertical u motion briefly at the apex as the tail blows out
    rise *= lerp(1.0, 0.18, clamp(apex_hang_timer / 0.20, 0.0, 1.0))
```

### 2.4 Phase 3: "Float Down with the Wave and Gravity" — Eliminating Mid-Wave Acceleration
Once the energy is released at the top, the surfer must **float down with the wave and gravity** rather than accelerating down the middle of the face:

```gdscript
# Decay post_cutback_float only after the surfer drops near the trough (u < 0.28) or finishes leveling out
if apex_gouge < 0.2:
    var decay_rate: float = 1.15 if u > 0.28 else 2.8
    post_cutback_float = move_toward(post_cutback_float, 0.0, dt * decay_rate)

var dropping: float = clamp(-sin(theta), 0.0, 1.0)

# 1. Shut off forward wave drive (a_drive) while dropping down the face or floating out of a cutback!
# Wave drive should only pull the surfer when trimming along the line or driving out of the bottom.
var drive_drop_mask: float = (1.0 - 0.85 * dropping) * (1.0 - 0.85 * post_cutback_float)
a_drive *= drive_drop_mask

# 2. Buoyant Planing Float on the Descent (replaces raw downhill snowboard gravity):
# Dropping against the upward-rushing water sheet cushions downhill acceleration and caps float speed.
var g_down_eff: float = lerp(g, 3.2, max(post_cutback_float, 0.65 * dropping))
var a_slope_down: float = g_down_eff * sin(phi) * dropping
var v_float_cap: float = lerp(0.95, 0.52, post_cutback_float) * V_p
var float_drag: float = -7.5 * dropping * max(0.0, v - v_float_cap)

var a_slope_final: float = a_up_jet if sin(theta) >= 0.0 else (a_slope_down + float_drag)

# 3. Gravity/Wave Descent Drift in u:
# Even when board speed v is very low (0.18..0.48 V_p) after stalling at the top, gravity gently floats
# the surfer down the face in u so he descends smoothly with the wave instead of sticking high on the wall.
var gravity_float_u: float = -0.38 * sin(phi) * max(post_cutback_float * 0.8, dropping) * (1.0 - apex_gouge * 0.7)
rise += gravity_float_u

# 4. Integrate Speed with Dynamic Stall Floor (0.16 V_p at apex vs 0.42 V_p in normal trim)
var v_min_floor: float = lerp(0.42, 0.16, max(apex_gouge, post_cutback_float * 0.75)) * V_p
v = clamp(v + (a_slope_final + a_drag + a_pump + a_drive + a_apex_dump) * dt, v_min_floor, 2.1 * V_p)

# 5. Track Instantaneous Kinetic Energy Dump (-dv/dt) for the Spray Engine
var inst_decel: float = max(0.0, (prev_v - v) / max(dt, 0.001))
decel_impulse = max(inst_decel, decel_impulse * exp(-dt / 0.12))
prev_v = v
```

---

## 3. Energy-Dump Coupled Spray System (`surfer_spray.gd` & `rider.gd`)

### 3.1 Replace Instantaneous Speed with Kinetic Energy Released (`-dv/dt`)
In `wave-and-spray-model.md` (§6.1), `power = speed * sharpness * (1 + 0.5 * lip_hit)`[cite: 2] fails during a realistic cutback because `speed` drops near zero at the apex and increases on the way down.
Update `power` so it is driven by **entry speed (`v_entry_peak`) + rate of deceleration (`decel_impulse = -dv/dt`) at the top of the wave**, and **damped during the post-cutback float down**:

```gdscript
# Normalized entry speed carried up into the turn (0..1.2)
var entry_speed_norm: float = clamp((v_entry_peak - 0.4 * V_p) / (1.3 * V_p), 0.0, 1.2)
# Normalized kinetic energy dump rate (-dv/dt in m/s^2, where ~9.5 m/s^2 is a full apex stall)
var dump_norm: float = clamp(decel_impulse / 9.5, 0.0, 1.4)

# Quiet the spray while floating down the middle of the wave after a cutback
var float_down_quiet: float = 1.0 - 0.65 * post_cutback_float * (1.0 - apex_gouge)

# Effective speed term for spray generation: peaks when dumping speed at the apex!
var effective_spray_speed: float = max(
    speed * float_down_quiet,
    (0.55 * entry_speed_norm + 0.75 * dump_norm) * max(apex_gouge, lip_hit)
)

var power: float = effective_spray_speed * sharpness * (1.0 + 0.90 * apex_gouge + 0.65 * lip_hit)
```

### 3.2 Continuous Rail Curtain + Apex Detonation (`surfer_spray.gd`)
1. **Never Miss the Apex Detonation:**
   - Trigger an immediate high-density **Apex Burst** whenever `apex_gouge > 0.60` and `dump_norm > 0.45` (or whenever `power` rises `0.12` above the previous burst), bypassing any cooldown[cite: 1, 2].
   - Optionally emit micro-slices every `0.055 s` (18 Hz) across a 6-emitter ring pool while `power > 0.18` so a roundhouse cutback paints a continuous sweeping 120-degree ribbon of white water[cite: 1].
2. **Boost Apex Cutback & Lip-Hit Plumes:**
   - When `max(apex_gouge, lip_hit) > 0.5`, apply up to a **1.6x droplet count multiplier** and **1.35x launch velocity multiplier**[cite: 1], and bias the 3D ejection vector upward and over the back of the crest `(0.25, 0.85, -0.45)`[cite: 1, 2]:
     ```gdscript
     var crest_loft: float = max(lip_hit, 0.75 * apex_gouge)
     var dir_3d: Vector3 = (-0.45 * f + 0.85 * (-sign(omega)) * s + (0.35 + 0.65 * crest_loft) * n).normalized()
     dir_3d = dir_3d.lerp(Vector3(0.25, 0.85, -0.45).normalized(), crest_loft * 0.75).normalized()
     ```
   - Because the surfer stalls (`v ≈ 0.18 * V_p`) and hangs for `~0.2 s` at the top while this plume fires, the giant spray fan blasts high over the crest and hangs in the sunset air while the surfer floats effortlessly down underneath it[cite: 1].
3. **Break Up the Rigid 30-Spoke Wheel & Keep Linear Pixel Drag:**
   - Add per-ray angular jitter `angle_i = base_angle_i + randf_range(-0.4, 0.4) * ray_step` and shape the initial speed profile across the fan `v_i = v_peak * (1.0 - 0.35 * pow(abs(ray_norm), 1.6))` so the fan forms a crescent sheet rather than rigid bicycle spokes[cite: 1].
   - Ensure `CPUParticles2D.damping_min = 220.0 * ppm_scale` and `damping_max = 480.0 * ppm_scale` (`px/s^2`) so fast-launched spray decelerates into hanging mist[cite: 1, 2].

---

## 4. Remaining Visual & Surface Upgrades (From Argon's Spec §7b Follow-Ups)

These items were noted in `wave-and-spray-model.md` (§7b) as high-value follow-ups not yet merged[cite: 1, 2]:

### 4.1 Quadratic Bezier Lip Vertex Morph (`wave3d.gdshader`)
Currently, `V_yz' = V_yz + (LIFTED - V_yz) * lift + (LANDED - V_yz) * fall` interpolates linearly across the chord of the lip arc[cite: 1, 2]. Replace with a 3-key quadratic Bezier evaluation in `wave3d.gdshader` `vertex()` so every lip vertex traces a true parabolic overturning trajectory with zero extra attributes[cite: 1]:

```glsl
vec2 p0 = lifted_yz;
vec2 p2 = landed_yz;
// Control point P1 ensures the parabola passes through thrown_yz at u_t = 0.5
vec2 p1 = 2.0 * thrown_yz - 0.5 * (p0 + p2);
float u_t = smoothstep(0.0, 0.68, lip_phase);
vec2 ballistic_yz = mix(mix(p0, p1, u_t), mix(p1, p2, u_t), u_t);
float recover = smoothstep(0.68, 1.0, lip_phase);
vec2 final_yz = mix(ballistic_yz, p0, recover);
VERTEX.yz = mix(VERTEX.yz, final_yz, lip_amount);
```

### 4.2 Translucent Lip Backlight Silhouette Inside the Tube (`surfer3d.gdshader`)
To fix the draw-order limitation where an overhanging lip hides the surfer inside the barrel (§5.6, §7.6)[cite: 1, 2]:
- Add a lightweight `next_pass` / `material_overlay` shader on the 3D surfer's `MeshInstance3D` with `render_mode unshaded, depth_test_inverted, depth_draw_never, blend_mix;`[cite: 1].
- When the 3D wave lip is in front of the surfer in the shared `WaveStage` depth buffer (`depth_test_inverted` passes), render the surfer as a soft dark-teal / sunlit-aqua refracted silhouette (`alpha = 0.42`) with a warm gold rim[cite: 1].

### 4.3 Advected 3D Whitewater Carve Track (`WaveCarveTrail` in `WaveStage`)
Currently, the surfer leaves no mark on the 3D wave mesh (§5.6)[cite: 1, 2]. Add a 32-node ring buffer in wave coordinates `(d_i, u_i, width_i, alpha_i)` sampled every `0.04 s` at the surfboard tail[cite: 1]:
1. **Width Coupled to Apex Gouge:** Set `width_i = lerp(0.16, 1.05, clamp(max(power, apex_gouge) * 1.5, 0.0, 1.0))`[cite: 1]. The trail draws a thin wake during the fast climb, expands into a wide `1 m` whitewater gouge right at the top of the cutback, and tapers to a light track during the float down.
2. **Advect with the Wave Face Each Frame:**
   - `d_i += (-V_p) * dt`[cite: 1]
   - `u_i += (v_draw_at(d_i, u_i) / max(1.2, wave.crest_height_at(d_i))) * dt`[cite: 1]
   - `width_i += 0.25 * dt`[cite: 1]
3. **Render as a 64-Vertex Triangle Strip:** Project `(d_i, u_i)` onto `wave.surface_point(d_i, u_i) + wave.surface_normal(d_i, u_i) * 0.03` using `foam_lit` / `foam_shade` speckled edge shading so the carved whitewater gouge rides up the face and pitches over the falls with the lip[cite: 1].

---

## 5. Step-by-Step Implementation & Verification Checklist

1. **Step 1 (`rider.gd` — 4-Phase Cutback & Top-Turn Physics):**
   - Add `bottom_turn_charge`, `v_entry_peak`, `apex_gouge`, `apex_hang_timer`, `post_cutback_float`, `prev_v`, and `decel_impulse`.
   - Implement `a_up_jet` and the `face_arc_factor` fix in `rise` so pointing up (`theta > 0`) accelerates the surfer up the wave face.
   - Implement `apex_gouge`, expand `light`, increase `omega_n_eff` to `18.0 rad/s`, relax `omega_cap_eff` to `5.8 rad/s`, lower `v_min_floor` to `0.16 * V_p`, and apply `a_apex_dump` + `apex_hang_timer` so the surfer comes to a near-stop and whips the board around at the top of the wave.
   - Implement `post_cutback_float`, mask out `a_drive` on the drop (`drive_drop_mask`), and apply buoyant planing float (`g_down_eff`, `float_drag`, `gravity_float_u`) so the surfer floats down with the wave and gravity without mid-wave acceleration.
2. **Step 2 (`surfer_spray.gd` & `rider.gd` — Energy-Dump Spray Coupling):**
   - Pass `v_entry_peak`, `decel_impulse`, `apex_gouge`, and `post_cutback_float` from `rider.gd` to `SurferSpray`.
   - Replace raw `speed` in `power` with `effective_spray_speed` so the biggest spray explosion triggers from the kinetic energy dump (`-dv/dt`) at the top of the cutback and stays quiet while floating down the middle of the wave.
3. **Step 3 (`wave3d.gdshader`, `surfer3d.gdshader`, `wave_carve_trail.gd`):**
   - Add the quadratic Bezier 3-key lip vertex morph in `wave3d.gdshader`[cite: 1].
   - Add the `depth_test_inverted` translucent lip silhouette pass on `surfer3d.gdshader`[cite: 1].
   - Add the 32-node advected `WaveCarveTrail` mesh ribbon in `WaveStage`[cite: 1].
4. **Step 4 (Automated Telemetry Test in `tests/run_tests.gd`):**
   - Run `godot_console --headless --path game --script res://tests/run_tests.gd`[cite: 1] with a cutback maneuver test (`u: 0.20 -> 0.78 -> 0.30`) asserting that:
     a) Peak speed `v_max` occurs during the upward climb (`u in [0.35, 0.72]`, `theta > 0`).
     b) Minimum speed `v_min < 0.28 * V_p` and peak turn rate `|omega|_max` occur in the upper zone (`u > 0.58`), **not** in the mid-face (`u < 0.50`).
     c) Peak spray `power` fires within `0.12 s` of the apex deceleration peak (`decel_impulse` at `u > 0.58`), and mid-wave descent speed (`u in [0.35, 0.55]`, `theta < 0`) stays below `0.70 * V_p`.