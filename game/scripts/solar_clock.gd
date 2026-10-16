class_name SolarClock
extends RefCounted
## Surfing until dark. While the surfer rides (and faster while the ride flows), the evening goes on: high golden light,
## the 80s sunset, electric dusk once the sun is down, and the bioluminescent night. With it the tide drops off the
## reef, so the wave gets bigger, hollower and faster and the bowls come more often. Nothing is counted or shown: the
## light, the colour and the wave are how the player feels it. A wipeout only steps the evening back a notch.
##
## `time` runs from 0 to END: each whole number is a phase (0 golden, 1 sunset, 2 dusk), and night begins at NIGHT.

const END := 3.0
const NIGHT := 2.6
const PHASE_NAMES: Array[String] = ["High Golden", "80s Sunset", "Electric Dusk", "Bioluminescent Night"]
const PHASE_STARTS: Array[float] = [0.0, 1.0, 2.0, NIGHT]
## Seconds of riding per phase, and the extra share of that rate while the flow is high.
const SECONDS_PER_PHASE := 45.0
const FLOW_BONUS_FROM := 0.7
const FLOW_BONUS := 0.5
## A wipeout puts the sun back this much (a little brighter), never all the way to the start.
const WIPEOUT_STEP_BACK := 0.35
## Where each mood is reached, as (time, mood): between two entries the look blends from one to the next.
const MOOD_KEYS := [[0.0, "golden"], [1.0, "sunset"], [2.0, "neon"], [NIGHT, "dusk"], [2.85, "bioluminescent"]]
## The tide over the reef as (time, wave size, hollowness, peel speed factor), eased between entries: mid-high tide
## through the golden hour, dropping through the sunset, a draining reef at dusk and night.
const TIDE_KEYS := [
	[0.0, 0.50, 0.42, 1.0], [0.8, 0.50, 0.42, 1.0],
	[1.2, 0.68, 0.65, 1.15], [1.9, 0.68, 0.65, 1.15],
	[2.2, 0.82, 0.85, 1.28], [END, 0.82, 0.85, 1.28],
]
## The sun's height on screen (its centre, in screen heights from the top; the horizon is at 0.40) as (time, height):
## it sinks through the evening and is gone below the horizon by night.
const SUN_KEYS := [[0.0, 0.15], [1.0, 0.24], [2.0, 0.36], [NIGHT, 0.62], [END, 0.85]]

var time := 0.0:
	set(value):
		time = clampf(value, 0.0, END)
## Paused, the evening holds where it is (a test hotkey, and the captures).
var running := true


## Moves the evening on by a frame of riding, faster when `flow` (0 to 1) is high.
func advance(delta: float, flow: float) -> void:
	if not running:
		return
	var bonus := FLOW_BONUS * smoothstep(FLOW_BONUS_FROM, 1.0, flow)
	time += delta / SECONDS_PER_PHASE * (1.0 + bonus)


## A wipeout: the sun comes back up a notch.
func step_back() -> void:
	time -= WIPEOUT_STEP_BACK


## The phase now, 0 to 3 (see PHASE_NAMES).
func phase() -> int:
	for i in range(PHASE_STARTS.size() - 1, -1, -1):
		if time >= PHASE_STARTS[i]:
			return i
	return 0


func phase_name() -> String:
	return PHASE_NAMES[phase()]


## Jumps to the start of phase `index` (testing, and the M key).
func jump_to_phase(index: int) -> void:
	time = PHASE_STARTS[clampi(index, 0, PHASE_STARTS.size() - 1)]


## Jumps to the start of the next phase, round to the first after night.
func next_phase() -> void:
	jump_to_phase((phase() + 1) % PHASE_STARTS.size())


## How far into the evening the session is, 0 to 1, for how often the reef throws bowls and racecourse walls.
func maturity() -> float:
	return clampf(time / NIGHT, 0.0, 1.0)


## The look now, as [from mood, to mood, how far between them].
func mood_blend() -> Array:
	for i in MOOD_KEYS.size() - 1:
		var a: Array = MOOD_KEYS[i]
		var b: Array = MOOD_KEYS[i + 1]
		if time < b[0]:
			return [a[1], b[1], smoothstep(a[0], b[0], time)]
	var last: Array = MOOD_KEYS[-1]
	return [last[1], last[1], 0.0]


## The tide now: (wave size, hollowness, peel speed factor).
func tide() -> Vector3:
	return _eased(TIDE_KEYS)


## The sun's height on screen now (see SUN_KEYS).
func sun_height() -> float:
	return _eased(SUN_KEYS).x


func _eased(keys: Array) -> Vector3:
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if time <= b[0]:
			var t := smoothstep(a[0], b[0], time)
			return Vector3(lerpf(a[1], b[1], t), lerpf(a[2], b[2], t) if a.size() > 2 else 0.0, lerpf(a[3], b[3], t) if a.size() > 3 else 0.0)
	var last: Array = keys[-1]
	return Vector3(last[1], last[2] if last.size() > 2 else 0.0, last[3] if last.size() > 3 else 0.0)
