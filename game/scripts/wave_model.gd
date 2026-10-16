class_name WaveModel
extends RefCounted
## The wave as a small physics-informed model, in meters. It draws nothing: it answers questions
## about the wave's shape, builds the cross-sections that the 3D mesh is swept from, and bakes
## a small profile texture, so the mesh, the shaders and the surfer all read the same numbers.
##
## Everything is a function of `d`, the distance in meters ahead of the **peel point** (where the
## wave is breaking right now). Positive d is ahead of the break (the way the surfer travels, to
## the left on screen); negative d is behind it, where the lip has thrown and the wall has
## collapsed. World axes: x runs along the crest and is -d, y is up, and z runs toward the beach,
## where the camera is.
##
## Real-world anchors (see CLAUDE.md): peel speed is celerity / sin(peel angle); steeper seabeds
## throw bigger, rounder barrels; the lip is a thrown jet that lands ahead of the crest.

enum Zone { SHOULDER, POCKET, BARREL, WHITEWATER }
## The three shapes the lip cycles through: standing up as it pitches, thrown out over the trough,
## and fallen into the whitewater. The shader morphs between them (see wave3d.gdshader).
enum LipShape { LIFTED, THROWN, LANDED }

const SURFER_HEIGHT := 1.8

## The baked profile covers d from -PROFILE_BEHIND to +PROFILE_AHEAD, in PROFILE_WIDTH samples.
const PROFILE_BEHIND := 30.0
const PROFILE_AHEAD := 60.0
const PROFILE_WIDTH := 512

const MIN_HEIGHT := 1.4              # wave height at size 0, about 0.8 surfers
const MAX_HEIGHT := 4.4              # wave height at size 1, about 2.4 surfers
const NEAR_TAPER := 0.15             # the wall eases down this much over the first NEAR_TAPER_LENGTH meters ahead of the break...
const NEAR_TAPER_LENGTH := 16.0
const SHOULDER_FLOOR := 0.3          # ...then, from about a third of the way down the shoulder, settles to this fraction of its height
const SHOULDER_FROM := 5.0           # meters ahead of the peel point where the face starts to relax into the shoulder...
const SHOULDER_SPAN := 0.75          # ...and the fraction of the shoulder's length by which it has fully relaxed
const SHOULDER_CALM := 0.65          # how much weaker the water's draw up the face is once the shoulder has relaxed
const SHOULDER_SLACK := 0.85         # how much of the wave's push is gone once the shoulder has relaxed
const LIP_DRAW := 0.45               # how much harder the water draws up the top of the face where the lip is throwing
const LOW_DRAW := 0.55               # the draw at the foot of the face, as a fraction of the draw in the middle
const WHITEWATER_PUSH := 0.6         # the push left in the whitewater behind the break (the foam still shoves a board along)
const COLLAPSE_LENGTH := 4.5         # distance behind the peel point over which the wall falls apart
const WHITEWATER_HEIGHT := 0.16     # fraction of the wall left once it has collapsed into foam
const PEAK_AT := 1.5                 # the highest point of the wave, just ahead of the peel point
const PEAK_WIDTH := 6.0              # how far along the crest the peak spreads, in meters
const PEAK_GAIN := 0.10              # how much taller the peak is than the wall around it
const SHOULDER_RUN := 0.9            # how much longer (gentler) the face runs far down the line
# The lip cycle: how far the lifted and landed shapes depart from the thrown one.
const LIFT_RISE := 0.06              # the wall stands this much taller as the lip pitches
const LIFT_CURL := 0.62              # ...with this much of the curl
const LAND_DROP := 0.28              # the wall falls this much when the lip lands
const LAND_CURL := 0.80              # ...with this much of the curl
const LANDING_RUN := 0.7             # meters the lip travels on toward the beach per meter of height it still has to fall
const BUILD_LENGTH := 9.0            # distance ahead over which the lip builds up to its throw
const LIP_LENGTH := 7.0              # how far behind the peel point the thrown lip lasts
const POCKET_AHEAD := 3.8            # the pocket runs from here ahead of the peel point...
const POCKET_BEHIND := -0.4          # ...to here, just behind it
const BARREL_THRESHOLD := 0.35       # how much barrel there must be for the tube zone to exist

