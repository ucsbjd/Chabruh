# Chabruh: how the wave, the surfer's interaction with it, and the spray are modelled

Paste-ready summary for review. Goal of the review: find ways to make the wave and spray more physically
and visually realistic. All numbers below are the constants in the code (Godot 4.7, GDScript, GLSL-like
shaders, Compatibility/WebGL2 renderer, must run at 60 fps on a phone in the browser).

Notation: `S(a,b,x)` = smoothstep(a,b,x) = 3t²−2t³ with t = clamp((x−a)/(b−a),0,1); `S(x)` means S(0,1,x).
`lerp(a,b,t)=a+(b−a)t`. Units are meters, seconds, radians unless a degree sign is shown.

---------------------------------------------------------------------------------------------------

## 0. Big picture

* A **2D side-view surf game** (sunset, flat-vector, "Over the Hill" look) where the **wave body is a small
  real 3D mesh** drawn into a transparent SubViewport and composited as a 2D layer. Sky, ridges, palms, spray
  particles and grading are 2D. The surfer is a skinned 3D character in the same 3D stage (shares the depth
  buffer with the wave).
* The wave is **not a fluid simulation**. It is a **parametric 2.5D model**: one 2D cross-section (a closed-form
  curve in the plane across the crest) that is a function of a single scalar **d** = distance along the crest
  ahead of the **peel point** (the point where the wave is breaking right now). The mesh is that section swept
  along the crest. The surfer lives on that surface in coordinates (d, u).
* The point of the design: the **same functions** give the shader its geometry, give gameplay an exact surface
  (position + normal + slope) to ride, and give the spray its emission points, so they cannot disagree.
* Time dependence is only (a) the surfer moving through d (the wave itself is a static function of d; the
  camera follows the surfer), and (b) a **shader-only animation** of the lip (3-key vertex morph) and
  whitewater heave. The mesh is never rebuilt per frame.

World axes: x runs along the crest and **x = −d**, y is up, z points toward the beach and camera.
Surfer travels toward +d (screen left), regular stance, seen from behind. Camera: telephoto (21° vertical FOV,
19 m back), looks down the line (yaw ≈ +30°), horizon at 0.40 of the screen height.

---------------------------------------------------------------------------------------------------

## 1. Wave parameters and the outer envelope (functions of d)

Inputs (all 0..1 dials plus two physical constants):

```
size s ∈ [0,1]            hollowness h ∈ [0,1] (0 spilling, 1 plunging)
celerity c = 5 m/s        peel angle α = 40°   (rideable 30–50°, <27° too fast)

Peel speed (Walker 1974):  V_p = c / sin α            = 7.78 m/s  (the break's speed along the crest)
Base height:               H0 = lerp(1.4, 4.4, s)     (0.8 to 2.4 surfer heights; surfer = 1.8 m)
Barrel amount:             B  = S(0.55,0.90,h) · S(0.35,0.80,s)          (needs hollow AND big)
Shoulder length:           L_s = lerp(30, 46, s)
```

Everything else is multiplied onto the height:

```
taper     T(d) = 1                                         d ≤ 0
                 1 − 0.15·S(0,16,d) − 0.55·S(0.35 L_s, L_s, d)   d > 0  (two stages: the playable wall keeps ~87% of its
                                                                       height for the first dozen meters, then settles
                                                                       toward open swell, 30% at the shoulder's end)
collapse  C(d) = 1                                         d ≥ 0
                 [1 − (1 − 0.16)·S(−d / 4.5)] · [1 − S(15,30,−d)]   d < 0   (wall falls apart into whitewater over 4.5 m,
                                                                            then fades out 15–30 m behind)
roll      R(d) = 1 + 0.06 sin(0.31 d + 0.7) + 0.035 sin(0.83 d + 2.1)       (so the crest is never ruler straight)
peak      P(d) = 1 + 0.10 · exp(−((d − 1.5)/6)²)                              (highest point just ahead of the break)

Crest height above trough:  H(d) = H0 · T · C · R · P
```

Other 0..1 fields of d (used by the section builder, shaders, spray and gameplay):

