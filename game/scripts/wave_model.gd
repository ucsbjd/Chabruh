class_name WaveModel
extends RefCounted
## The wave as a small physics-informed model. It draws nothing: it answers questions about
## the wave's shape, and bakes the answers into a tiny texture so the shader and the surfer
## read exactly the same numbers.
##
## Everything is a function of `d`, the distance ahead of the **peel point** (where the wave is
## breaking right now), in screen heights. Positive d is ahead of the break (left on screen, the
## way the surfer travels), negative d is behind it (the lip has thrown, the wall has collapsed).
## Heights use screen heights too: y runs 0 at the top of the screen to 1 at the bottom.
##
## Real-world anchors (see CLAUDE.md): peel speed is celerity / sin(peel angle); steeper seabeds
## throw bigger, rounder barrels; the lip lands ahead of the crest.

enum Zone { SHOULDER, POCKET, BARREL, WHITEWATER }

## Where the face meets the trough nearest the peel point, and the horizon the wall recedes toward.
const BASE_Y := 0.80
const HORIZON := 0.40
## The stand-in surfer's height, so wave sizes read as multiples of a surfer.
const SURFER_HEIGHT := 0.26

## The baked profile covers d from -PROFILE_BEHIND to +PROFILE_AHEAD, in PROFILE_WIDTH samples.
const PROFILE_BEHIND := 1.6
const PROFILE_AHEAD := 4.0
const PROFILE_WIDTH := 512

const MIN_HEIGHT := 0.20             # wave height at size 0, about 0.8 surfers
const MAX_HEIGHT := 0.62             # wave height at size 1, about 2.4 surfers
const SHOULDER_MIN := 0.38           # how low the wall tapers far ahead, as a fraction of its height
const PERSPECTIVE_FAR := 0.55        # how far the base line climbs toward the horizon down the line
const COLLAPSE_LENGTH := 0.7         # distance behind the peel point over which the wall falls apart
const WHITEWATER_HEIGHT := 0.18      # fraction of the wall left once it has collapsed into foam
const BUILD_LENGTH := 0.6            # distance ahead over which the lip starts to throw
const LIP_LENGTH := 0.9              # how far behind the peel point the thrown lip lasts
const POCKET_AHEAD := 0.55           # the pocket runs from here ahead of the peel point...
const POCKET_BEHIND := -0.05         # ...to here, just behind it
const BARREL_THRESHOLD := 0.35       # how much barrel there must be for the tube zone to exist

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

## The wave's own speed toward the beach, in screen heights per second.
var celerity := 0.5


## Speed of the break along the crest: celerity / sin(peel angle) (Walker, 1974).
static func peel_speed_for(wave_celerity: float, angle_degrees: float) -> float:
	return wave_celerity / sin(deg_to_rad(angle_degrees))


## The inverse: the peel angle that gives a break speed, in degrees.
static func peel_angle_for(wave_celerity: float, peel_speed: float) -> float:
	return rad_to_deg(asin(clampf(wave_celerity / peel_speed, 0.0, 1.0)))


func peel_speed() -> float:
	return peel_speed_for(celerity, peel_angle_degrees)


## Height of the wall nearest the peel point, in screen heights.
func height() -> float:
	return lerpf(MIN_HEIGHT, MAX_HEIGHT, size)


## How much barrel there is, 0 to 1: needs a hollow wave and enough height to hold a tube.
func barrel() -> float:
	return smoothstep(0.55, 0.9, hollowness) * smoothstep(0.35, 0.8, size)


## How far ahead of the peel point the wall takes to taper down to its far end.
func shoulder_length() -> float:
	return lerpf(1.1, 2.0, size)


## 1 at the peel point and behind it, falling to SHOULDER_MIN far ahead.
func taper_at(d: float) -> float:
	if d <= 0.0:
		return 1.0
	return lerpf(1.0, SHOULDER_MIN, smoothstep(0.0, 1.0, d / shoulder_length()))


## 1 at the peel point and ahead of it, falling to WHITEWATER_HEIGHT far behind.
func collapse_at(d: float) -> float:
	if d >= 0.0:
		return 1.0
	return lerpf(1.0, WHITEWATER_HEIGHT, smoothstep(0.0, 1.0, -d / COLLAPSE_LENGTH))


## Height of the crest above the base line.
func crest_height_at(d: float) -> float:
	return height() * taper_at(d) * collapse_at(d)


## Where the face meets the trough. It climbs toward the horizon down the line, so the wall
## recedes a little in perspective.
func base_y_at(d: float) -> float:
	var near := inverse_lerp(SHOULDER_MIN, 1.0, taper_at(d))
	return HORIZON + (BASE_Y - HORIZON) * lerpf(PERSPECTIVE_FAR, 1.0, near)


## How far the lip has thrown, 0 to 1: it starts ahead of the break and lasts a while behind it.
func throw_at(d: float) -> float:
	if d >= 0.0:
		return 1.0 - smoothstep(0.0, BUILD_LENGTH, d)
	return 1.0 - smoothstep(LIP_LENGTH * 0.4, LIP_LENGTH, -d)


## How much of the face is foam, 0 to 1. Spilling waves start foaming ahead of the peel point;
## plunging ones only behind it.
func foam_at(d: float) -> float:
	var lead := lerpf(0.5, 0.0, barrel())
	return 1.0 - smoothstep(-0.55, lead, d)


## Screen height of the face surface `u` of the way up the face (0 at the base, 1 at the crest).
func surface_y(d: float, u: float) -> float:
	return base_y_at(d) - u * crest_height_at(d)


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


## The profile as a PROFILE_WIDTH by 1 image: red is the crest height, green the base line,
## blue the lip throw and alpha the foam, sampled from -PROFILE_BEHIND to +PROFILE_AHEAD.
func bake_profile() -> Image:
	var image := Image.create(PROFILE_WIDTH, 1, false, Image.FORMAT_RGBAH)
	for i in PROFILE_WIDTH:
		var d := sample_distance(i)
		image.set_pixel(i, 0, Color(crest_height_at(d), base_y_at(d), throw_at(d), foam_at(d)))
	return image


## The distance d that sample `index` of the baked profile stands for.
static func sample_distance(index: int) -> float:
	return lerpf(-PROFILE_BEHIND, PROFILE_AHEAD, index / float(PROFILE_WIDTH - 1))
