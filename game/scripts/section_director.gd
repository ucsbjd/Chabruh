class_name SectionDirector
extends RefCounted
## The reef under the wave. A point break peels along uneven bathymetry: deep channels where it softens and slows,
## long walls, fast racecourse sections and shallow bowls that suck out and barrel. Each of these is a ReefSection, a
## bump in wave space (`d`, meters ahead of the peel point) that rides toward the peel point at the peel speed, since
## the reef stays put while the break runs along it. Nothing is rebuilt per frame: WaveModel reads the sections for the
## rider's physics and WaveStage passes them to the shaders as two vec4s, so the two always agree.
##
## Sections come one after another with breathing room between them. `maturity` (0 early in a session, 1 late in the
## evening, as the tide drains off the reef) makes bowls and racecourse walls more likely.

enum Kind { CRUISER_WALL, DEEP_CHANNEL, RACECOURSE, REEF_BOWL }

## What each kind does to the wave where it is: size and hollowness offsets (WaveModel's 0 to 1 dials), how much
## faster the break peels, and how far either side of its centre it reaches, in meters.
const KINDS := {
	Kind.CRUISER_WALL: {"size": 0.0, "hollow": 0.0, "peel": 1.0, "half_width": 12.0},
	Kind.DEEP_CHANNEL: {"size": -0.18, "hollow": -0.35, "peel": 0.72, "half_width": 12.0},
	Kind.RACECOURSE: {"size": 0.10, "hollow": 0.20, "peel": 1.32, "half_width": 14.0},
	# (the spec's 10 m bowl passed the surfer too quickly to hold a barrel: 13 m gives about 1.5 s of real tube)
	Kind.REEF_BOWL: {"size": 0.22, "hollow": 0.48, "peel": 1.15, "half_width": 13.0},
}
const NAMES := {
	Kind.CRUISER_WALL: "cruiser wall", Kind.DEEP_CHANNEL: "deep channel",
	Kind.RACECOURSE: "racecourse", Kind.REEF_BOWL: "reef bowl",
}

const SPAWN_D := 38.0                # sections appear this far ahead, off the left of the screen
const GONE_D := -34.0                # ...and are dropped once all of them is this far behind the break
const GAP_MIN := 8.0                 # meters of plain wall between one section and the next
const GAP_MAX := 16.0
const MAX_ACTIVE := 2
## How likely each kind is: a bowl from BOWL_CHANCE_EARLY to BOWL_CHANCE_LATE as the session matures; the rest is
## shared out between the others, the racecourse growing and the gentle channel shrinking with maturity.
const BOWL_CHANCE_EARLY := 0.25
const BOWL_CHANCE_LATE := 0.55
const RACE_SHARE := Vector2(0.25, 0.5)       # early, late
const CHANNEL_SHARE := Vector2(0.35, 0.25)
## A forced section (the test hotkeys) is put this far ahead of the rider, so its telegraphs show before it arrives.
const FORCE_AHEAD := 22.0


var sections: Array[ReefSection] = []
## 0 early in a session to 1 late in it: bowls and racecourse walls come more often.
var maturity := 0.0
var rng := RandomNumberGenerator.new()
## Off, the reef is flat: no sections spawn (the ones already there carry on).
var enabled := true
var _gap := GAP_MIN


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	_gap = rng.randf_range(GAP_MIN, GAP_MAX)


## Moves every section toward the break at the peel speed (m/s), drops those left far behind, and queues the next.
func update(delta: float, peel_speed: float) -> void:
	for section in sections:
		section.d_center -= peel_speed * delta
	for i in range(sections.size() - 1, -1, -1):
		if sections[i].d_center + sections[i].half_width <= GONE_D:
			sections.remove_at(i)
	if enabled and sections.size() < MAX_ACTIVE:
		var kind := pick_kind()
		var half_width: float = KINDS[kind].half_width
		var last_edge := sections[-1].d_center + sections[-1].half_width if not sections.is_empty() else -INF
		if SPAWN_D - half_width - last_edge >= _gap:
			sections.append(ReefSection.new(kind, SPAWN_D, KINDS[kind]))
			_gap = rng.randf_range(GAP_MIN, GAP_MAX)


## The next kind, weighted by maturity.
func pick_kind() -> Kind:
	var bowl := lerpf(BOWL_CHANCE_EARLY, BOWL_CHANCE_LATE, maturity)
	var race := lerpf(RACE_SHARE.x, RACE_SHARE.y, maturity)
	var channel := lerpf(CHANNEL_SHARE.x, CHANNEL_SHARE.y, maturity)
	var wall := maxf(1.0 - race - channel, 0.1)
	var roll := rng.randf()
	if roll < bowl:
		return Kind.REEF_BOWL
	roll = (roll - bowl) / (1.0 - bowl) * (race + channel + wall)
	if roll < race:
		return Kind.RACECOURSE
	if roll < race + channel:
		return Kind.DEEP_CHANNEL
	return Kind.CRUISER_WALL


## Testing: clears the reef and puts one section of `kind` centred at `at_d`.
func force(kind: Kind, at_d: float) -> void:
	sections.clear()
	sections.append(ReefSection.new(kind, at_d, KINDS[kind]))
	_gap = GAP_MIN


## How much of `kind` there is at d, 0 to 1.
func weight_of(kind: Kind, d: float) -> float:
	var total := 0.0
	for section in sections:
		if section.kind == kind:
			total += section.weight(d)
	return minf(total, 1.0)


## The size offset (WaveModel's size dial) at d.
func size_delta_at(d: float) -> float:
	var total := 0.0
	for section in sections:
		total += section.delta_size * section.weight(d)
	return total


## The hollowness offset at d.
func hollow_delta_at(d: float) -> float:
	var total := 0.0
	for section in sections:
		total += section.delta_hollow * section.weight(d)
	return total


## How much faster (or slower) than usual the break peels at d.
func peel_mult_at(d: float) -> float:
	var mult := 1.0
	for section in sections:
		mult += (section.peel_mult - 1.0) * section.weight(d)
	return mult


## The kind that is strongest at d (a cruiser wall where there is none).
func kind_at(d: float) -> Kind:
	var best := Kind.CRUISER_WALL
	var best_weight := 0.05
	for section in sections:
		var w := section.weight(d)
		if w > best_weight:
			best = section.kind
			best_weight = w
	return best


## The section nearest ahead of d still to come (or reaching it), or null.
func next_ahead(d: float) -> ReefSection:
	var found: ReefSection = null
	for section in sections:
		if section.d_center + section.half_width > d and (found == null or section.d_center < found.d_center):
			found = section
	return found


## What the shaders need for section `index` (0 or 1): (centre, half width, height gain, kind), where the height gain
## is the factor the section adds to the wave's height for a wave of `height` meters between min_height and max_height.
## An empty slot has no width.
func uniform_for(index: int, height: float, min_height: float, max_height: float) -> Vector4:
	if index >= sections.size():
		return Vector4(1000.0, 0.001, 0.0, 0.0)
	var section := sections[index]
	return Vector4(section.d_center, section.half_width, section.delta_size * (max_height - min_height) / height, float(section.kind))