# Cross-section proportions, as fractions of the wave height.
const LIP_THICKNESS := 0.14          # at the crest, tapering to a thin tip
const BARREL_RADIUS := 0.43          # inner radius of a full barrel, up and down
## A real plunging lip throws out further than it is tall: the tube under it is close to an ellipse about 1.7 times wider
## than high (New, 1983, "A class of elliptical free-surface flows"). A full barrel is this much wider than high, toward
## the beach, so the lip pitches further out and the mouth opens as an almond; a shallow curl stays round.
const BARREL_ASPECT := 1.4
const BACK_RUN := 3.2                # how far back the gentle back slope runs
const POINTS_BACK := 12
const POINTS_OUTER := 16
const POINTS_INNER := 18
const POINTS_FACE := 10

## 0 is a small wave, 1 is the biggest. Sets the height (and so how much barrel is possible).
var size := 0.5:
	set(value):
		size = clampf(value, 0.0, 1.0)

## 0 is a spilling wave (foam tumbles down the face), 1 is a plunging one (the lip throws).
var hollowness := 0.5:
	set(value):
		hollowness = clampf(value, 0.0, 1.0)

## How the break travels along the crest. 30 to 50 degrees is rideable; below about 27 it peels
## too fast to ride.
var peel_angle_degrees := 40.0:
	set(value):
		peel_angle_degrees = clampf(value, 5.0, 85.0)

## The wave's own speed toward the beach, in meters per second.
var celerity := 5.0


## Speed of the break along the crest: celerity / sin(peel angle) (Walker, 1974).
static func peel_speed_for(wave_celerity: float, angle_degrees: float) -> float:
	return wave_celerity / sin(deg_to_rad(angle_degrees))


## The inverse: the peel angle that gives a break speed, in degrees.
static func peel_angle_for(wave_celerity: float, peel_speed: float) -> float:
	return rad_to_deg(asin(clampf(wave_celerity / peel_speed, 0.0, 1.0)))


func peel_speed() -> float:
	return peel_speed_for(celerity, peel_angle_degrees)


## Height of the wall nearest the peel point, in meters.
func height() -> float:
	return lerpf(MIN_HEIGHT, MAX_HEIGHT, size)


## How much barrel there is, 0 to 1: needs a hollow wave and enough height to hold a tube.
func barrel() -> float:
	return smoothstep(0.55, 0.9, hollowness) * smoothstep(0.35, 0.8, size)


## How far ahead of the peel point the wall takes to taper down to its far end.
func shoulder_length() -> float:
	return lerpf(30.0, 46.0, size)


## 1 at the peel point and behind it. Down the line the wall first eases a little (the playable wall holds most of its
## height, room for a cutback), then from about a third of the way down the shoulder it settles toward open swell.
func taper_at(d: float) -> float:
	if d <= 0.0:
		return 1.0
	var near := NEAR_TAPER * smoothstep(0.0, NEAR_TAPER_LENGTH, d)
	var far := (1.0 - NEAR_TAPER - SHOULDER_FLOOR) * smoothstep(shoulder_length() * 0.35, shoulder_length(), d)
	return 1.0 - near - far


## 1 at the peel point and ahead of it, falling to WHITEWATER_HEIGHT behind and then to nothing.
func collapse_at(d: float) -> float:
	if d >= 0.0:
		return 1.0
	var collapsed := lerpf(1.0, WHITEWATER_HEIGHT, smoothstep(0.0, 1.0, -d / COLLAPSE_LENGTH))
	return collapsed * (1.0 - smoothstep(PROFILE_BEHIND * 0.5, PROFILE_BEHIND, -d))


## How much spray the crest throws at d, 0 to 1: a little spindrift all along the wall, a lot where the
## wave is breaking, and a steady haze rising off the whitewater behind it.
func mist_at(d: float) -> float:
	var near_break := (d + 1.0) / 5.0
	return clampf(0.18 * taper_at(d) + 0.82 * exp(-near_break * near_break) + 0.6 * whitewater_at(d), 0.0, 1.0)


## Height of the crest above the trough, in meters.
func crest_height_at(d: float) -> float:
	return height() * taper_at(d) * collapse_at(d) * roll_at(d) * peak_at(d)


## A gentle bump in height at the peel point: the peak, where the wave is highest and about to break.
func peak_at(d: float) -> float:
	var x := (d - PEAK_AT) / PEAK_WIDTH
	return 1.0 + PEAK_GAIN * exp(-x * x)


