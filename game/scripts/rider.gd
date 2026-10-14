class_name Rider
extends RefCounted
## The surfer's motion on the wave, as a snowboard-style carving model (docs/finger-surf-controls.md has the reasoning).
## Where they are on the wave: `d`, meters ahead of the peel point, and `u`, height up the face (0 trough, 1 crest).
## How they move: a heading `theta` in the face plane (0 down the line toward +d, negative nose down toward the
## trough, positive nose up toward the lip), the turn rate `omega`, a speed `v` in m/s and a hip `compression`.
## Dropping down the face trades height for speed and carving back up trades it back, so moves come out of the
## state instead of being played as clips. The nose leads: a target heading is followed by a stiff spring, the hips
## by a softer one, and `lead` says how far the head and chest should already be turned into the next move.
## For now the old input (a point on the wave to aim at) is turned into a target heading and a drive; the finger
## controls replace that in step 11. Spray and the wake come from speed times sharpness, as before.

const D_NEAR := -2.0                 # closest to the curl (inside the barrel zone)
const D_FAR := 12.0                  # far down the shoulder
const STEER_CURVE := 1.3             # puts the pocket near the middle of the steering range
const U_LOW := 0.06
const U_HIGH := 0.96
const THETA_MIN := -0.85                # easy mode: no diving so steeply that the curl catches him (cos(theta) keeps him up with it)
const THETA_MAX := 1.3
const SPRING_K := 324.0              # board heading: critically damped, about 50 ms (natural frequency 18 rad/s)
const SPRING_D := 36.0
const COMPRESSION_K := 100.0         # hips: slightly underdamped, about 120 ms (natural frequency 10 rad/s)
const COMPRESSION_D := 17.0
const LEAD_MAX := 0.8
const MIN_SPEED := 0.45              # speeds are factors of the wave's own peel speed, so they follow the wave
const TRIM_SPEED := 1.05
const MAX_SPEED := 2.1
const OMEGA_FULL := 3.0              # turn rate that counts as a fully sharp carve, rad/s
const MOVE_HOLD := 0.3               # seconds a move label stays once seen
const BURST_POWER := 1.9             # spray strength per unit of speed times sharpness

var d := 3.0
var u := 0.5
var vel_d := 0.0                     # meters per second, positive is ahead (to the left)
var vel_u := 0.0                     # face heights per second
var theta := 0.0
var omega := 0.0
var v := 0.0                         # meters per second along the heading
var speed := 0.5                     # v scaled to 0..1 between the wave's slowest and fastest riding speed
var compression := 0.2
var compression_vel := 0.0
var lead := 0.0                      # how far the head and chest are already turned into the coming move, radians
var rail_roll := 0.0                 # radians, onto the inside rail (positive) or the outside rail (negative)
var sharpness := 0.0
var move := "trim"

var _fresh := true
var _stick := 0.0                    # radians of heading the player is asking for; fades when the input stops
var _stick_sign := 0.0               # which way the last real push went, for pumping
var _stick_peak := 0.0               # the biggest push of that stroke
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


## Puts the rider somewhere, riding at trim speed and heading.
func place(meters_ahead: float, face_height: float) -> void:
	d = meters_ahead
	u = face_height
	vel_d = 0.0
	vel_u = 0.0
	omega = 0.0
	compression_vel = 0.0
	_fresh = true
	_stick = 0.0
	_stick_sign = 0.0
	_stick_peak = 0.0


