# Step 10 spec: arcade carving physics and continuous 3D pose blending

Saved from the design discussion so nothing is lost between contexts. It replaces clip-based moves and the pure
target-position spring in `rider.gd`. Starting values are only starting values: tune by feel, expose in `data/tuning.tres`.

## Open points before building
- `WaveModel` has no `barrel_amount_at(d, u)`; add it from `zone_at()` and `barrel()`.
- How input sets `target_theta` (mouse, trackpad, touch) is the key design call; this spec does not say.
- Re-run `tools/calibrate.ps1` and `tools/replay.ps1` once the mapping exists.

## State
- `d`: meters ahead of the peel point (`+d` is the open shoulder, screen left). `u` in 0..1: height on the face (0 trough, 1 crest).
- `theta` in [-1.45, 1.55] rad: board heading in the face plane. 0 is down the line toward `+d`; negative points down the face; positive points up it.
- `omega` = d(theta)/dt in rad/s (positive carves up on the inside rail, a bottom turn; negative carves down, a top turn or cutback).
- `speed` along the heading in m/s. `compression` in 0..1 (0 tall, 1 fully crouched).

## Lead-and-follow springs (instant input, heavy body)
Lag over 100 ms on the main steering cue feels sluggish; none on the whole body feels weightless. Three timescales:
1. Head, shoulders and upper torso (0 to 20 ms): `lead_delta = clamp(target_theta - theta, -0.8, 0.8)` twists neck, head and upper spine on the first frame.
2. Board heading (about 50 ms, critically damped, wn = 18, zeta = 1):
   `speed_auth = clamp(remap(speed, MIN_SPEED, MAX_SPEED, 0.55, 1.15), 0.55, 1.15)`
   `theta_accel = (324 * (target_theta - theta) - 36 * omega) * speed_auth`
   `omega = clamp(omega + theta_accel * dt, -MAX_OMEGA, MAX_OMEGA)`; `theta = clamp(theta + omega * dt, -1.45, 1.55)`
3. Compression (about 120 ms, slightly underdamped, wn = 10, zeta = 0.85):
   `target_crouch = clamp(0.22 + abs(omega) * 0.25 + barrel_proximity * 0.65 + manual_crouch_input * 0.5, 0.1, 1.0)`
   `c_accel = 100 * (target_crouch - compression) - 17 * compression_vel`; integrate velocity then position, clamp 0..1.

## Energy exchange (each physics step)
- Slope gravity: `a_slope = -G_EFF * sin(wave.face_angle(u)) * sin(theta)` (dropping down gains speed, climbing trades it for height).
- Drag: `a_drag = -K_WATER * speed^2 - K_CARVE * abs(omega) * speed` (bleeds energy into spray in sharp snaps).
- Pump: `a_pump = K_PUMP * abs(omega) * max(0, -compression_vel) * max(0, 1 - abs(u - 0.45) * 1.8) * max(0.2, cos(theta))`.
- `speed = clamp(speed + (a_slope + a_drag + a_pump) * dt, MIN_SPEED, MAX_SPEED)`.
- Wave draw: `v_draw = V_DRAW_BASE * clamp(wave.crest_height_at(d) / 2.5, 0.4, 1.3)`; `face_h = max(1.2, wave.crest_height_at(d))`.
- Integrate the wave manifold: `d += (speed * cos(theta) - wave.peel_speed()) * dt`; `u += ((speed * sin(theta) + v_draw) / face_h) * dt`.
- Soft boundaries: near the trough (`u < 0.12`, `theta < 0`) a scoop torque nudges `theta` toward 0. Near the crest (`u > 0.92`, `theta > 0`) a bank torque nudges it toward 0 into a floater or top turn, unless the air launch condition holds (`u >= 0.98`, `theta > 0.65`, `speed > 8.5`).

## Starting constants
`MIN_SPEED 2.2`, `MAX_SPEED 12.5`, `TRIM_SPEED 6.5` (m/s); `MAX_OMEGA 4.5` rad/s; `G_EFF 11.5`; `K_WATER 0.035`, `K_CARVE 0.12`, `K_PUMP 1.8`; `V_DRAW_BASE 1.1` m/s.

## Placing and posing the 3D surfer
- `pos = wave.surface_point(d, u)`, `n_surf = wave.surface_normal(d, u)`. `t_crest = (-1, 0, 0)` (down the line), `t_face = n_surf x t_crest` (up the face), then re-orthonormalise `t_crest`.
- `forward = t_crest * cos(theta) + t_face * sin(theta)`. Rail roll about `forward`: `rail_roll = clamp(omega * speed * 0.038, -0.78, 0.78)` (about 45 degrees max).
- Pose weights (blend bone rotations per bone with `Quaternion.slerp` from the baked pose library):
  `w_bottom_turn = clamp(omega/2.2, 0, 1) * clamp(1-u, 0.2, 1)`; `w_top_turn = clamp(-omega/2.0, 0, 1) * clamp(u, 0.3, 1)`;
  `w_cutback = clamp(-omega/2.5, 0, 1) * clamp((d-2)/3, 0, 1)`; `w_vert_snap = clamp(theta/1.1, 0, 1) * clamp(-omega/2.2, 0, 1) * clamp((u-0.65)/0.3, 0, 1)`;
  `w_barrel = barrel_amount_at(d, u) * clamp(compression, 0.4, 1)`; `w_crouch = compression * (1 - w_barrel)`.
- Layer `lead_delta` as a twist on the neck, head and upper chest so the upper body leads every carve.

## Earned move labels (they drive spray, never clips)
`wipeout` (committed, cancellable recovery); `air` (committed parabola above `u > 1`, steerable `theta`); `barrel` (tube zone, deep compression);
`floater` (`u > 0.90`, `abs(theta) < 0.35`); `hit_the_lip` (`u > 0.72`, `theta > 0.65`, `omega < -1.8`, biggest spray fan);
`bottom_turn` (`u < 0.45`, `omega > 1.0`, `speed > 5`); `cutback` (`u > 0.50`, `omega < -1.2`, `d > 3.5`); `top_turn` (`u > 0.55`, `omega < -1.1`); `trim` otherwise.
Spray: `strength = clamp((speed / MAX_SPEED) * (abs(omega) / 3.0), 0, 1)` into `SurferSpray.burst`.