```
throw (lip activity) τ(d) = 1 − S(d / 9)            d ≥ 0      (lip builds over 9 m ahead of the break)
                            1 − S(2.8, 7, −d)       d < 0      (lip persists ~7 m behind it)
curl             κ(d) = τ(d) · lerp(0.18, 1.0, B)               (even a spiller keeps 18% lip)
foam             f(d) = 1 − S(−4, lead, d),   lead = lerp(4, 0, B)      (spillers foam ahead of the break, plungers only behind)
whitewater       W(d) = 0 (d ≥ 0);  S(−d/4.5) · (1 − S(15,30,−d))  (d < 0)
shoulder         σ(d) = S(5, 0.75 L_s, d)      (0 on the wall/pocket, relaxing from 5 m ahead, fully by ~30 m)
draw             D(d,u) = clamp(H/2.5, 0.4, 1.3) · (1 − 0.65σ) · lerp(0.55, 1, S(0,0.35,u)) · (1 + 0.45 τ S(0.5,0.9,u))
                          (how hard the water rises up the face: strongest in the pocket and up by the throwing lip,
                           weaker at the foot, calm down the shoulder; × v_draw_base = 1.1 m/s)
push (power)     W(d) = T(d) · (1 − 0.85σ) · lerp(1, 0.6, whitewater)     (how much the wave drives a surfer along at d)
mist (spray amt) m(d) = clamp(0.18·T + 0.82·exp(−((d+1)/5)²) + 0.6·W, 0, 1)
face angle       φ(u) = lerp(15°, lerp(55°, 88°, h), u²)        (from horizontal; gentle at base, steep near crest)
zones: SHOULDER d>3.8 | POCKET −0.4≤d≤3.8 | BARREL (B>0.35 and d>−7) | WHITEWATER otherwise
barrel_amount(d,u) = B · (1 − S(0.35, 0.70, u)) inside the barrel zone (only low on the face, under the lip)
```

---------------------------------------------------------------------------------------------------

## 2. The cross-section (the real "shape" of the wave)

For a given d, a 2D polyline in the (z, y) plane is built from H = H(d), κ = κ(d), foam, trough position.
There are 4 parts. For a full barrel (κ=1) it is geometrically an **almond-shaped tube**, wider than high (New 1983
found the region under an overturning crest is close to a √3-aspect ellipse; we use a = 1.4):

```
lip thickness (at crest)  t   = H · lerp(0.025, 0.14, κ^0.7)         tip thickness t_tip = 0.012 H
barrel radius (height)    r   = κ · 0.43 · H
aspect                    a   = lerp(1, 1.4, S(0.2, 1, κ))           (round for a shallow curl, almond for a full barrel)
tube centre height        c_y = H − r − t           (ellipse centre is at z = a·r, y = c_y)
arc point                 A(ρ,θ) = ( a·r + a·ρ cosθ ,  c_y + ρ sinθ )

1. Back slope: cubic Bezier from (−3.2 H, 0) to the start of the outer arc A(r+t, 105°),
   tangent-matched (control pts: +0.55·3.2H along z, and −0.28·3.2H along the arc tangent).   12 points.
2. Outer arc over the crest and out along the lip: θ goes 105° → θ_tip = lerp(90°, −40°, κ),
   radius tapers  ρ(τ) = r + t_tip + (t − t_tip)·(1 − τ)^0.8,  τ∈[0,1].                          16 points.
   (θ_tip = −40° means the thrown lip points forward/down past the trough: it is a ballistic-looking jet.)
3. Inner arc back under the lip = barrel roof, ρ = r, θ from θ_tip → 180°.                         18 points.
4. Face: cubic Bezier from face_top = (0, c_y) to the trough (z_tr, 0). In the pocket (σ = 0) it is concave, control
   points face_top + (0, −c_y·0.5523) and trough − (z_tr·0.5523, 0) (0.5523 = quarter-circle constant; at κ=1 it is the
   tube's quarter-ellipse floor). Down the shoulder it rounds over like an unbroken swell: the controls blend to
   face_top + (0.32 z_tr σ, −c_y·lerp(0.5523, 0.22, σ)) and (z_tr(1 − lerp(0.5523, 0.42, σ)), 0.08 c_y σ),
   convex at the top and easing into a gentle slope at the foot.                                10 points.

Trough (foot of the wave) z-position:
   run   = H · lerp(2.0, 1.1, h) · (1 + 0.9·σ(d))             (face runs longer and gentler down the shoulder; steeper if hollow)
   z_tr  = lerp(run, a·κ·0.43·H, κ)                            (a full barrel pulls the foot in to the tube's width)
```

