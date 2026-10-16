# **Surf Game Physics and Spray Overhaul**

[https\://gemini.google.com/app/93f5c7ec77bc6b65](https://gemini.google.com/app/93f5c7ec77bc6b65)

*User prompt:  update the wave and spray model that Argon created with even more detail about how to fix the following issue that I see in the game: The physics still need a lot of work. The timing isn't correct when he goes up for a cutback. He should accelerate up, and then you kind of come to a stop when you do the cutback. All the energy is released in that cutback at the top of the wave. Instead, he kind of does the cutback, and then when he gets to the middle of the wave, he kind of accelerates down. It's like the most energy is on the way down, when it should be like he explodes up, does the cutback (giant spray), and then kind of floats down with the wave and gravity down. *

Response: The physics timing issue during cutbacks and top turns comes directly from the "snowboard-style carving model" currently in rider.gd and surfer\_spray.gd. Because the wave face is treated mathematically like a static snow hill rather than an upward-rushing hydrodynamic sheet, the four phases of a cutback are inverted in energy and timing:

> 1. **Why he slows down going up instead of exploding up:** In wave-and-spray-model.md (§5.3), slope acceleration is a\_slope \= \-g \* sin(phi) \* sin(theta) with g \= 9\. The instant the surfer points up the face (theta \> 0), gravity brakes him the entire way up. Worse, a\_drive is multiplied by S(-0.1, 0.4, cos(theta)), which cuts out during a steep climb (cos(theta) \-\> 0), and rise \= (v \* sin(theta) \* sin(phi) \+ v\_draw) / H multiplies the upward climb rate by sin(phi), choking vertical projection on the gentler shoulder slope.  
> 2. **Why the cutback happens late and doesn't come to a stop at the top:**  
   * **Hard speed floor:** Speed v is clamped to \[0.45 \* V\_p, 2.1 \* V\_p\] (3.5 m/s minimum), making it physically impossible for the surfer to stall/pause at the apex of a cutback.  
   * **Turn-rate lag pushes the cutback down to mid-wave:** Lean is filtered by a 2nd-order system (omega\_n \= 8 rad/s) and omega\_cap \= min(3.5, grip / max(v, 4)) restricts turn rate when speed is high. Additionally, the light unweighting factor only activates near the lip at S(0.78, 0.9, u), missing shoulder cutbacks (u \= 0.55..0.78). As a result, when you initiate a cutback going up, the board takes \~0.3 s to roll and whip—by which time the surfer has already drifted down to the middle of the wave (u ≈ 0.5).  
> 3. **Why he accelerates in the middle of the wave instead of floating down:** Once the nose points down in the steep mid-face (theta \< 0, u ≈ 0.5), \-g \* sin(phi) \* sin(theta) becomes strongly positive AND a\_drive turns back on at 100% because cos(theta) increases. The surfer gets rocket-boosted down the middle of the face instead of floating down against the rising water sheet.  
> 4. **Why the spray peaks on the way down instead of exploding at the top:** SurferSpray computes power \= speed \* sharpness \* (1 \+ 0.5 \* lip\_hit). Because power multiplies *instantaneous* speed by sharpness, slowing down at the top kills the spray, whereas accelerating through the delayed turn in the middle of the wave maximizes speed \* sharpness on the way down\! In real surfing, cutback spray is driven by **kinetic energy dumped at the apex (-dv/dt and entry speed)**, not exit speed.

Below is the complete, updated specification for update\_wave\_physics\_engine\_from\_Argon.md with the new **Section 3B (Cutback & Top-Turn Energy Cycle Overhaul)** and **Section 4.1 (Kinetic Energy-Dump Spray Coupling)** integrated.

# **Chabruh: Wave Modeling, Hydrodynamics, Cutback Energy Cycle & Dynamic Spray Upgrade Spec**

Read CLAUDE.md, wave-and-spray-model.md, game/scripts/wave\_model.gd, game/scripts/wave\_mesh.gd, game/scripts/wave\_stage.gd, game/scripts/rider.gd, game/scripts/surfer\_spray.gd, and game/shaders/wave3d.gdshader.

## **Goal of This Upgrade**

Take our existing parametric 2.5D wave and spray architecture and upgrade it from "geometric approximation \+ static-hill snowboard physics" to **"stylized arcade surf hydrodynamics"** (60 fps on WebGL2 & mobile, zero per-frame mesh rebuilds):

> 1. **Realistic, Carvable Wave Shoulder & Dynamic "Reef Bowl" Sections:** Fix the concave-everywhere cross-section and height floor so the shoulder rolls smoothly into a convex, gentle slope, while subtle reef bowls create rhythmic steep sections for hitting the lip and getting barreled.  
> 2. **Almond-Ellipse Barrel \+ True Parabolic Lip Jet \+ Tube Silhouette:** Widen the barrel horizontally like a real Longuet-Higgins/New (1983) plunging wave, drive the lip along a true ballistic parabola, add a subtle pocket sweet-spot assist, and let the surfer remain visible through the thin translucent lip curtain.  
> 3. **2D Spatial Water Velocity Field on the Face:** Replace scalar v\_draw with a position-dependent flow field (U\_d(d,u), U\_u(d,u)) that draws up and back into the pocket, launches upward at the lip, and calms on the shoulder.  
> 4. **True 4-Phase Cutback & Top-Turn Energy Cycle ("Explode Up \-\> Apex Stall & Energy Dump \-\> Float Down"):** Replace the static-hill snowboard acceleration model so the surfer accelerates *up* the face on the rising water jet, dumps all kinetic energy into a near-stationary rail gouge at the top of the wave, and floats effortlessly down with gravity and the wave without mid-face rocket acceleration.  
> 5. **Energy-Dump Coupled Spray Curtains & Advected Carve Tracks:** Drive spray intensity from **kinetic energy released (-dv/dt and pre-turn entry speed)** rather than instantaneous post-turn speed, couple ejection angles to the 3D rail normal, and add an advected whitewater carve trail on the 3D wave face.

## **1\. Realistic Wave Shoulder & Rhythmic "Reef Bowl" Sections (wave\_model.gd)**

### **1.1 Diagnosing the Current Shoulder Issues**

> * Ensure T(d) tapers smoothly in two stages so the playable wall holds height for the first 14–16 m before settling toward open swell out at L\_s.  
> * face\_angle(u) \= lerp(15 deg, lerp(55 deg, 88 deg, h), u^2) does not depend on d. Update it to face\_angle\_at(d, u) so any helper reading slope flattens progressively along sigma \= shoulder\_at(d).  
> * In section(d), blend the upper face cubic Bezier handles by sigma \= shoulder\_at(d) from a deep concave pocket wall (sigma \= 0, 0.5523 quarter-ellipse constant) to a convex/trochoidal rounded swell on the shoulder (sigma \-\> 1):

\# Part 4: Face cubic Bezier from P0 \= (0, c\_y) to P3 \= (z\_tr, 0\)  
var sigma: float \= shoulder\_at(d)  
var p0 := Vector2(0.0, c\_y)  
var p3 := Vector2(z\_tr, 0.0)  
var p1 := Vector2(  
    lerp(0.0, 0.32 \* z\_tr, sigma),  
    c\_y \- c\_y \* lerp(0.5523, 0.22, sigma)  
)  
var p2 := Vector2(  
    z\_tr \- z\_tr \* lerp(0.5523, 0.42, sigma),  
    lerp(0.0, 0.08 \* c\_y, sigma)  
)

## **2\. Elliptical "Almond" Barrel, Ballistic Lip & Tube Visibility**

### **2.1 Almond Tube & Quadratic Bezier Lip Morph (wave\_model.gd, wave3d.gdshader)**

> 1. **Elliptical Aspect:** Keep the almond barrel aspect (a \= lerp(1.0, 1.4..1.6, S(0.2, 1.0, kappa))) so the lip pitches well forward of the trough (A(rho, theta) \= (a\*r \+ a\*rho\*cos(theta), c\_y \+ rho\*sin(theta))).  
> 2. **Parabolic Vertex Morph (wave3d.gdshader):** Instead of linear chord blending between LIFTED, THROWN, and LANDED, evaluate a quadratic Bezier through the 3 keys over u\_t \= smoothstep(0.0, 0.68, lip\_phase) so every lip vertex follows a true ballistic arc:

vec2 p0 \= lifted\_yz;  
vec2 p2 \= landed\_yz;  
vec2 p1 \= 2.0 \* thrown\_yz \- 0.5 \* (p0 \+ p2);  
float u\_t \= smoothstep(0.0, 0.68, lip\_phase);  
vec2 ballistic\_yz \= mix(mix(p0, p1, u\_t), mix(p1, p2, u\_t), u\_t);  
float recover \= smoothstep(0.68, 1.0, lip\_phase);  
VERTEX.yz \= mix(VERTEX.yz, mix(ballistic\_yz, p0, recover), lip\_amount);

> 3. **Translucent Lip Backlight Silhouette (surfer3d.gdshader):** Add a next\_pass / material\_overlay with render\_mode unshaded, depth\_test\_inverted, depth\_draw\_never, blend\_mix; so whenever the 3D pitching lip passes in front of the surfer in the depth buffer, the surfer renders as a refracted dark-teal silhouette (alpha \= 0.42) with a warm gold rim.

## **3A. 2D Spatial Water Velocity Field on the Wave Face (rider.gd)**

The water on a breaking wave face is not stationary; it rushes rapidly upward from the trough toward the crest (D(d, u) / v\_draw):

func water\_velocity\_at(d: float, u: float) \-\> Vector2:  
    var H: float \= crest\_height\_at(d)  
    var sigma: float \= shoulder\_at(d)  
    var tau: float \= throw\_at(d)  
    var B: float \= barrel()

    var pocket\_focus: float \= 1.0 \- 0.65 \* sigma  
    var vertical\_profile: float \= smoothstep(0.0, 0.35, u) \* (1.0 \+ 0.45 \* tau \* smoothstep(0.5, 0.9, u))  
    var v\_up: float \= 1.25 \* clamp(H / 2.5, 0.45, 1.4) \* pocket\_focus \* vertical\_profile

    var suck\_back: float \= \-0.22 \* V\_p \* (1.0 \- sigma) \* (1.0 \- smoothstep(0.65, 0.88, u))  
    var lip\_forward\_boost: float \= 0.28 \* V\_p \* tau \* (0.4 \+ 0.6 \* B) \* smoothstep(0.75, 0.95, u)  
    return Vector2(suck\_back \+ lip\_forward\_boost, v\_up)

## **3B. Cutback & Top-Turn Energy Cycle Overhaul (rider.gd)**

### **3B.1 Why the Current Cutback Timing Is Inverted**

In wave-and-spray-model.md (§5.2–§5.4), four equations conspire to make the surfer sluggish going up, late into the turn, and fastest in the middle of the wave on the way down:

| Phase | Current Equation in rider.gd | Why It Breaks the Feel |
| :---- | :---- | :---- |
| **1\. Going Up (Climb)** | a\_slope \= \-g \* sin(phi) \* sin(theta) and a\_drive \*= S(-0.1, 0.4, cos(theta)) | Gravity immediately decelerates the surfer on the climb (theta \> 0), and a\_drive shuts off as the board points vertically (cos(theta) \-\> 0). |
| **2\. Climb Rate (u')** | rise \= (v \* sin(theta) \* sin(phi) \+ v\_draw) / H | Multiplying v \* sin(theta) by sin(phi) cuts upward motion along the face by 50–75% on the shoulder (phi \= 15°..30°), making the climb feel slow. |
| **3\. Cutback at the Top** | v \>= 0.45 \* V\_p, omega\_n \= 8 rad/s, light \= S(0.78, 0.9, u) | The 0.45 \* V\_p floor prevents stalling; light never triggers on shoulder cutbacks (u \= 0.55..0.78); and the 8 rad/s lean lag delays peak omega by \~300 ms until the surfer has already dropped to mid-wave (u ≈ 0.5). |
| **4\. Dropping Down** | a\_slope \= \-g \* sin(phi) \* sin(theta) \> 0 \+ full a\_drive | Pointing down in the steep mid-face (u ≈ 0.5, theta \< 0\) gives maximum downhill gravity acceleration PLUS full a\_drive, creating a mid-wave rocket boost instead of floating down. |

### **3B.2 Phase 1: "Explode Up" — Bottom-Turn Slingshot & Up-Face Hydrodynamic Thrust**

In real surfing, carving out of the bottom/pocket loads the fins and rail against the upward-rushing water sheet (D(d, u)). As the surfer points up the face (theta \> 0), that stored rail compression plus the upward orbital flow propels the board *up* the wall, overpowering gravity until the surfer reaches the crest/shoulder.

Add these state variables to rider.gd:

var bottom\_turn\_charge: float \= 0.0   \# 0..1 stored compression from bottom turn / pocket carve  
var v\_entry\_peak: float \= 0.0         \# Latched peak speed entering the climb/cutback (m/s)  
var apex\_gouge: float \= 0.0           \# 0..1 active energy-dump intensity at the top of the wave  
var apex\_hang\_timer: float \= 0.0      \# Brief suspension/float timer at the cutback apex (s)  
var post\_cutback\_float: float \= 0.0   \# 0..1 float-down state after releasing energy at the top  
var prev\_v: float \= 0.0               \# Previous frame speed to measure \-dv/dt energy dump  
var decel\_impulse: float \= 0.0        \# Smoothed rate of kinetic energy release (-dv/dt)

> 1. **Charge the Bottom-Turn Slingshot (u \< 0.48) & Release It Going Up (theta \> 0.15):**

\# 1\. Charge when carving or compressed in the lower/mid wave (u \< 0.48)  
var low\_face: float \= 1.0 \- smoothstep(0.28, 0.55, u)  
if low\_face \> 0.1 and (omega \> 0.4 or load\_g \> 1.15 or sin(theta) \> 0.2):  
    var charge\_rate: float \= (0.8 \* clamp(omega / 2.5, 0.0, 1.0) \+ 0.7 \* clamp(load\_g \- 1.0, 0.0, 1.0) \+ 0.5) \* (0.4 \+ 0.6 \* W)  
    bottom\_turn\_charge \= clamp(bottom\_turn\_charge \+ charge\_rate \* dt \* 3.2, 0.0, 1.0)  
else:  
    bottom\_turn\_charge \= move\_toward(bottom\_turn\_charge, 0.0, dt \* 1.1)

\# 2\. Upward Hydrodynamic Projection Thrust (Explode Up\!)  
var climbing: float \= clamp(sin(theta), 0.0, 1.0)  
var climb\_window: float \= (1.0 \- smoothstep(0.68, 0.90, u)) \# Accelerates all the way up to the top zone  
\# Upward-rushing water pushes WITH the surfer during the climb, canceling static uphill gravity\!  
var a\_up\_jet: float \= climbing \* climb\_window \* (  
    g \* sin(phi) \* 1.18                                 \# Cancels uphill gravity brake (-g\*sin(phi)\*sin(theta)) \+ net lift  
    \+ (3.8 \+ 5.2 \* bottom\_turn\_charge) \* (0.35 \+ 0.65 \* D\_draw) \# Explosive bottom-turn projection burst  
)  
\# Burn bottom\_turn\_charge as it propels the surfer up into the top turn  
if climbing \> 0.25 and u \> 0.35:  
    bottom\_turn\_charge \= move\_toward(bottom\_turn\_charge, 0.0, dt \* 1.8)

> 2. **Fix the rise Climb Rate Chokehold (§5.2):** In (d, u) coordinates, u runs along the curved face polyline, not vertical y alone. Multiplying v \* sin(theta) by sin(phi) artificially chokes climb speed on the shoulder. Replace sin(phi) in rise with a face-arc projection factor face\_arc\_factor \= lerp(0.72, 1.0, sin(phi)) and add an upward projection boost:

var face\_arc\_factor: float \= lerp(0.72, 1.0, sin(phi))  
var climb\_boost: float \= 1.0 \+ 0.35 \* climbing \* (1.0 \- smoothstep(0.65, 0.88, u))  
var rise: float \= (v \* sin(theta) \* face\_arc\_factor \* climb\_boost \+ v\_draw) / H

Now, when the surfer turns up toward the crest (theta \> 0), he **accelerates up the face** (v increases and u climbs briskly), latching his peak speed into v\_entry\_peak:

if climbing \> 0.2 and u \< 0.78:  
    v\_entry\_peak \= max(v\_entry\_peak, v)  
else:  
    v\_entry\_peak \= move\_toward(v\_entry\_peak, v, dt \* 1.2)

### **3B.3 Phase 2: "Come to a Stop at the Top" — Zero-Lag Apex Whip & Kinetic Energy Dump**

When the surfer reaches the upper wave (u \> 0.52 on the shoulder or u \> 0.62 near the pocket) and initiates a cutback or top turn (theta\* \< theta \- 0.35 or theta wrapping from \+ through 0 toward \-), **all of that upward kinetic energy must release right at the top of the wave**.

> 1. **Detect the Apex Cutback / Top Turn (apex\_gouge):**

\# High zone starts at u \= 0.50 on the shoulder (sigma \-\> 1\) and u \= 0.62 in the pocket (sigma \-\> 0\)  
var top\_zone\_start: float \= lerp(0.60, 0.46, sigma)  
var in\_top\_zone: float \= smoothstep(top\_zone\_start, top\_zone\_start \+ 0.18, u)

\# Turning down/back from a climb or high trim (input asking for lower heading, or actively carving negative omega)  
var turn\_down\_intent: float \= clamp((theta \- theta\_star) / 0.75, 0.0, 1.0)  
var active\_top\_carve: float \= clamp(-omega / 2.2, 0.0, 1.0)  
var apex\_trigger: float \= in\_top\_zone \* max(turn\_down\_intent, active\_top\_carve) \* smoothstep(-0.85, 0.15, theta)

apex\_gouge \= move\_toward(apex\_gouge, apex\_trigger, dt \* (9.0 if apex\_trigger \> apex\_gouge else 3.5))

> 2. **Eliminate Turn Lag at the Top (light & omega\_n Upgrade):** In wave-and-spray-model.md (§5.4), light only activates at S(0.78, 0.9, u) and lean uses omega\_n \= 8 rad/s. Change both so the board whips around **immediately at the top of the climb**, not halfway back down the wave:

\# Expand 'light' to include apex\_gouge so shoulder cutbacks (u \= 0.52..0.80) unweight and pivot immediately\!  
var light: float \= max(  
    max(clamp((1.0 \- load\_g) / 0.5, 0.0, 1.0), steep),  
    max(smoothstep(0.75, 0.88, u), apex\_gouge \* 0.92)  
)

\# Double the 2nd-order lean response speed during an apex cutback (8.0 \-\> 18.0 rad/s) so rail roll doesn't lag\!  
var omega\_n\_eff: float \= lerp(8.0, 18.0, apex\_gouge)  
\# Also relax omega\_cap at the apex so high entry speed DOES NOT force a wide, slow turn into the mid-face:  
var omega\_cap\_eff: float \= lerp(omega\_cap, 5.8, apex\_gouge)

> 3. **Dump All Kinetic Energy at the Apex (a\_apex\_dump & 0.16 \* V\_p Stall Floor):** Instead of bleeding speed slowly over a full second while dropping into the mid-face, dump kinetic energy **proportionally to v^2 \* apex\_gouge right at the top**, and lower the minimum speed floor from 0.45 \* V\_p to **0.16 \* V\_p** during the cutback apex:

\# Massive rail-gouge energy dump at the top of the wave: converts upward speed into spray & pivot whip\!  
var v\_stall\_target: float \= (0.18 \+ 0.08 \* (1.0 \- sigma)) \* V\_p  
var excess\_top\_speed: float \= max(0.0, v \- v\_stall\_target)  
var a\_apex\_dump: float \= \-14.5 \* apex\_gouge \* (0.4 \+ 0.6 \* abs(omega) / 3.0) \* excess\_top\_speed

\# Trigger brief apex hang-time and latch the post-cutback float state  
if apex\_gouge \> 0.35:  
    apex\_hang\_timer \= max(apex\_hang\_timer, 0.24 \* apex\_gouge)  
    post\_cutback\_float \= 1.0

During apex\_hang\_timer \> 0.0, damp rise (rise \*= lerp(1.0, 0.18, clamp(apex\_hang\_timer / 0.20, 0.0, 1.0))) so the surfer visibly **pauses/stalls at the crest as the board whips around and blows out the tail**.

### **3B.4 Phase 3: "Float Down with the Wave and Gravity" — Ending the Mid-Wave Acceleration**

Why was the surfer accelerating in the middle of the wave after the cutback?

> 1. Because a\_drive turns on whenever cos(theta) \> \-0.1, so as the board points down the face (theta ≈ \-45°..-75°, cos(theta) \= 0.26..0.70), a\_drive pushes the surfer hard toward v\_want\!  
> 2. Because a\_slope \= \-g \* sin(phi) \* sin(theta) gives full downhill acceleration (+9 \* sin(phi) \* |sin(theta)|) in the steep mid-face (u \= 0.35..0.65), ignoring the upward-rushing water sheet (v\_draw) that cushions a surfboard dropping down the face.

Fix both so the descent feels like **floating down with gravity and the wave**:

\# Decay post\_cutback\_float smoothly as the surfer drops down toward the trough (u \< 0.25) or finishes turning back to trim  
if apex\_gouge \< 0.2:  
    var decay\_rate: float \= 1.15 if u \> 0.28 else 2.8  
    post\_cutback\_float \= move\_toward(post\_cutback\_float, 0.0, dt \* decay\_rate)

var dropping: float \= clamp(-sin(theta), 0.0, 1.0)

\# 1\. Kill wave forward drive (a\_drive) while dropping down the face or floating out of a cutback\!  
\# Wave drive only engages when the surfer levels out into trim at the bottom/pocket, NOT mid-drop.  
var drive\_drop\_mask: float \= (1.0 \- 0.85 \* dropping) \* (1.0 \- 0.85 \* post\_cutback\_float)  
a\_drive \*= drive\_drop\_mask

\# 2\. Replace raw downhill snowboard gravity with Buoyant Planing Float on the way down:  
\# When dropping against the upward-rushing water (v\_draw), hydrodynamic planing drag balances gravity  
\# so the board floats/glides down at a controlled speed (\~0.45..0.68 V\_p) instead of rocketing down the mid-face\!  
var g\_down\_eff: float \= lerp(g, 3.2, max(post\_cutback\_float, 0.65 \* dropping))  
var a\_slope\_down: float \= g\_down\_eff \* sin(phi) \* dropping  
\# Terminal float-down damping: prevents downhill acceleration past a natural float speed v\_float\_cap  
var v\_float\_cap: float \= lerp(0.95, 0.52, post\_cutback\_float) \* V\_p  
var float\_drag: float \= \-7.5 \* dropping \* max(0.0, v \- v\_float\_cap)  
var a\_slope\_final: float \= a\_up\_jet if sin(theta) \>= 0.0 else (a\_slope\_down \+ float\_drag)

\# 3\. Gravity/Wave Float-Down Descent in u:  
\# Even though board speed v is low (0.20..0.48 V\_p) after the apex stall, gravity \+ the wave gently float  
\# the surfer down the face (u') so he doesn't hang stuck at the top while slow\!  
var gravity\_float\_u: float \= \-0.38 \* sin(phi) \* max(post\_cutback\_float \* 0.8, dropping) \* (1.0 \- apex\_gouge \* 0.7)  
rise \+= gravity\_float\_u

**Dynamic Speed Floor Update (§5.2–§5.3):**

var v\_min\_floor: float \= lerp(0.42, 0.16, max(apex\_gouge, post\_cutback\_float \* 0.75)) \* V\_p  
v \= clamp(v \+ (a\_slope\_final \+ a\_drag \+ a\_pump \+ a\_drive \+ a\_apex\_dump) \* dt, v\_min\_floor, 2.1 \* V\_p)

\# Measure instantaneous kinetic energy dumped (-dv/dt) for the spray engine\!  
var inst\_decel: float \= max(0.0, (prev\_v \- v) / max(dt, 0.001))  
decel\_impulse \= max(inst\_decel, decel\_impulse \* exp(-dt / 0.12))  
prev\_v \= v

### **3B.5 How the Complete Cutback Now Feels Frame-by-Frame**

> 1. **Bottom Turn (u \= 0.15 \-\> 0.35, theta swings positive):** bottom\_turn\_charge builds to 1.0 from rail load. As the nose points up, a\_up\_jet fires—the surfer **accelerates rapidly up the face**, reaching peak speed (v\_entry\_peak ≈ 1.3..1.6 \* V\_p) as he climbs toward the crest/shoulder.  
> 2. **Apex Cutback (u \= 0.65..0.88, theta wraps through 0 toward \-):** apex\_gouge hits 1.0. omega\_n jumps to 18 rad/s and light approaches 1.0, whipping the board around right at the top with zero lag. a\_apex\_dump converts the surfer's upward speed into a huge \-dv/dt impulse (decel\_impulse), bringing the surfer to a **near-stop (v ≈ 0.18 \* V\_p) with a 0.2s hang at the top** while detonating a giant spray fan.  
> 3. **Float Down (u \= 0.75 \-\> 0.25, theta \< 0):** With post\_cutback\_float active, a\_drive is suppressed and g\_down\_eff \+ gravity\_float\_u let the surfer **float smoothly down the face with gravity and the wave** at a relaxed, weightless pace—no mid-wave acceleration spike\! Only when he reaches the bottom/pocket (u \< 0.28) and levels out (theta \-\> 0\) does the wave's drive re-engage for the next bottom turn.

## **4\. Next-Gen Spray System: Energy-Dump Coupling, Cutback Curtains & Carve Tracks**

### **4.1 Coupling Spray to Kinetic Energy Released (-dv/dt) Instead of Current Speed (surfer\_spray.gd)**

In wave-and-spray-model.md (§6.1), spray power is calculated as: power \= speed \* sharpness \* (1 \+ 0.5 \* lip\_hit)

**Why this broke the cutback visual:** When the surfer properly slows to a near-stop at the top of the wave (speed \-\> 0.15), multiplying by speed makes power tiny at the apex—and then makes power huge in the middle of the wave when he accelerates downhill\!

**The Physical Fix:** A surfboard throws spray by **converting kinetic energy into water momentum (\\Delta E\_k \\propto v\_{entry} \\cdot (-\\Delta v))**. Update power in rider.gd / surfer\_spray.gd so it is driven by the **entry speed \+ deceleration impulse (decel\_impulse) at the apex**, and **actively suppressed during the post-cutback float down**:

\# Normalized entry speed brought into the top turn (0..1)  
var entry\_speed\_norm: float \= clamp((v\_entry\_peak \- 0.4 \* V\_p) / (1.3 \* V\_p), 0.0, 1.2)  
\# Normalized deceleration impulse (-dv/dt in m/s^2, where 10 m/s^2 is a hard apex stall)  
var dump\_norm: float \= clamp(decel\_impulse / 9.5, 0.0, 1.4)

\# Effective energy available for spray:  
\# \- At the top of a cutback/snap: driven by entry\_speed\_norm and the \-dv/dt energy dump\!  
\# \- On the way down (post\_cutback\_float \> 0, apex\_gouge \== 0): damped by (1.0 \- 0.65 \* post\_cutback\_float)  
\#   so floating down the middle of the wave NEVER throws a giant spray fan\!  
var float\_down\_quiet: float \= 1.0 \- 0.65 \* post\_cutback\_float \* (1.0 \- apex\_gouge)  
var effective\_spray\_speed: float \= max(  
    speed \* float\_down\_quiet,  
    (0.55 \* entry\_speed\_norm \+ 0.75 \* dump\_norm) \* max(apex\_gouge, lip\_hit)  
)

var power: float \= effective\_spray\_speed \* sharpness \* (1.0 \+ 0.90 \* apex\_gouge \+ 0.65 \* lip\_hit)

### **4.2 Continuous Rail Curtain \+ Apex Detonation (surfer\_spray.gd)**

> 1. **Continuous Rail Curtain \+ Instant Peak Re-Trigger:**  
   * Ensure the emitter never locks out the apex of the turn: fire micro-slices or re-trigger immediately whenever power rises by 0.12 above the previous burst OR when decel\_impulse peaks at the top of the cutback (apex\_gouge \> 0.65 and dump\_norm \> 0.5).  
   * Scale apex cutback & lip-hit bursts with a **1.6x droplet count (FAN droplets up to 280\) and 1.35x launch speed (up to 10.8 m/s \* ppm)** so the energy dump at the top of the wave produces a massive, lingering white curtain while the surfer pauses and floats down beneath it\!  
> 2. **3D Rail-Coupled Ejection Direction:** Keep the 3D rail projection through WaveStage.project(): dir \= normalize(-0.45 \* f \+ 0.85 \* (-sign(omega)) \* s \+ (0.35 \+ 0.65 \* max(lip\_hit, apex\_gouge)) \* n), blended upward/over the crest (0.25, 0.85, \-0.45) by 0.75 \* max(lip\_hit, 0.7 \* apex\_gouge). During an apex cutback at the top of the wave, the spray blasts **up and out over the shoulder/crest** while the surfer drops beneath the hanging mist curtain.  
> 3. **True Linear Particle Drag in Pixels (§6.1):** Ensure CPUParticles2D.damping\_min \= 220.0 \* ppm\_scale and damping\_max \= 480.0 \* ppm\_scale (since Godot's particle damping is linear deceleration in px/s^2) so high-velocity apex spray explodes outward fast and then hangs in the air as the surfer floats down the face.

### **4.3 Advected Whitewater Carve Track on the 3D Wave Face (WaveCarveTrail)**

To visually anchor the "explode up \-\> gouge at the top \-\> float down" arc on the wave face:

> 1. **32-Node Ring Buffer in (d, u):** Record (d\_i, u\_i, width\_i, alpha\_i) every 0.04 s at the surfboard tail. Scale width\_i \= lerp(0.16, 1.05, clamp(max(power, apex\_gouge) \* 1.5, 0.0, 1.0)) so the track is a thin wake during the fast climb, widens into a **thick 1 m whitewater gouge right at the top of the cutback**, and narrows into a light float track on the descent.  
> 2. **Advect with water\_velocity\_at(d\_i, u\_i):** Each frame update d\_i \+= (flow.x \- V\_p) \* dt and u\_i \+= (flow.y / max(1.2, wave.crest\_height\_at(d\_i))) \* dt so the apex gouge gets carried up over the crest as the surfer floats down away from it.

## **5\. Implementation Checklist for Claude**

> 1. **Step 1 (rider.gd — Cutback & Top-Turn Physics Overhaul):**  
   * Implement bottom\_turn\_charge and a\_up\_jet so carving out of the bottom/pocket and pointing up (theta \> 0\) accelerates the surfer **up** the wave face, overcoming uphill gravity \-g \* sin(phi) \* sin(theta).  
   * Fix rise by replacing sin(phi) with lerp(0.72, 1.0, sin(phi)) \* climb\_boost so climbing onto the shoulder doesn't bog down.  
   * Implement apex\_gouge, expand light to include apex\_gouge \* 0.92, boost omega\_n from 8.0 to 18.0 rad/s at the apex, lower the speed floor from 0.45 \* V\_p to 0.16 \* V\_p during the turn, and apply a\_apex\_dump \+ apex\_hang\_timer so the surfer comes to a crisp near-stop and whips the board around **at the top of the wave**.  
   * Implement post\_cutback\_float, mask out a\_drive while dropping (theta \< 0), and apply buoyant planing float (g\_down\_eff, float\_drag, and gravity\_float\_u) so the surfer **floats down with the wave and gravity** without accelerating in the middle of the face.  
> 2. **Step 2 (surfer\_spray.gd & rider.gd — Energy-Dump Spray Coupling):**  
   * Compute decel\_impulse (-dv/dt) and v\_entry\_peak in rider.gd and pass them into SurferSpray.  
   * Replace speed in power \= speed \* sharpness \* ... with effective\_spray\_speed driven by v\_entry\_peak \+ decel\_impulse at the apex and damped by float\_down\_quiet during the descent, so the giant spray explosion happens at the top of the cutback when energy is dumped, not in the middle of the wave on the way down.  
> 3. **Step 3 (wave\_model.gd, wave3d.gdshader, surfer3d.gdshader, wave\_carve\_trail.gd):**  
   * Verify quadratic Bezier lip morph in wave3d.gdshader, depth\_test\_inverted tube silhouette pass on surfer3d.gdshader, and the 32-node advected WaveCarveTrail ribbon in WaveStage.  
> 4. **Step 4 (Verification & Telemetry Test):**  
   * Add a headless physics assertion in tests/run\_tests.gd that simulates a bottom-turn-to-cutback maneuver (u: 0.20 \-\> 0.78 \-\> 0.30) and verifies:  
     1. Peak upward speed v\_max\_up occurs during the climb (u ∈ \[0.35, 0.72\], theta \> 0).  
     2. Minimum speed v\_min\_apex \< 0.28 \* V\_p and maximum angular velocity |omega|\_max occur at the top of the wave (u \> 0.62), **not** at mid-wave (u \< 0.52).  
     3. Maximum spray power occurs within 0.12 s of the apex deceleration spike (-dv/dt peak at u \> 0.62), and mid-wave descent speed (u ∈ \[0.35, 0.55\], theta \< 0\) remains below 0.70 \* V\_p (floating down rather than accelerating).

---

*User prompt: I need you to summarize all this in an .MD file that is wholy contained taht I can download and give to an AI*

Response:  
---

