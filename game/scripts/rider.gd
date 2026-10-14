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
const THETA_MIN := -1.45
const THETA_MAX := 1.55
const SPRING_K := 324.0              # board heading: critically damped, about 50 ms (natural frequency 18 rad/s)
const SPRING_D := 36.0
const COMPRESSION_K := 100.0         # hips: slightly underdamped, about 120 ms (natural frequency 10 rad/s)
const COMPRESSION_D := 17.0
const LEAD_MAX := 0.8
const MIN_SPEED := 0.45              # speeds are factors of the wave's own peel speed, so they follow the wave
const TRIM_SPEED := 1.05
const MAX_SPEED := 1.7
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


func step(delta: float, steer: float, height: float, model: WaveModel, tuning: TuningData) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	var peel := model.peel_speed()
	var v_min := MIN_SPEED * peel
	var v_trim := TRIM_SPEED * peel
	var v_max := MAX_SPEED * peel
	var face_h := maxf(1.2, model.crest_height_at(d))
	var sin_phi := sin(model.face_angle(u))
	# The wave's own pull up the face. Holding a line needs a slightly nose-down heading that cancels it (theta_trim).
	var draw := tuning.v_draw_base * clampf(face_h / 2.5, 0.4, 1.3)
	if _fresh:
		_fresh = false
		v = v_trim
		theta = -asin(clampf(draw / maxf(v * sin_phi, 0.5), 0.0, 0.6))
	var theta_trim := -asin(clampf(draw / maxf(v * sin_phi, 0.5), 0.0, 0.6))

	# Interim input: aim at a point on the wave. Height error becomes a heading, distance error a drive.
	var want_u := u_for(height)
	var want_d := d_for(steer)
	var target_theta := clampf(theta_trim + clampf(tuning.heading_gain * (want_u - u), -1.0, 1.0), THETA_MIN, THETA_MAX)
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
	var target_crouch := clampf(0.22 + absf(omega) * 0.25 + model.barrel_amount_at(d, u) * 0.65, 0.1, 1.0)
	compression_vel += (COMPRESSION_K * (target_crouch - compression) - COMPRESSION_D * compression_vel) * delta
	compression = clampf(compression + compression_vel * delta, 0.0, 1.0)

	# Energy: the slope gives speed going down and takes it going up, water and carving take some, and extending
	# out of a crouch in the middle of a carve pumps. Drag is chosen so that the trim heading settles at trim speed.
	var phi_mid := model.face_angle(0.5)
	var ref_trim := asin(clampf(draw / (v_trim * sin(phi_mid)), 0.0, 0.6))
	var k_water := tuning.g_eff * sin(phi_mid) * sin(ref_trim) / (v_trim * v_trim)
	var a_slope := -tuning.g_eff * sin_phi * sin(theta)
	var a_drag := -k_water * v * v - tuning.k_carve * absf(omega) * v
	var mid_face := clampf(1.0 - absf(u - 0.45) * 1.8, 0.0, 1.0)
	var a_pump := tuning.k_pump * absf(omega) * maxf(0.0, -compression_vel) * mid_face * maxf(0.2, cos(theta))
	# Drive toward the speed that holds (or closes on) the point being aimed at; the slope still shows through.
	var want_v := peel / maxf(cos(theta), 0.35) + clampf(tuning.drive_reach * (want_d - d), -0.4 * peel, 0.8 * peel)
	var a_drive := clampf(tuning.drive_gain * (want_v - v), -tuning.max_drive, tuning.max_drive)
	v = clampf(v + (a_slope + a_drag + a_pump + a_drive) * delta, v_min, v_max)
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