Per-vertex shading attributes stored alongside: height fraction y/H, foam, "cavity" (depth inside barrel),
translucency (thin water → glows). Base slope is only a Bezier; the face is a smooth curve; there is no
breaking-wave hydrodynamics (no velocity field, no true overturning dynamics) - the lip is a stylised
analytic jet.

### Lip landing point (where the spit happens)
```
lip_landing(d) = ( x = −d,  y = 0,  z = z_tip + y_tip · 0.7 )     (tip keeps travelling toward the beach 0.7 m per m of remaining height)
```

### Mesh
`WaveMesh` sweeps ~54 stations along d (dense near the break: every 0.5 m from d=−7 to +10, sparse out to
−30 / +60) × 56 points per section. Vertex position = THROWN shape; also stores LIFTED and LANDED shapes in
CUSTOM0 and (lip amount, whitewater amount) in UV2. UV = (meters along outline from lip tip, meters along crest).

---------------------------------------------------------------------------------------------------

## 3. Lip animation and surface motion (vertex shader, no mesh rebuild)

The three shapes are the same section built with modified inputs:
```
LIFTED: H·(1 + 0.06 τ),  κ·0.62          THROWN: H, κ (default)         LANDED: H·(1 − 0.28 τ),  κ·0.80
```
Phase slides along the crest so neighbouring lips are at different points of the cycle (a travelling pattern):
```
phase    φ_L = fract( t / 5.5  +  d / 15 )                      (period 5.5 s, 15 m between lips in the same state)
lift     = [ S(0.86,1,φ_L) + 1 − S(0,0.28,φ_L) ] · τ
fall     = S(0.50,0.66,φ_L) · (1 − S(0.74,0.92,φ_L)) · τ
V_yz'    = V_yz + (LIFTED − V_yz)·lift + (LANDED − V_yz)·fall
crash    = fall   (adds foam high on the face when a lip has just landed)
```
Whitewater heave (vertex): two scrolling noise octaves
`rough = W · foamVertexColour · (0.35 + heightFrac)`;
`Δy = (heave·1.5 + chop·0.7)·rough`, `Δz = (heave·0.9 + chop·0.5)·rough`, with heave/chop sampled from a seamless noise
texture scrolling with time. The sea plane reads a baked 512×1 half-float "profile" texture
(crest height, trough z, curl, foam by d) to put shadow and foam at the wave's base.

Spray lip landing event: the 2D spit fires when `lip_phase(d,t)` crosses **0.68** (see §6).

---------------------------------------------------------------------------------------------------

## 4. Look (how geometry becomes the key-frame image)

Fully unshaded, flat bands (no real lighting):
```
tone = clamp( 0.06 + 0.80·h_frac + 0.18·(lit−0.5) + 0.28·thin − 0.30·cavity + 0.12·warpNoise + 0.10·blotNoise, 0, 1)
lit  = dot(n, sun_dir)·0.5 + 0.5
colour = shadow → deep (edge 0.14) → mid (0.40) → light (0.64) → glint (0.86), each a soft smoothstep edge
sun-through-the-lip  through = S(0.55,1,h_frac)·(0.35+0.65 thin)·(1−cav) → yellow-green glow bands
cell-edge veins (thin lilac network): from a cell distance-field texture, scrolled up the face toward the lip tip
barrel interior: mix to dark violet by 0.8·cav, glowing where thin and high
foam: smoothstep threshold of  foam + drip noise·0.9·(1−0.4h) + blotch·0.25  → cream/violet clumps with speckle
rim line: fresnel·steepness·height, warm yellow; distance haze toward sky colour 45–240 m
```
Pattern scroll: `flow_uv = (UV.x + t·1.1·sign(UV.x), UV.y − t·2.6)` (face texture climbs toward the lip, slides along the crest).