## `height_push` is how far the player pushed up (+) or down (-) the face this frame, in face heights (scroll, keys, drag).
func step(delta: float, steer: float, height_push: float, model: WaveModel, tuning: TuningData) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	var peel := model.peel_speed()
	var v_min := MIN_SPEED * peel
	var v_trim := TRIM_SPEED * peel
	var v_max := MAX_SPEED * peel
	var face_h := maxf(1.2, model.crest_height_at(d))
	var sin_phi := sin(model.face_angle(u))
	# The wave's own pull up the face. With no input he is carried up it slowly (drift_climb, meters per second of
	# rise); holding his line takes a small nose-down heading, and pushing up or down the face starts from there.
	var draw := tuning.v_draw_base * clampf(face_h / 2.5, 0.4, 1.3)
	if _fresh:
		_fresh = false
		v = v_trim
		theta = asin(clampf((tuning.drift_climb - draw) / maxf(v * sin_phi, 0.5), -0.6, 0.6))
	var theta_trim := asin(clampf((tuning.drift_climb - draw) / maxf(v * sin_phi, 0.5), -0.6, 0.6))

	# Interim input: the change in the height setting (wheel, trackpad scroll, arrow keys) pushes a virtual stick that
	# fades back to centre, so scrolling down points the nose down and letting go lets the wave take him again.
	# Where along the wave to aim (the steering) stays a point on the wave, followed by driving faster or slower.
	_stick = clampf(_stick * exp(-delta / tuning.stick_decay) + height_push * tuning.stick_gain, -1.2, 1.2)
	var want_d := d_for(steer)
	var pump_kick := _pump(sin_phi, peel, tuning)
	var target_theta := clampf(theta_trim + _stick, THETA_MIN, THETA_MAX)
	# Easy mode: when the curl is gaining on him he cannot point up the face faster than it moves along the wave, so
	# climbing and carving never let it catch him.
	var behind := clampf((want_d - d - 0.2) / 1.0, 0.0, 1.0)
	if behind > 0.0:
		var keep_up := acos(clampf(0.95 * peel / maxf(v, 0.95 * peel), 0.0, 1.0))
		target_theta = lerpf(target_theta, clampf(target_theta, -keep_up, keep_up), behind)
	# Soft guardrails: scoop out of the trough and ease off at the crest instead of hitting them.
	if u < 0.15 and target_theta < 0.0:
		target_theta = lerpf(0.0, target_theta, clampf(u / 0.15, 0.0, 1.0))
	if u > 0.88 and target_theta > 0.0:
		target_theta = lerpf(target_theta, 0.0, clampf((u - 0.88) / 0.12, 0.0, 1.0))

	# Tier 1: the head and chest turn into the move at once. Tier 2: the board follows on a stiff spring.
	lead = clampf(target_theta - theta, -LEAD_MAX, LEAD_MAX)
	var authority := clampf(remap(v, v_min, v_max, 0.55, 1.15), 0.55, 1.15)
	omega = clampf(omega + (SPRING_K * (target_theta - theta) - SPRING_D * omega) * authority * delta, -tuning.max_omega, tuning.max_omega)
	theta = clampf(theta + omega * delta, THETA_MIN, THETA_MAX)
	# Tier 3: the hips sink into hard turns and the barrel, and rebound as the turn is left.
	# How low he gets: more with speed, more with how hard the direction is changing, most in the tube.
	var target_crouch := clampf(0.18 + 0.30 * speed + 0.30 * clampf(absf(omega) / 3.0, 0.0, 1.0) + model.barrel_amount_at(d, u) * 0.65, 0.1, 1.0)
	compression_vel += (COMPRESSION_K * (target_crouch - compression) - COMPRESSION_D * compression_vel) * delta
	compression = clampf(compression + compression_vel * delta, 0.0, 1.0)

	# Energy: the slope gives speed going down and takes it going up, and water and carving take some. Drag is chosen so
	# that the trim heading settles at trim speed. Pumping (small strokes up and down the face) adds speed in _pump().
	var phi_mid := model.face_angle(0.5)
	var ref_trim := asin(clampf((draw - tuning.drift_climb) / (v_trim * sin(phi_mid)), 0.0, 0.6))
	var k_water := tuning.g_eff * sin(phi_mid) * sin(ref_trim) / (v_trim * v_trim)
	var a_slope := -tuning.g_eff * sin_phi * sin(theta)
	var a_drag := -k_water * v * v - tuning.k_carve * absf(omega) * v
	# Drive toward the speed that holds (or closes on) the point being aimed at; the slope still shows through.
	var want_v := peel / maxf(cos(theta), 0.35) + clampf(tuning.drive_reach * (want_d - d), -0.4 * peel, 0.8 * peel)
	var a_drive := clampf(tuning.drive_gain * (want_v - v), -tuning.max_drive, tuning.max_drive)
	v = clampf(v + (a_slope + a_drag + a_drive) * delta + pump_kick, v_min, v_max)
	speed = clampf(remap(v, v_min, v_max, 0.0, 1.0), 0.0, 1.0)

	# Move along the wave: ahead of the peel point while faster than the curl, up the face by the heading's rise.
	var new_d := clampf(d + (v * cos(theta) - peel) * delta, D_NEAR, D_FAR)
	var new_u := clampf(u + ((v * sin(theta) * sin_phi + draw) / face_h) * delta, U_LOW, U_HIGH)
	vel_d = (new_d - d) / delta
	vel_u = (new_u - u) / delta
	d = new_d
	u = new_u
	rail_roll = clampf(omega * v * 0.038, -0.78, 0.78)

	# Sharpness: how hard the board is turning, held a moment so a snap throws spray and a wobble does not.
	sharpness = maxf(clampf(absf(omega) / OMEGA_FULL, 0.0, 1.0), sharpness)
	sharpness *= exp(-6.0 * delta)

	_update_spray(delta, tuning)
	_update_move(model, peel)


## Pumping: every time the stick reverses after a real stroke, the stroke's size is paid out as speed (a surfer or
## skater pumps by working the board up and down the slope). The steeper the face and the faster the wave, the more it gives.
func _pump(sin_phi: float, peel: float, tuning: TuningData) -> float:
	var kick := 0.0
	if absf(_stick) > 0.05:
		var way := signf(_stick)
		if way != _stick_sign:
			if _stick_sign != 0.0 and absf(_stick_peak) > tuning.pump_min_stroke:
				kick = tuning.k_pump * absf(_stick_peak) * sin_phi * peel
				compression_vel -= 4.0 * absf(_stick_peak)  # the rebound out of the stroke
			_stick_sign = way
			_stick_peak = 0.0
		if absf(_stick) > absf(_stick_peak):
			_stick_peak = _stick
	return kick


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


## Moves are labels the state earns, never buttons: a bottom turn happens low on the face, a top turn high.
func _update_move(model: WaveModel, peel: float) -> void:
	var seen := "trim"
	if model.barrel_amount_at(d, u) > 0.5 and compression > 0.5:
		seen = "barrel"
	elif u > 0.72 and theta > 0.65 and omega < -1.8:
		seen = "hit_the_lip"
	elif u > 0.9 and absf(theta) < 0.35:
		seen = "floater"
	elif u < 0.45 and omega > 1.0 and v > 0.65 * peel:
		seen = "bottom_turn"
	elif u > 0.5 and omega < -1.2 and d > 3.5:
		seen = "cutback"
	elif u > 0.55 and omega < -1.1:
		seen = "top_turn"
	# A move label stays a moment once seen, so it does not flicker.
	if seen != "trim" or _clock > _move_until:
		move = seen
		_move_until = _clock + MOVE_HOLD
