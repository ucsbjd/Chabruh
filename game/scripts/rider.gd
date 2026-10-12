class_name Rider
extends RefCounted
## The surfer's motion on the wave: where they are (`d`, meters ahead of the peel point, and `u`, height
## up the face), how fast they feel (`speed`, 0 to 1) and how sharply they are turning (`sharpness`, 0 to 1).
## They follow the point the player aims at with a smooth, speed-limited spring, so nothing jumps. Pumping
## up and down the face builds speed, the pocket is fastest and the far shoulder slows you. Spray and the
## wake are driven from speed times sharpness, and a crude move label says what the motion looks like.

const D_NEAR := -2.0                 # closest to the curl (inside the barrel zone)
const D_FAR := 12.0                  # far down the shoulder
const STEER_CURVE := 1.3             # puts the pocket near the middle of the steering range
const U_LOW := 0.06
const U_HIGH := 0.96
const TURN_RATE_FULL := 7.0          # radians per second of heading change that count as the sharpest turn
const SPEED_SMOOTHING := 4.0
const MOVE_HOLD := 0.3               # seconds a move label stays once seen
const BURST_POWER := 1.9             # spray strength per unit of speed times sharpness

var d := 3.0
var u := 0.5
var vel_d := 0.0                     # meters per second, positive is ahead (to the left)
var vel_u := 0.0                     # face heights per second
var energy := 0.3
var speed := 0.5
var sharpness := 0.0
var move := "trim"

var _heading := 0.0
var _burst_ready_in := 0.0
var _pending_burst := 0.0
var _move_until := 0.0
var _clock := 0.0


static func d_for(steer: float) -> float:
	return lerpf(D_NEAR, D_FAR, pow(clampf(steer, 0.0, 1.0), STEER_CURVE))


static func steer_for(meters: float) -> float:
	return pow(clampf((meters - D_NEAR) / (D_FAR - D_NEAR), 0.0, 1.0), 1.0 / STEER_CURVE)


static func u_for(height: float) -> float:
	return lerpf(U_LOW, U_HIGH, clampf(height, 0.0, 1.0))


static func height_for(face_height: float) -> float:
	return clampf((face_height - U_LOW) / (U_HIGH - U_LOW), 0.0, 1.0)


## Puts the rider somewhere, with no motion.
func place(meters_ahead: float, face_height: float) -> void:
	d = meters_ahead
	u = face_height
	vel_d = 0.0
	vel_u = 0.0


func step(delta: float, steer: float, height: float, model: WaveModel, tuning: TuningData) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	var follow := 1.0 - exp(-tuning.follow_rate * delta)
	var new_d := d + clampf((d_for(steer) - d) * follow, -tuning.max_steer_speed * delta, tuning.max_steer_speed * delta)
	var new_u := u + clampf((u_for(height) - u) * follow, -tuning.max_height_speed * delta, tuning.max_height_speed * delta)
	var smooth := 1.0 - exp(-24.0 * delta)
	vel_d = lerpf(vel_d, (new_d - d) / delta, smooth)
	vel_u = lerpf(vel_u, (new_u - u) / delta, smooth)
	d = new_d
	u = new_u

	# Speed: a steeper face, pumping and the pocket make you fast; the shoulder slows you.
	var slope := sin(model.face_angle(u))
	energy = clampf(energy + (absf(vel_u) * tuning.pump_gain - energy * tuning.energy_decay) * delta, 0.0, 1.0)
	var pocket := 1.0 - smoothstep(0.0, 6.0, absf(d - 2.0))
	var shoulder := smoothstep(model.shoulder_length() * 0.35, model.shoulder_length(), d)
	var want_speed := clampf(0.2 + 0.3 * slope + 0.35 * energy + 0.2 * pocket - 0.4 * shoulder, 0.0, 1.0)
	speed = lerpf(speed, want_speed, 1.0 - exp(-SPEED_SMOOTHING * delta))

	# Sharpness: how fast the direction of travel (along the wave and up the face, in meters) is turning.
	var vy := vel_u * model.crest_height_at(d)
	var motion := Vector2(vel_d, vy).length()
	if motion > 0.4:
		var heading := atan2(vy, vel_d)
		var turn := absf(angle_difference(_heading, heading)) / delta
		_heading = heading
		var raw := clampf(turn / TURN_RATE_FULL, 0.0, 1.0) * smoothstep(0.5, 3.0, motion)
		sharpness = maxf(raw, sharpness)
	sharpness *= exp(-6.0 * delta)

	_update_spray(delta, tuning)
	_update_move()


## The strength of a spray that should be thrown now, 0 to 1, or 0 for none. Asking clears it.
func take_burst() -> float:
	var strength := _pending_burst
	_pending_burst = 0.0
	return strength


func _update_spray(delta: float, tuning: TuningData) -> void:
	_burst_ready_in = maxf(_burst_ready_in - delta, 0.0)
	var power := speed * sharpness
	if _burst_ready_in <= 0.0 and power > tuning.spray_threshold:
		_pending_burst = clampf(power * BURST_POWER, 0.0, 1.0)
		_burst_ready_in = tuning.spray_pause


func _update_move() -> void:
	var seen := "trim"
	if u > 0.88 and absf(vel_d) > 1.0 and absf(vel_u) < 0.5 and sharpness < 0.3:
		seen = "floater"
	elif u > 0.7 and sharpness > 0.3:
		seen = "hit_the_lip" if u > 0.88 else "top_turn"
	elif u < 0.45 and vel_u > 0.45:
		seen = "bottom_turn"
	elif vel_d < -1.5 and u > 0.2 and u < 0.85:
		seen = "cutback"
	# A move label stays a moment once seen, so it does not flicker.
	if seen != "trim" or _clock > _move_until:
		move = seen
		_move_until = _clock + MOVE_HOLD
