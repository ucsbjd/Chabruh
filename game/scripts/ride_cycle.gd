class_name RideCycle
extends RefCounted
## The rhythm around a ride, with no hard fail. Riding; a soft wipeout (a splash, a slow tumble under the foam while
## the wave rolls on); a lull, when the sea goes glassy and calm; then a new swell rising from the horizon, and he pops
## up into trim again. A lull can also come by itself (a test hotkey); lulls are a feature, never rushed.
##
## A wipeout is the curl catching him: far enough behind the peel point, in the whitewater and not in a barrel, for a
## moment (the foam takes him), or a bowl's lip landing right on his head high on the face behind the break.

enum State { RIDING, WIPEOUT, LULL, RISING }

const WIPEOUT_TIME := 1.8            # seconds tumbling under the foam
const LULL_TIME := 3.5               # seconds of glassy calm
const RISE_TIME := 2.0               # seconds for the next swell to stand up
const LULL_SWELL := 0.15             # the wave's height in the lull, as a factor
const FALL_SWELL := 0.7              # ...and as it rolls away from a wipeout
const SWELL_EASE := 1.2              # seconds for the swell to ease toward the lull's
const CAUGHT_D := -2.0               # meters behind the peel point where the foam can take him...
const CAUGHT_FOAM := 0.4             # ...when there is this much whitewater...
const CAUGHT_TUBE := 0.3             # ...and less tube than this (deep in a real barrel is the reward, not a fall)
const CAUGHT_TIME := 1.0             # seconds there before he goes
const HEAD_U := 0.75                 # high on the face behind the break, a bowl's landing lip takes him
const HEAD_BOWL := 0.5

var state := State.RIDING
var timer := 0.0
var swell := 1.0                     # the wave's height as a factor (WaveModel.swell)
var _caught := 0.0
var _swell_from := 1.0


func riding() -> bool:
	return state == State.RIDING


## One frame. `lip_landing` says the lip is falling at the rider's place now. Returns what just started: "wipeout",
## "lull", "rise", "ride", or "" when nothing changed.
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
		State.WIPEOUT:
			swell = lerpf(swell, FALL_SWELL, 1.0 - exp(-delta / SWELL_EASE))
			if timer >= WIPEOUT_TIME:
				_enter(State.LULL)
				return "lull"
		State.LULL:
			swell = lerpf(swell, LULL_SWELL, 1.0 - exp(-delta / (SWELL_EASE * 0.5)))
			if timer >= LULL_TIME:
				_swell_from = swell
				_enter(State.RISING)
				return "rise"
		State.RISING:
			swell = lerpf(_swell_from, 1.0, smoothstep(0.0, RISE_TIME, timer))
			if timer >= RISE_TIME:
				swell = 1.0
				_enter(State.RIDING)
				return "ride"
	return ""


## The soft tumble, now.
func wipeout() -> void:
	_enter(State.WIPEOUT)


## A lull, now (from riding, or to cut a tumble short).
func lull() -> void:
	_enter(State.LULL)


## How far through the tumble he is, 0 to 1 (0 when not wiping out).
func tumble() -> float:
	return clampf(timer / WIPEOUT_TIME, 0.0, 1.0) if state == State.WIPEOUT else 0.0


## How low he sits in the water, 0 (standing) to 1 (down in it, sitting up waiting): down through the tumble and the
## lull, and back up at the end of the rise.
func sunk() -> float:
	match state:
		State.WIPEOUT:
			return smoothstep(0.0, 0.5, timer / WIPEOUT_TIME)
		State.LULL:
			return 1.0
		State.RISING:
			return 1.0 - smoothstep(RISE_TIME - 0.45, RISE_TIME, timer)
	return 0.0


func _enter(next: State) -> void:
	state = next
	timer = 0.0
	_caught = 0.0