## 0 on the wall and the pocket, rising to 1 down the line: the shoulder, where the face relaxes, rounds over at the top
## and runs longer and gentler to the trough, so it pushes a surfer along less.
func shoulder_at(d: float) -> float:
	return smoothstep(SHOULDER_FROM, shoulder_length() * SHOULDER_SPAN, d)


## How strongly the water on the face draws up toward the crest at (d, u), as a factor of the draw in the middle of the
## face of a 2.5 m wave's pocket: it grows with the wave's height, is strongest in the pocket and up where the lip is
## throwing (it holds a board at the lip), weaker low on the face, and calms down the shoulder as the face relaxes. This
## is what lifts a surfer and so, pointed down the line, what drives him: the wave's power.
func draw_at(d: float, u: float) -> float:
	var size_factor := clampf(crest_height_at(d) / 2.5, 0.4, 1.3)
	var calm := 1.0 - SHOULDER_CALM * shoulder_at(d)
	var profile := lerpf(LOW_DRAW, 1.0, smoothstep(0.0, 0.35, u)) * (1.0 + LIP_DRAW * throw_at(d) * smoothstep(0.5, 0.9, u))
	return size_factor * calm * profile


## How much the wave pushes a surfer along at d, 0 to 1: all of it in the pocket by the peak, less down the shoulder as
## the face shrinks and relaxes, and some still in the whitewater behind the break.
func power_at(d: float) -> float:
	return clampf(taper_at(d) * (1.0 - SHOULDER_SLACK * shoulder_at(d)) * lerpf(1.0, WHITEWATER_PUSH, whitewater_at(d)), 0.0, 1.0)


## How much of the wave has turned to whitewater at d, 0 to 1: nothing ahead of the break, all of it
## once the wall has collapsed, then fading as the foam spreads out far behind.
func whitewater_at(d: float) -> float:
	if d >= 0.0:
		return 0.0
	return smoothstep(0.0, COLLAPSE_LENGTH, -d) * (1.0 - smoothstep(PROFILE_BEHIND * 0.5, PROFILE_BEHIND, -d))


## A slow undulation along the crest, so the wall is never ruler-straight: swells in height of a few percent.
func roll_at(d: float) -> float:
	return 1.0 + 0.06 * sin(d * 0.31 + 0.7) + 0.035 * sin(d * 0.83 + 2.1)


## How far the lip has thrown, 0 to 1: it starts ahead of the break and lasts a while behind it.
func throw_at(d: float) -> float:
	if d >= 0.0:
		return 1.0 - smoothstep(0.0, BUILD_LENGTH, d)
	return 1.0 - smoothstep(LIP_LENGTH * 0.4, LIP_LENGTH, -d)


## How curled the lip is at d, 0 to 1. Even a spilling wave keeps a little lip.
func curl_at(d: float) -> float:
	return throw_at(d) * lerpf(0.18, 1.0, barrel())


## How much of the face is foam, 0 to 1. Spilling waves start foaming ahead of the peel point;
## plunging ones only behind it.
func foam_at(d: float) -> float:
	var lead := lerpf(4.0, 0.0, barrel())
	return 1.0 - smoothstep(-4.0, lead, d)


## Angle of the face from horizontal, in radians: gentle at the base, steeper toward the crest,
## and steeper overall on hollow waves. The pull down the face is sin of this.
func face_angle(u: float) -> float:
	var crest_angle := lerpf(55.0, 88.0, hollowness)
	return deg_to_rad(lerpf(15.0, crest_angle, u * u))


## Which part of the wave a surfer at d is in.
func zone_at(d: float) -> Zone:
	if d > POCKET_AHEAD:
		return Zone.SHOULDER
	if d >= POCKET_BEHIND:
		return Zone.POCKET
	if barrel() > BARREL_THRESHOLD and d > -LIP_LENGTH:
		return Zone.BARREL
	return Zone.WHITEWATER


## How much tube a surfer at (d, u) is in, 0 to 1: nothing outside the barrel zone, and only low on the face, under the lip.
func barrel_amount_at(at_d: float, at_u: float) -> float:
	if zone_at(at_d) != Zone.BARREL:
		return 0.0
	return barrel() * (1.0 - smoothstep(0.35, 0.7, at_u))