---------------------------------------------------------------------------------------------------

## 5. How the surfer interacts with the wave

### 5.1 Coordinates and what the wave gives the rider
The rider state is **(d, u)**: d = meters ahead of the peel point, u ∈ [0.06, 0.96] = height up the face
(0 = trough, 1 = top; index-linear along the 10-segment face polyline). Each frame the wave supplies:
```
P  = surface_point(d,u) = (−d, y, z_polyline(u))            (the board's contact point)
n  = surface_normal(d,u)  (blended from adjacent points' normals; smooth so the board doesn't jolt)
φ  = acos(n_y)            (local face slope, radians)
H  = crest_height_at(d)   (clamped ≥ 1.2 m for the rise rate)
the break's travel V_p (the wave "moves" past the rider at V_p along d)
```
There is **no feedback from the surfer to the water** (no displacement, no wake on the surface mesh); the wave is
a fixed function of d. The surfer only reads it.

Tangent frame: `t_crest = (−1,0,0)`, `t_face = t_crest × n`, `t_crest ← n × t_face` (orthonormal on the face).
Heading θ in that plane: 0 = down the line, + toward the lip, − toward the trough.
```
f = t_crest cosθ + t_face sinθ      (nose direction)
s = t_face cosθ − t_crest sinθ      (the side a positive turn swings toward)
```

### 5.2 Motion in the (d,u) coordinates
```
run = v cosθ − V_p                     (the wave outruns you unless v cosθ > V_p)
      closing on the curl: run = −1.0 V_p · tanh(−run / 1.0 V_p) · clamp((d + 3)/2.5)   (soft limit, eases to a stop)
      running ahead: run · clamp((16 − d)/2)
d' = d + run·Δt                        within [−3 m, +16 m], never slammed into
rise = ( v sinθ sinφ + v_draw ) / H   face heights per second; v_draw = 1.1·D(d,u) (the water's draw, see section 1)
u'  = u + rise·Δt                     with soft cushions near u=0.06 and u=0.96; in a snap the lip holds the tail
                                      (a falling rise is scaled by 1 − lip_hold) until the nose is round
```
Speed band: `v ∈ [0.45, 2.1]·V_p`, trim speed 1.05·V_p. Gameplay is therefore speed *relative to the wave's own speed*.

### 5.3 Forces / energy (snowboard-style carving model)
```
a_slope = −g sinφ sinθ                        (gravity along the face; g_eff = 9)
a_drag  = −k_w v² − k_carve|ω| v − k_skid |sinθ| v − k_stall·stall·v
          k_w calibrated so the trim heading settles at trim speed mid-wave:  k_w = g sinφ_mid sinθ_ref / v_trim²
a_pump  = k_pump · pump_amount · sinφ · (1 − speed) · W²      (rhythmic strokes add speed; little on the soft shoulder)
a_drive = clamp( 0.5·(v_want − v)·(1 if accelerating else 0.3), ±6 ) · S(−0.1, 0.4, cosθ) · W²
          (it is the wave's push: it fades down the shoulder and does nothing pointed back toward the curl)
v_want  = min( V_p / max(cosθ, 0.35), 1.2·V_trim ) · lerp(0.6, 1, W) + clamp( 0.7·(d_want − d), −0.4 V_p, 0.8 V_p ) · W
v'      = clamp(v + (a_slope + a_drag + a_pump + a_drive)Δt, 0.45 V_p, 2.1 V_p)
```
Energy is **where the face is steep and the water draws hardest** (near the peak, high on the face); the trough is flat
and the shoulder soft, so speed bleeds off out in front and the curl comes back. Carving and pointing across the line
cost speed; a "stall" (steer back) drags; a cutback bleeds 0.6 of its speed a second while coming round.

