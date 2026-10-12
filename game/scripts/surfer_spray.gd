class_name SurferSpray
extends Node2D
## The spray the surfer throws, in the style of the storyboard photos and the key frames: a wide radial
## fan thrown off the board's tail, much bigger than the surfer, thick near the tail and thinning to
## fine droplets at its edge; a foam wake on the water behind the board; and a splash for landings.
##
## One call drives it: `burst(strength)`, strength 0 to 1. Step 6 sets that from speed times how
## sharply the surfer turns. A gentle burst is a small low flick; a full one is the signature fan.
##
## Layers: this node sits just after the Surfer in the scene, so its droplets fly in front of them;
## the heavy body of the fan and the wake live in a second layer that is moved to just before the
## Surfer, so they fall behind. Every particle is a flat white oval, tinted from the current mood.

## The fan's arc on screen in degrees (0 is right, negative is up): over and behind the tail, since
## the surfer rides toward the left.
const FAN_CENTRE := -40.0
const FAN_HALF_WIDTH_GENTLE := 18.0
const FAN_HALF_WIDTH_FULL := 58.0
const FAN_RAYS := 30                 # distinct rays, so the fan reads as spokes and not as a cloud
const POOL := 3                      # bursts that can overlap before the oldest is cut
## How far the fan throws, in meters per second of launch speed (before drag), gentle to full.
const FAN_SPEED_GENTLE := Vector2(1.5, 3.0)
const FAN_SPEED_FULL := Vector2(3.0, 8.0)
const EDGE_SPEED_BOOST := 1.4       # the fine droplets at the edge fly farther than the body
const FAN_LIFETIME_GENTLE := 0.55
const FAN_LIFETIME_FULL := 1.3
const FAN_AMOUNT_GENTLE := 16
const FAN_AMOUNT_FULL := 190
const EDGE_AMOUNT_FULL := 90
const CORE_AMOUNT_FULL := 8
const SPLASH_AMOUNT_FULL := 110
const DRAG := Vector2(0.7, 1.3)      # velocity falls off like this per second, so droplets thin out with range
const GRAVITY_METERS := 6.0          # a little less than real, so the arcs stay open
const DROPLET_SCALE := 0.8           # droplet size relative to the surfer's scale
const WAKE_AMOUNT := 36
const WAKE_LIFETIME := 1.6
## Pixels per meter the textures were drawn for; particle scales are relative to this.
const REFERENCE_PIXELS_PER_METER := 104.0

var _pixels_per_meter := REFERENCE_PIXELS_PER_METER
var _next := 0
var _back := Node2D.new()
var _fans: Array[CPUParticles2D] = []
var _edges: Array[CPUParticles2D] = []
var _cores: Array[CPUParticles2D] = []
var _splash: CPUParticles2D
var _wake: CPUParticles2D
var _droplet := SprayTextures.droplet()
var _blob := SprayTextures.blob()
var _sheet := SprayTextures.sheet()
var _gradient := Gradient.new()
var _fall_off := Curve.new()


func _init() -> void:
	# Everything is attached here, not in _ready, so a spray that is never started cannot orphan nodes.
	_fall_off.add_point(Vector2(0.0, 1.0))
	_fall_off.add_point(Vector2(1.0, 0.35))
	_gradient.add_point(0.55, Color.WHITE)
	for i in POOL:
		_fans.append(_make_emitter(_back, _droplet))
		_cores.append(_make_emitter(_back, _blob))
		_edges.append(_make_emitter(self, _droplet))
	_splash = _make_emitter(self, _droplet)
	_wake = _make_emitter(_back, _sheet)
	_setup_wake()
	add_child(_back)


func _ready() -> void:
	# The parent is still adding its children, so wait a moment before moving the heavy layer.
	_place_back_layer.call_deferred()


## Moves the heavy layer to just before the Surfer, so it falls behind them.
func _place_back_layer() -> void:
	var parent := get_parent()
	if parent == null or _back.get_parent() != self:
		return
	var surfer := parent.get_node_or_null("Surfer")
	var at := surfer.get_index() if surfer != null else get_index()
	remove_child(_back)
	parent.add_child(_back)
	parent.move_child(_back, at)