## The cross-section of the wave at d. See WaveSection for the layout.
##
## It is built from simple curves: a gentle back slope, then an outer arc over the crest that is
## thrown forward into the lip, a thin tip, an inner arc back under the lip (the roof of the
## barrel), and a concave face that curls down to the trough. An ellipse of height r centred at
## (r * aspect, y_a) gives both arcs, so a full barrel is an almond-shaped tube, wider than high
## (barrel_aspect), whose floor is the water.
func section(d: float) -> WaveSection:
	return section_key(d, LipShape.THROWN)


## The cross-section at d in one of the lip cycle's three shapes. All three have the same points and
## the same trough, so the shader can morph between them point by point.
func section_key(d: float, shape: LipShape) -> WaveSection:
	var height_here := crest_height_at(d)
	var curl := curl_at(d)
	var foam_here := foam_at(d)
	var activity := throw_at(d)
	var trough := trough_z_at(d)
	match shape:
		LipShape.LIFTED:
			height_here *= 1.0 + LIFT_RISE * activity
			curl *= LIFT_CURL
		LipShape.LANDED:
			height_here *= 1.0 - LAND_DROP * activity
			curl *= LAND_CURL
	return section_for(height_here, curl, foam_here, trough, shoulder_at(d))


## Where the foot of the wave is, in z. The face runs longer and gentler down the shoulder, and a
## full barrel pulls the foot in to the barrel's own radius.
func trough_z_at(d: float) -> float:
	var wave_h := maxf(crest_height_at(d), 0.03)
	var curl := curl_at(d)
	var run := wave_h * lerpf(2.0, 1.1, hollowness) * (1.0 + SHOULDER_RUN * shoulder_at(d))
	return lerpf(run, curl * BARREL_RADIUS * wave_h * barrel_aspect(curl), curl)


## The same cross-section for an explicit height (meters), curl and foam amount (both 0 to 1). A
## negative `trough_override` lets the section place its own foot. `shoulder` (0 to 1, see shoulder_at) rounds the face.
func section_for(crest_meters: float, curl: float, foam_here: float, trough_override := -1.0, shoulder := 0.0) -> WaveSection:
	var result := WaveSection.new()
	var wave_h := maxf(crest_meters, 0.03)

	var thick := wave_h * lerpf(0.025, LIP_THICKNESS, pow(curl, 0.7))
	var tip_thick := wave_h * 0.012
	var radius := curl * BARREL_RADIUS * wave_h
	var aspect := barrel_aspect(curl)
	var centre_y := wave_h - radius - thick
	var trough_z := trough_override if trough_override >= 0.0 else lerpf(wave_h * lerpf(2.0, 1.1, hollowness), radius * aspect, curl)
	var back_len := wave_h * BACK_RUN
	var theta_start := deg_to_rad(105.0)
	var theta_tip := deg_to_rad(lerpf(90.0, -40.0, curl))

	# The back slope, rising gently to where the outer arc begins.
	var arc_start := _arc_point(radius * aspect, centre_y, radius + thick, theta_start, aspect)
	var arc_tangent := Vector2(sin(theta_start), -cos(theta_start))
	var back_from := Vector2(-back_len, 0.0)
	for i in POINTS_BACK:
		var t := i / float(POINTS_BACK)
		var p := _bezier(back_from, back_from + Vector2(back_len * 0.55, 0.0), arc_start - arc_tangent * (back_len * 0.28), arc_start, t)
		result.add(p, p.y / wave_h, foam_here * 0.95, 0.0, 0.2 * (1.0 - p.y / wave_h))

	# The outer arc over the crest and down the front of the lip, thinning toward the tip.
	for i in POINTS_OUTER:
		var t := i / float(POINTS_OUTER - 1)
		var theta := lerpf(theta_start, theta_tip, t)
		var thin := pow(1.0 - t, 0.8)
		var arc_radius := radius + tip_thick + (thick - tip_thick) * thin
		var p := _arc_point(radius * aspect, centre_y, arc_radius, theta, aspect)
		var tip_foam := smoothstep(0.55, 1.0, t) * curl
		var index := result.add(p, p.y / wave_h, maxf(foam_here, tip_foam), 0.0, 1.0 - thin * 0.8)
		if p.y >= result.points[result.crest].y:
			result.crest = index
	result.lip_tip = result.points.size() - 1

	# The inner arc: back from the tip, up under the lip (the roof of the barrel) and round to the face.
	for i in POINTS_INNER:
		var t := (i + 1) / float(POINTS_INNER)
		var theta := lerpf(theta_tip, PI, t)
		var p := _arc_point(radius * aspect, centre_y, radius, theta, aspect)
		var tip_foam := (1.0 - smoothstep(0.0, 0.35, t)) * curl
		result.add(p, p.y / wave_h, maxf(foam_here, tip_foam), curl * lerpf(0.3, 1.0, t), 1.0 - t * 0.7)

	# The face: concave, curling down to the trough (for a full barrel this is the tube's floor curve). Down the shoulder
	# it rounds over: convex at the top, easing into a gentle slope at the foot, like an unbroken swell.
	var face_top := result.points[result.points.size() - 1]
	var trough := Vector2(trough_z, 0.0)
	var upper := face_top + Vector2(0.32 * trough_z * shoulder, -face_top.y * lerpf(0.5523, 0.22, shoulder))
	var lower := Vector2(trough_z * (1.0 - lerpf(0.5523, 0.42, shoulder)), 0.08 * face_top.y * shoulder)
	result.face_from = result.points.size() - 1
	for i in POINTS_FACE:
		var t := (i + 1) / float(POINTS_FACE)
		var p := _bezier(face_top, upper, lower, trough, t)
		result.add(p, p.y / wave_h, foam_here, curl * lerpf(0.9, 0.5, t), 0.1)
	result.face_to = result.points.size() - 1

	# The water in front of the wave is a separate plane, so the section ends at the trough.
	return result