### 5.4 Steering, lean and turning (the body leads, the board follows)
```
Player input → stick S (radians of heading wanted): S ← clamp(S·fade + push·4.5, ±1.45), then low-pass τ=0.10 s.
   While the gesture is still coming in (pushes < 0.12 s apart) fade = e^(−Δt/0.55); once it stops, what is left holds
   (τ = 3 s) until the board has turned to it or the face has run out that way, then fades with 0.55 s. Pushing the
   other way zeroes S first (a new move).
θ_trim = asin( clamp( (climb − v_draw) / max(v·max(sinφ,0.3), 0.5), ±0.6) )   (heading that just holds the line;
         climb = 0.3 m/s, or near the curl a pull toward a settling height, 0.45, or 0.3 in a barrel)
θ*     = clamp(θ_trim·(1 − |S|/1.45) + S, −1.25 (drop), 1.5)   (a full push points the board the way it was pushed),
         limited to ±0.35 rad when inside the barrel (no room to cross the line), eased to 0 near the bottom (guard on
         time-to-trough) and near the crest (a climb below 49° rounds into a top turn 0.08 to 0.4 s before the top; a
         steeper one is committed: θ* ≥ min(θ, 0.8) until the lip)
Snap: at the lip (S(0.78, 0.9, u) > 0.3), nose no lower than −0.3, the player's wanted heading more than 0.6 below θ
      → commit to θ_snap = min(wanted, −0.6); the lip holds the tail until θ < θ_snap + 0.3; pivot gain 7, τ 0.08 s,
      spin-up ≤ 45 rad/s², up to 6.5 rad/s
Normal load on the feet (g units × g):  p = max( g n_y + press_curve, 0.6 g ),  press_curve = −(dP/dt)·(dn/dt) low-passed 0.15 s
   (the concave face pushes up into him as he rides its curve)
Lean that holds the line:  lean_hold = atan2( g s_y , p )
Grip-limited turn rate cap: ω_cap = min( 3.5 , grip·(1 + 0.35·buried) / max(v,4) ),  grip = 19 m/s²   (faster ⇒ wider turns)
Wanted turn: ω_want = clamp( 2.2·(θ* − θ), ±ω_cap )
Lean the input asks for: lean_asked = atan2( v ω_want + g s_y , p )          (centripetal + gravity balance, skier-like)
"light" (board unweighted, near-vertical face, or at the lip) = max( clamp((1−load_g)/0.5,0,1), steep, S(0.78,0.9,u) )
lean_target = clamp( lean_hold + (lean_asked − lean_hold)(1 − 0.9·light), lean_hold ± 1.15 )
Lean is a 2nd-order system: lean_vel += ( ω_n²(lean_target − lean) − 2ω_n·lean_vel )Δt,  ω_n = 8 rad/s, |lean_vel| ≤ 3.4 rad/s
Carve turn rate: ω_carve = clamp( ( p tan(lean) − g s_y ) / max(v,3), ±ω_cap )
Pivot (tail snap, only when light): ω_pivot → light·( clamp(k(θ*−θ), ±6.5) − ω_carve ), k = 4 (top turn) or 7 (snap,
   foam rebound), τ = 0.15 or 0.08 s, spin-up limited to 10 or 45 rad/s²
ω = ω_carve + ω_pivot ;  θ += ω Δt ;  sharpness = max(|ω|/3, sharpness)·e^(−6Δt)   (feeds the spray)
```
Result: no input can jerk him; "the lean leads and the turn follows". `strain` = max(lean lag/0.7, lean-ask rate/4, load/3g)
is a debug number for "a real surfer would fall here" (never an actual fall).

