class_name MovePlayer
extends RefCounted
## Plays a move through the same controls the player uses (the hotkeys L, C, F, T and P), so each move can be seen and
## felt: it pushes up and down the face and steers along the wave the way a player would, a phase at a time, watching
## where the surfer is rather than following a clock. The world hands the controls back the moment the player touches
## them. The capture tool and tests/ride_trace.gd play moves the same way.

const MOVES: Array[String] = ["lip_hit", "cutback", "floater", "tube", "pump"]
const LABELS := {"lip_hit": "hit the lip", "cutback": "cutback", "floater": "floater", "tube": "barrel crouch", "pump": "pump"}
## Pushes, in face heights a second: a steady scroll down or up the face, a gentle one, and the hard flick of a snap.
const PUSH := 1.2
const GENTLE := 0.6
const FLICK := 4.8
## Where each move happens: a cutback starts this far out in front, and the tube is ridden this far behind the peel point.
const CUTBACK_OUT := 10.0
const TUBE_DEPTH := -1.2
const HOLD_BACK := 0.3               # seconds a cutback is held on once he faces back toward the curl, riding back at it
const SNAP_TIME := 0.25              # seconds of hard push down at the lip
const FLOAT_TIME := 1.6              # seconds he is left to ride along the top in a floater
const TUBE_TIME := 3.0               # seconds he sits in the tube
const PUMP_TIME := 4.0               # seconds he chases down the line, pumping
## A drop and a climb push only until the heading he is asked for (Rider.aim) is this steep, in radians, then let the
## board turn to it and hold it, the way a player flicks him down the face or up it. A cutback's climb is moderate, so he
## is not committed to the lip.
const DROP_AIM := -0.8
const CUT_CLIMB_AIM := 0.6
const PHASE_LIMIT := 4.5             # seconds any phase may take before the move gives up (he is never stuck in one)

var move := ""                       # the move being played, or "" when none is
var phase := ""
var _phase_time := 0.0


func play(move_name: String) -> void:
	if move_name not in MOVES:
		return
	move = move_name
	_enter({"lip_hit": "drop", "cutback": "out", "floater": "climb", "tube": "back", "pump": "chase"}[move_name])


func stop() -> void:
	move = ""
	phase = ""


func playing() -> bool:
	return move != ""


## Call every frame before the rider steps: it moves the controls for the move being played.
func update(delta: float, rider: Rider, input: RideInput) -> void:
	if move == "":
		return
	_phase_time += delta
	match move:
		"lip_hit":
			_lip_hit(delta, rider, input)
		"cutback":
			_cutback(delta, rider, input)
		"floater":
			_floater(delta, rider, input)
		"tube":
			_tube(rider, input)
		"pump":
			_pump(input)
	if move != "" and _phase_time > PHASE_LIMIT:
		_finish(input)


## Down to the foot of the face, a bottom turn driving hard up it (committed to the lip), a hard flick down at the lip,
## then hands off while he floats down.
func _lip_hit(delta: float, rider: Rider, input: RideInput) -> void:
	match phase:
		"drop":
			input.steer = RideInput.REST_STEER
			input.nudge_height(-PUSH * delta)
			if rider.u < 0.22:
				_enter("climb")
		"climb":
			input.nudge_height(PUSH * 1.5 * delta)
			if rider.u > 0.86:
				_enter("snap")
		"snap":
			input.nudge_height(-FLICK * delta)
			if _phase_time > SNAP_TIME:
				_enter("float")
		"float":
			if _phase_time > 0.4 and rider.afloat < 0.05:
				_finish(input)


## Out in front, down and a bottom turn, a moderate climb into the upper face, then a push down held all the way round
## until he faces back toward the curl and on a moment, then let go: the board pivots back.
func _cutback(delta: float, rider: Rider, input: RideInput) -> void:
	match phase:
		"out":
			input.steer = Rider.steer_for(CUTBACK_OUT)
			if rider.d > Rider.CUT_ROOM + 4.0:
				_enter("drop")
		"drop":
			if rider.aim > DROP_AIM:
				input.nudge_height(-PUSH * delta)
			if rider.u < 0.3:
				_enter("climb")
		"climb":
			# (not so steep that he is committed to the lip: that would be a hit, not a cutback)
			if rider.aim < CUT_CLIMB_AIM:
				input.nudge_height(PUSH * delta)
			if rider.u > 0.38 and rider.theta > 0.15:
				_enter("carve")
		"carve":
			input.nudge_height(-PUSH * delta)
			if rider.rebounding:
				_enter("let_go")
			elif rider.theta < -(Rider.CUTBACK_REACH - 0.25):
				_enter("ride_back")
		"ride_back":
			input.nudge_height(-PUSH * delta)
			if _phase_time > HOLD_BACK or rider.rebounding:
				_enter("let_go")
		"let_go":
			if not rider.cutting_back:
				_finish(input)


## A gentle climb to the top, then hands off so he rides along it, then a gentle push down off it.
func _floater(delta: float, rider: Rider, input: RideInput) -> void:
	match phase:
		"climb":
			if rider.theta < 0.5:
				input.nudge_height(GENTLE * delta)
			if rider.u > 0.88:
				_enter("ride")
		"ride":
			if _phase_time > FLOAT_TIME:
				_enter("down")
		"down":
			input.nudge_height(-GENTLE * delta)
			if _phase_time > 0.6:
				_finish(input)


## Steer back into the pocket until the curl catches him, sit in the tube a while, then steer out again.
func _tube(rider: Rider, input: RideInput) -> void:
	match phase:
		"back":
			input.steer = 0.0
			if rider.d < 0.5:
				_enter("inside")
		"inside":
			input.steer = Rider.steer_for(TUBE_DEPTH)
			if _phase_time > TUBE_TIME:
				_finish(input)


## Steer far down the line so he chases it, pumping for speed, then back to the pocket.
func _pump(input: RideInput) -> void:
	input.steer = 0.95
	if _phase_time > PUMP_TIME:
		_finish(input)


func _enter(next_phase: String) -> void:
	phase = next_phase
	_phase_time = 0.0


## Hands the controls back with the surfer steered for the pocket, where he rests.
func _finish(input: RideInput) -> void:
	input.steer = RideInput.REST_STEER
	stop()