## The point `u` of the way up the face at d, as a world position (x along the crest, y up, z
## toward the beach). u is 0 at the trough and 1 at the top of the face.
func surface_point(d: float, u: float) -> Vector3:
	var p := section(d).face_point(u)
	return Vector3(-d, p.y, p.x)


## The outward (into the air) unit normal of the face at d and u, in world axes.
func surface_normal(d: float, u: float) -> Vector3:
	var n := section(d).face_normal(u)
	return Vector3(0.0, n.y, n.x)


## Meters of face per unit of u at (d, u): a speed along the face divided by this is how fast u changes.
func face_length_at(d: float, u: float) -> float:
	return section(d).face_length(u)


## The crest at d, where the lip is thrown from: a world position.
func crest_point(d: float) -> Vector3:
	var s := section(d)
	var p := s.points[s.crest]
	return Vector3(-d, p.y, p.x)


## The tip of the lip at d, a world position.
func lip_tip_point(d: float) -> Vector3:
	var s := section(d)
	var p := s.points[s.lip_tip]
	return Vector3(-d, p.y, p.x)


## Where the thrown lip lands on the water: the tip falls on past where it is now, along its
## heading, and the spit and splash happen there. A world position at sea level.
func lip_landing_point(d: float) -> Vector3:
	var tip := lip_tip_point(d)
	return Vector3(tip.x, 0.0, tip.z + tip.y * LANDING_RUN)


## The profile as a PROFILE_WIDTH by 1 image, sampled from -PROFILE_BEHIND to +PROFILE_AHEAD:
## red is the crest height in meters, green is where the trough is (z), blue the curl and
## alpha the foam. Shaders use it to put foam and shadow where the wave is.
func bake_profile() -> Image:
	var image := Image.create(PROFILE_WIDTH, 1, false, Image.FORMAT_RGBAH)
	for i in PROFILE_WIDTH:
		var d := sample_distance(i)
		var curl := curl_at(d)
		image.set_pixel(i, 0, Color(crest_height_at(d), trough_z_at(d), curl, foam_at(d)))
	return image


## The distance d that sample `index` of the baked profile stands for.
static func sample_distance(index: int) -> float:
	return lerpf(-PROFILE_BEHIND, PROFILE_AHEAD, index / float(PROFILE_WIDTH - 1))


static func _arc_point(centre_z: float, centre_y: float, arc_radius: float, theta: float, aspect := 1.0) -> Vector2:
	return Vector2(centre_z + arc_radius * cos(theta) * aspect, centre_y + arc_radius * sin(theta))


## How much wider than high the tube is for a curl (0 to 1): round for a shallow curl, BARREL_ASPECT for a full barrel.
static func barrel_aspect(curl: float) -> float:
	return lerpf(1.0, BARREL_ASPECT, smoothstep(0.2, 1.0, curl))


static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)