### 5.5 Balance (centre of mass) and how the body sits on the surface
```
felt   = f · p·tan(pitch) + s·( v ω_carve + g s_y ) + n·p        (apparent gravity at the feet; pitch from along-board drag/pump)
balance = normalize( lerp( normalize(felt), up, 0.7·weightless ) ) ,  load_g = |felt| / g
          weightless = max( clamp(1 − (g n_y + press_curve)/(0.6 g)), lip_hold )   (with hardly any press on a near-vertical
          face, or the lip holding the tail, he stays near upright while the board goes vertical: the J-Bay footage)
board rail roll = clamp( 0.6·carve + 0.3·lean_hold , lean ± 0.7 ) clamped to ±0.7 rad   (carve = lean − lean_hold)
crouch target = clamp( 0.15 + 0.2·speed + 0.45·dropping + load rhythm + 0.65·barrel_amount + 0.35·tuck , 0.05, 1 )
          (2nd-order hips, ~120 ms; dropping = nose down × how fast he is actually descending; tuck = near the curl)
```
The 3D surfer places the board flat on the face (basis from n and heading), rolled onto its rail about its own
length, **pivoting about the back foot** (tail stays on the ridden spot), tilts the body about the feet so the pose's
centre of mass lies along `balance`, runs two-bone leg IK to keep feet planted on the deck, and a lead chain
(front arm → head → chest → hips → board) points where he is about to go. A back hand that drags in a deep
bottom turn spawns hand spray when `dot(wrist − P, n) < touch distance`.

### 5.6 Things the surfer does NOT do (relevant to realism)
* does not deform the water, no board wake geometry, no displacement of the wave
* the lip curtain cannot pass in front of the surfer in the tube (sprite/draw-order limit)
* no wave-on-board forces from real hydrodynamics (planing drag, fin lift, rail bite are collapsed into the
  scalar `a_drag`, `grip`, `ω_cap`)
* the wave is invariant in time except the lip morph; no sets/lulls physics, no wind chop on the face

---------------------------------------------------------------------------------------------------

## 6. The spray model (4 independent systems, all flat white ovals tinted by mood colours)

Rendering: oval textures, `scale_curve` 1 → 0.35 over life, colour ramp: sunlit cream/peach (foam_lit mixed 35% toward
sun_glint) → foam_lit → transparent violet (foam_shade, alpha 0). No lighting, no refraction.

### 6.1 Surfer fan ("the signature effect"), `SurferSpray`, CPUParticles2D, screen-space
Triggered by the rider:
```
power = speed · sharpness · (1 + 0.5·lip_hit)     (speed ∈[0,1], sharpness ∈[0,1] from turn rate; lip_hit = high on the
                                                    face and turning down hard)
a burst when power > 0.22, and another within the 0.45 s pause each time power rises 0.15 above the last one, so
the biggest fan comes at the peak of the turn (the snap at the lip) instead of being locked out by the first.
strength s = clamp(1.9·power, 0, 1)
direction: off the outside of the turn, back along the board and up off the face,
   dir = normalize(−0.45 f + 0.85·(−sign ω)·s + (0.35 + 0.65 lip_hit) n), blended 0.75·lip_hit toward up and back over
   the crest (0.25, 0.85, −0.45); projected to the screen and kept between −165° and +20°.
drag: 1.0 to 2.0 m/s per second (scaled to pixels: Godot's particle damping is a fixed speed loss per second)
```
Fan parameters from s ∈ [0,1]:
```
half-angle   = lerp(18°, 58°, s^0.7) about a centre axis of −40° (up and behind the tail on screen)
launch speed = U[ lerp(1.5,3,s) , lerp(3,8,s) ] m/s · ppm         (ppm = pixels per meter on screen)
lifetime     = lerp(0.55 s, 1.3 s, s)
FAN droplets = lerp(16, 190, s)
EDGE droplets= lerp(0, 90, s²)   half-angle ×1.12, speed ×1.4, lifetime ×0.9, size ×0.6    (fine droplets farther out)
CORE blobs   = lerp(2, 8, s)     half-angle ×0.8, speed ×0.5, lifetime ×0.6, size ×1.1     (heavy near the tail)
rays         = 30 fixed directions across the arc ("spokes"), speed uniform-random per particle, droplet size ×U[0.7,1.4]
a pool of 3 fans can overlap; back layer (fan body + core + wake) is drawn behind the surfer, front layer (edge droplets, splash) in front
```
Particle motion (per droplet), with `g_s = 6 m/s²` (less than real 9.8 on purpose, to keep arcs open):
```
x(t) = x0 + v0 cosα · t ;  y(t) = y0 + v0 sinα · t + ½ g_s t²      (α = ray angle on screen; screen y down)
engine damping 0.7–1.3 per second is applied on top   (NOTE: Godot's `damping` for particles is, to my knowledge, a linear
deceleration in px/s², not an exponential rate, so at these values it may be nearly a no-op. Worth checking if you re-tune.)
```
Also:
* **Wake**: continuous emitter on the tail, amount = 36·lerp(0.2,1,speed), lifetime 1.6 s, drifts backwards at
  ~(0.9–1.25)·(water drift speed); flat "sheet" textures. Not attached to the wave surface.