## Throws a fan of spray off the board's tail. `strength` is 0 (a small flick) to 1 (the full fan).
func burst(strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	var half_width := lerpf(FAN_HALF_WIDTH_GENTLE, FAN_HALF_WIDTH_FULL, pow(s, 0.7))
	var speeds := FAN_SPEED_GENTLE.lerp(FAN_SPEED_FULL, s)
	var life := lerpf(FAN_LIFETIME_GENTLE, FAN_LIFETIME_FULL, s)
	var index := _next % POOL
	_next += 1
	var size_scale := DROPLET_SCALE * _pixels_per_meter / REFERENCE_PIXELS_PER_METER

	_fire(_fans[index], int(lerpf(FAN_AMOUNT_GENTLE, FAN_AMOUNT_FULL, s)), life, half_width, speeds, size_scale)
	_fire(_edges[index], int(lerpf(0.0, EDGE_AMOUNT_FULL, s * s)), life * 0.9, half_width * 1.12, speeds * EDGE_SPEED_BOOST, size_scale * 0.6)
	_fire(_cores[index], int(lerpf(2.0, CORE_AMOUNT_FULL, s)), life * 0.6, half_width * 0.8, speeds * 0.5, size_scale * 1.1)


## A splash round the board, for a landing after an air, `strength` 0 to 1.
func splash(strength: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	var size_scale := DROPLET_SCALE * _pixels_per_meter / REFERENCE_PIXELS_PER_METER
	_set_fan_points(_splash, -90.0, 70.0)
	_fire_with_points(_splash, int(lerpf(12.0, SPLASH_AMOUNT_FULL, s)), lerpf(0.5, 0.95, s), Vector2(1.0, lerpf(2.0, 4.6, s)), size_scale * 0.8)


## How much foam trails behind the board, 0 to 1 (0 turns it off).
func set_wake(amount: float) -> void:
	var wanted := int(WAKE_AMOUNT * clampf(amount, 0.0, 1.0))
	_wake.emitting = wanted > 0
	# Changing the count restarts the emitter, so only do it when it really changes.
	if wanted > 0 and wanted != _wake.amount:
		_wake.amount = wanted


## Puts the spray on the board's tail. `tail` is in the parent's pixels, `pixels_per_meter` is the
## surfer's on-screen scale, and `drift` is how fast the water slides past, in pixels per second.
func follow(tail: Vector2, pixels_per_meter: float, drift: float) -> void:
	position = tail
	_back.position = tail
	_pixels_per_meter = pixels_per_meter
	var gravity := Vector2(0.0, GRAVITY_METERS * pixels_per_meter)
	for emitter in _all_emitters():
		emitter.gravity = gravity if emitter != _wake else Vector2.ZERO
	_wake.initial_velocity_min = drift * 0.9
	_wake.initial_velocity_max = drift * 1.25
	_wake.scale_amount_min = 0.45 * pixels_per_meter / REFERENCE_PIXELS_PER_METER
	_wake.scale_amount_max = 0.95 * pixels_per_meter / REFERENCE_PIXELS_PER_METER
	_wake.emission_rect_extents = Vector2(0.25, 0.05) * pixels_per_meter


## Tints the spray from the mood: cream and peach where the sun lands, violet as the droplets fall into shade.
func apply_mood(mood: MoodData) -> void:
	_gradient.set_color(0, mood.foam_lit.lerp(mood.sun_glint, 0.35))
	_gradient.set_color(1, mood.foam_lit)
	_gradient.set_color(2, Color(mood.foam_shade, 0.0))


## The most droplets the spray can have alive at once, counting every pooled emitter at full strength.
func particle_budget() -> int:
	var total := 0
	for emitter in _all_emitters():
		total += emitter.amount
	return total


## How many droplets are alive right now (for the performance report).
func live_particles() -> int:
	var total := 0
	var now := Time.get_ticks_msec()
	for emitter in _all_emitters():
		if emitter == _wake:
			total += emitter.amount if emitter.emitting else 0
		elif now < int(emitter.get_meta("dies_at", 0)):
			total += emitter.amount
	return total


func _all_emitters() -> Array[CPUParticles2D]:
	var all: Array[CPUParticles2D] = []
	all.append_array(_fans)
	all.append_array(_edges)
	all.append_array(_cores)
	all.append(_splash)
	all.append(_wake)
	return all


func _make_emitter(layer: Node2D, texture: Texture2D) -> CPUParticles2D:
	var emitter := CPUParticles2D.new()
	emitter.emitting = false
	emitter.one_shot = true
	emitter.explosiveness = 0.92
	emitter.local_coords = false
	emitter.texture = texture
	emitter.particle_flag_align_y = true
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_DIRECTED_POINTS
	emitter.direction = Vector2.RIGHT
	emitter.spread = 2.0
	emitter.damping_min = DRAG.x
	emitter.damping_max = DRAG.y
	emitter.scale_amount_curve = _fall_off
	emitter.color_ramp = _gradient
	emitter.lifetime = 1.0
	emitter.amount = 1
	layer.add_child(emitter)
	return emitter


func _setup_wake() -> void:
	_wake.one_shot = false
	_wake.explosiveness = 0.0
	_wake.amount = WAKE_AMOUNT
	_wake.lifetime = WAKE_LIFETIME
	_wake.particle_flag_align_y = false
	_wake.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_wake.direction = Vector2.RIGHT
	_wake.spread = 5.0
	_wake.damping_min = 0.0
	_wake.damping_max = 0.0
	_wake.angle_min = -6.0
	_wake.angle_max = 6.0
	_wake.emitting = true


## Sets up one fan emitter for a burst and starts it.
func _fire(emitter: CPUParticles2D, amount: int, life: float, half_width: float, speeds: Vector2, droplet_scale: float) -> void:
	if amount <= 0:
		return
	_set_fan_points(emitter, FAN_CENTRE, half_width)
	_fire_with_points(emitter, amount, life, speeds, droplet_scale)


func _fire_with_points(emitter: CPUParticles2D, amount: int, life: float, speeds: Vector2, droplet_scale: float) -> void:
	emitter.amount = maxi(amount, 1)
	emitter.lifetime = life
	emitter.initial_velocity_min = speeds.x * _pixels_per_meter
	emitter.initial_velocity_max = speeds.y * _pixels_per_meter
	emitter.scale_amount_min = droplet_scale * 0.7
	emitter.scale_amount_max = droplet_scale * 1.4
	emitter.restart()
	emitter.emitting = true
	emitter.set_meta("dies_at", Time.get_ticks_msec() + int(life * 1000.0))


## Spokes: every particle leaves along one of FAN_RAYS directions across the arc (with a hair of
## spread), at a random speed, so the fan shows radial lines of droplets instead of a random cloud.
func _set_fan_points(emitter: CPUParticles2D, centre_degrees: float, half_width_degrees: float) -> void:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	for i in FAN_RAYS:
		var t := i / float(FAN_RAYS - 1) - 0.5
		points.append(Vector2.ZERO)
		normals.append(Vector2.from_angle(deg_to_rad(centre_degrees + t * 2.0 * half_width_degrees)))
	emitter.emission_points = points
	emitter.emission_normals = normals
