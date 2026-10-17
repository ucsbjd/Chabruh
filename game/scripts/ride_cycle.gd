class_name RideCycle
extends RefCounted
## The rhythm around a ride, forever and with no hard fail. He paddles out and sits in the lineup on glassy water; a set
## shows as swell lines on the horizon, rolls in and stands up under him; he rides its wave through its life (the reef's
## sections, then it closes out), or kicks out over the shoulder, or the foam takes him in a soft tumble; then he drifts
## back to the lineup and waits for the next set. Lulls are a feature, never rushed, and each one is a little different.
##
## A wipeout is the curl catching him: far enough behind the peel point, in the whitewater and not in a barrel, for a
## moment (the foam takes him), or a bowl's lip landing right on his head high on the face behind the break.

enum State { PADDLE, LULL, SET, RIDING, WIPEOUT, DRIFT }

const PADDLE_TIME := 5.0             # seconds paddling out at the start
const LULL_TIMES := Vector2(9.0, 15.0)    # seconds sitting in the lineup between sets (random in this range)
const APPROACH_TIME := 7.0           # seconds from the set's lines showing on the horizon to him riding
const RISE_TIME := 2.5               # ...the last of which the swell stands up under him
const RIDE_TIMES := Vector2(28.0, 40.0)   # seconds a wave lives before it closes out
const SET_SIZE := 0.1                # each set's size and hollowness wander this much either side of the tide's
const SET_HOLLOW := 0.14
const WIPEOUT_TIME := 1.8            # seconds tumbling under the foam
const DRIFT_TIME := 3.0              # seconds drifting back out after a closeout or a kick out
const LULL_SWELL := 0.15             # the wave's height in the lull, as a factor
const FALL_SWELL := 0.7              # ...and as it rolls away from a wipeout
const SWELL_EASE := 1.2              # seconds for the swell to ease toward the lull's
const KICKOUT_D := 32.0              # meters out on the shoulder past which he kicks out...
const KICKOUT_TIME := 1.2            # ...after this long there
const CAUGHT_D := -2.0               # meters behind the peel point where the foam can take him...
const CAUGHT_FOAM := 0.4             # ...when there is this much whitewater...
const CAUGHT_TUBE := 0.3             # ...and less tube than this (deep in a real barrel is the reward, not a fall)
const CAUGHT_TIME := 1.5             # seconds there before he goes
const HEAD_U := 0.75                 # high on the face behind the break, a bowl's landing lip takes him
const HEAD_BOWL := 0.5

var state := State.RIDING
var timer := 0.0
var swell := 1.0                     # the wave's height as a factor (WaveModel.swell)
var set_size := 0.0                  # this set's offsets on top of the tide
var set_hollow := 0.0
var _caught := 0.0
var _out := 0.0
var _swell_from := 1.0
var _lull_time := LULL_TIMES.x
var _ride_time := RIDE_TIMES.y
var _rng := RandomNumberGenerator.new()


## Starts in the water paddling out (`intro`), or straight up riding (tests and captures).
func _init(intro := false, seed_value := 0) -> void:
	_rng.seed = seed_value if seed_value != 0 else Time.get_ticks_usec()
	_ride_time = _rng.randf_range(RIDE_TIMES.x, RIDE_TIMES.y)
	if intro:
		swell = LULL_SWELL
		_enter(State.PADDLE)


func riding() -> bool:
	return state == State.RIDING


## One frame. `lip_landing` says the lip is falling at the rider's place now. Returns what just started: "wipeout",
## "closeout", "kickout", "lull", "set", "ride", or "" when nothing changed.
func update(delta: float, rider: Rider, model: WaveModel, lip_landing: bool) -> String:
	timer += delta
	match state:
		State.RIDING:
			swell = minf(swell + delta / SWELL_EASE, 1.0)
			var deep := rider.d < CAUGHT_D and model.whitewater_at(rider.d) > CAUGHT_FOAM and model.barrel_amount_at(rider.d, rider.u) < CAUGHT_TUBE
			_caught = _caught + delta if deep else maxf(_caught - delta, 0.0)
			var on_head := rider.d < 0.0 and rider.u > HEAD_U and model.bowl_at(rider.d) > HEAD_BOWL and lip_landing
			if _caught > CAUGHT_TIME or on_head:
				wipeout()
				return "wipeout"
			_out = _out + delta if rider.d > KICKOUT_D else 0.0
			if _out > KICKOUT_TIME:
				_enter(State.DRIFT)
				return "kickout"
			if timer > _ride_time:
				_enter(State.DRIFT)
				return "closeout"
		State.WIPEOUT:
			swell = lerpf(swell, FALL_SWELL, 1.0 - exp(-delta / SWELL_EASE))
			if timer >= WIPEOUT_TIME:
				lull()
				return "lull"
		State.DRIFT, State.PADDLE:
			swell = lerpf(swell, LULL_SWELL, 1.0 - exp(-delta / (SWELL_EASE * 1.5)))
			if timer >= (DRIFT_TIME if state == State.DRIFT else PADDLE_TIME):
				lull()
				return "lull"
		State.LULL:
			swell = lerpf(swell, LULL_SWELL, 1.0 - exp(-delta / (SWELL_EASE * 0.5)))
			if timer >= _lull_time:
				next_set()
				return "set"
		State.SET:
			var rise := smoothstep(APPROACH_TIME - RISE_TIME, APPROACH_TIME, timer)
			swell = lerpf(_swell_from, 1.0, rise)
			if timer >= APPROACH_TIME:
				swell = 1.0
				_ride_time = _rng.randf_range(RIDE_TIMES.x, RIDE_TIMES.y)
				_enter(State.RIDING)
				return "ride"
	return ""


## The soft tumble, now.
func wipeout() -> void:
	_enter(State.WIPEOUT)


## Back in the lineup, waiting (from riding, or to cut a tumble short). Each lull is a little different.
func lull() -> void:
	_lull_time = _rng.randf_range(LULL_TIMES.x, LULL_TIMES.y)
	_enter(State.LULL)


## The next set starts rolling in now, with its own size and hollowness.
func next_set() -> void:
	_swell_from = swell
	set_size = _rng.randf_range(-SET_SIZE, SET_SIZE)
	set_hollow = _rng.randf_range(-SET_HOLLOW, SET_HOLLOW)
	_enter(State.SET)


## How far the set's lines have come in from the horizon, 0 (none showing) to 1 (here); 0 when no set is coming.
func approach() -> float:
	return clampf(timer / APPROACH_TIME, 0.0, 1.0) if state == State.SET else 0.0


## How far through the tumble he is, 0 to 1 (0 when not wiping out).
func tumble() -> float:
	return clampf(timer / WIPEOUT_TIME, 0.0, 1.0) if state == State.WIPEOUT else 0.0


## How low he sits in the water, 0 (standing) to 1 (down in it, sitting up waiting): down through the tumble, the
## drift and the lull, and back up as the set's wave stands up under him.
func sunk() -> float:
	match state:
		State.WIPEOUT:
			return smoothstep(0.0, 0.5, timer / WIPEOUT_TIME)
		State.DRIFT:
			return smoothstep(0.0, 0.6, timer)
		State.LULL, State.PADDLE:
			return 1.0
		State.SET:
			return 1.0 - smoothstep(APPROACH_TIME - 0.45, APPROACH_TIME, timer)
	return 0.0


func _enter(next: State) -> void:
	state = next
	timer = 0.0
	_caught = 0.0
	_out = 0.0