* **Hand drag**: 40 droplets, lifetime 0.45 s, speed 1.4–3.2 m/s, direction (0.55, −1) ± 24°, only while the hand is down at the face.
* **Splash** (landing after an air): 12→110 droplets, 0.5→0.95 s, speeds 1→(2…4.6) m/s, arc centred straight up ±70°. (Wired but air not built yet.)

### 6.2 Wave "spit" from the barrel mouth, `WaveSpray`, CPUParticles2D
Five fixed spit points along the break, `d ∈ {−0.5, −2.6, −4.7, −7.2, −9.8}`. Each fires **when that lip's phase crosses 0.68**
(the same `fract(t/5.5 + d/15)` the shader uses, so spray and the visible lip landing are in sync):
```
emit point  = project( lip_landing(d) )            (screen position of where the lip lands)
strength    = τ(d) · (0.3 + 0.7 B) · (0.45 + 0.55 s)          (hollow, big waves spit hard; small spillers only puff)
strength    = max(strength, W(d)·(0.45 + 0.4 s))               (behind the break the whitewater itself throws spray)
fires if strength > 0.02:  amount = lerp(12, 64, strength);  speed U[1.4, lerp(2.5,5.2,strength)] m/s;  lifetime 0.95 s
arc centre −122° on screen (forward, up and over) ± 40°, 18 rays;  gravity 6 m/s²
```

### 6.3 Crest mist (3D, in the wave stage): `WaveMist` mesh + `mist3d` shader
A thin 4-row curtain mesh standing on the crest line, only a surface for a procedural droplet shader:
```
columns every 0.75 m from d = −24 to +50
base = crest_point(d);  amount m = mist_at(d)
height of curtain = 0.62·H0·(0.25 + 0.75 m);  top leans 0.35 m per m up (offshore wind pushes it back)
```
Fragment shader (two hashed-cell layers = 6 and 11 cells/m, the second ×0.65 size, carried ×1.5 faster):
```
position in the plane   g = (wpos.xy − wind·t·carried)·cells_per_meter ; wind = (0.8, 1.5) m/s (along the crest, up)
cell hash decides droplet offset/size; it re-rolls "present" at ~2.5 Hz (flicker), so droplets blink in and out
thin  = (1 − up)^1.4         (fewer droplets higher on the curtain)
present = step( flicker , m · thin · (0.62 or 0.42 by layer) )
droplet = anti-aliased oval, stretched 0.55/1.35 along/across the wind, radius lerp(0.30, 0.15, up)·(0.55+0.9 hash)
colour: foam_shade (low, in the wave's shadow) → foam_lit → sun_glint high up; ~14% of droplets glint (blinking)
```

### 6.4 Foam on the surface (shader, not particles)
Foam mask on the wave mesh (§4) and the sea plane: `wash = (1 − S(0, 0.7+4.2 foam, z−z_trough + noise))` — ragged foam
band along the wave's foot driven by the baked profile; plus the dripping foam edge on the face.

---------------------------------------------------------------------------------------------------

## 7. Known simplifications and likely realism gaps (where an outside AI could help)

1. **Wave shape is a fixed closed-form section, a function of d only.** There is no variation across the wave's
   direction of travel other than d, no 3D breaking dynamics, no sets, no secondary swells/chop on the face, no
   backwash, no wave–wave interaction. The "lip" is a hand-built arc plus 3-key vertex morph (lifted/thrown/landed).
2. **Real physics used**: peel speed = c/sin α; qualitative steepness vs seabed → barrel roundness; lip as ballistic jet
   (only roughly: the landing point is a fixed 0.7 m per m heuristic, not a trajectory solve).
   **Not used**: shoaling (Green's law), Miche/breaking criterion H/h≈0.78, Iribarren number for spilling/plunging
   from beach slope & wave steepness, Boussinesq/Serre–Green–Naghdi shape, orbital velocities in the face, offshore
   wind effect on lip, wave period/wavelength relation.
3. **Surfer ↔ wave is one-way.** No rail/fin hydrodynamics (just scalar drag/grip), no water displacement or wake on the
   surface, no spray entering the lighting, no board-induced foam trail on the mesh (the wake is a 2D particle sheet).
4. **Spray is 2D screen-space particles** launched in screen angles, with gravity scaled by pixels/m. Not coupled to the
   wave surface normal or velocity (e.g. real spray off a turn is tangent to the board's wake, droplets inherit the
   water's orbital velocity and the surfer's velocity). Mist is a procedural dot field on a curtain, not advected by
   the wave.
5. **Shading is deliberately flat** (key-frame look). No subsurface/translucency model other than the `thin` heuristic,
   no real refraction through the lip, no caustics, no depth fog or specular sun glitter beyond dash noise.
6. **Draw order limitation:** the lip curtain cannot pass in front of the surfer (needs a second render pass) —
   limits the tube moment.

## 7b. The upgrade spec (`docs/update_wave_physics_engine_from_Argon.md`): what went in, and why

Checked against sources before deciding: New (1983) finds the region under an overturning crest is close to a
√3-aspect ellipse; the jet tip moves ballistically (Longuet-Higgins and Dommermuth; Duncan's lab measures 0.6 to 0.8 g);
Godot's particle damping is a fixed loss of speed per second in pixels, so 0.7 to 1.3 really was a no-op.

* **In:** the two-stage taper and the shoulder that relaxes from 5 m ahead and rounds over (σ-blended face Bezier), so
  out in front the face is softer; the water's draw as a field of d and u (strongest in the pocket and up by the lip,
  calm on the shoulder) and the wave's push W(d) feeding the drive and pumping, so too far out in front he slows and
  the curl comes back (the spec's "flow field", up-face part); the almond barrel (aspect 1.4, short of √3 to keep the
  key-frame tube); a settle by the curl (tuck, height, heading) in place of the spec's barrel sweet-spot spring; spray
  bursts at the peak of a turn instead of a lockout, aimed off the outside rail and up over the crest at the lip, and
  real particle drag.
* **Not in, and why:** `face_angle(d, u)`: the rider already reads the real surface normal, so it feels the new shoulder
  directly (`face_angle` is not used by gameplay). The along-crest "suck back" and "lip forward boost": a peeling wave's
  water moves up the face, not along the crest, and they would fight the drive. A ballistic `lip_landing_point`: the
  mesh's landed lip never reaches the water, so a solved landing would put the spit away from the visible lip. The
  quadratic Bezier lip morph: a subtle change to an approved animation, worth its own pass. The translucent lip
  silhouette (`depth_test_inverted` next pass) and the advected carve trail: real wins for the tube and for carves, but
  each needs its own WebGL2 test, so they are follow-ups (step 12 territory). The 18 Hz spray stream and jittered rays:
  the fan was approved as spokes; peak-timed bursts give the big lip fan without it.

## 8. Suggested questions to ask the other AI
* Using only a 1D parameter d (and fixed shape), how can the wave be made to look and move more like a real
  plunging/spilling wave at low cost (CPU-built mesh once, GPU vertex animation, WebGL2)?
* A better, still analytic, model of the lip's ballistic trajectory and the barrel's time evolution (so the
  lip landing point, spit, and airflow follow the physics rather than constants 0.7 / 0.62 / 0.8).
* A cheap way to make the spray physically plausible from the board's tangent velocity and the local water
  surface normal (3D particles in the wave stage, GPU-less CPU budget ≈ a few hundred particles).
* A cheap surface-wake/foam trail on the wave face (e.g. a scrolling decal/trail texture in wave UV space).
* How to get the surfer visually inside the tube (render order/second pass) in WebGL2.
