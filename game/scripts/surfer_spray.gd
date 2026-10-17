class_name SurferSpray
extends Node2D
## The spray the surfer throws, in the style of the storyboard photos and the key frames: a wide radial
## fan thrown off the board's tail, much bigger than the surfer, thick near the tail and thinning to
## fine droplets at its edge; a foam wake on the water behind the board; and a splash for landings.
##
## One call drives it: `burst(strength)`, strength 0 to 1. Step 6 sets that from speed times how
## sharply the surfer turns. A gentle burst is a small low flick; a full one is the signature fan. `giant` (0 to 1) is
## how much of it is the speed he sheds stopping at the top of the wave: that fan is bigger, flies further and hangs in
## the air while he floats down under it.
## `set_hand_drag()` adds the thin sheet a hand throws up when it drags through the face in a big bottom turn, and
## `set_rail()` the curtain the rail throws the whole way round a cutback, sweeping round with the board.
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
## A giant fan (stopping at the top) has this much more of everything: droplets, launch speed, time in the air, and width.
const GIANT_AMOUNT := 0.4
const GIANT_SPEED := 0.3
const GIANT_LIFE := 0.4
const GIANT_WIDTH := 0.15
const GIANT_FRONT_CUT := 0.75        # how many fewer of a giant fan's fine droplets fly in front of the surfer
const RAY_JITTER := 0.4              # each burst moves every ray by up to this share of the gap between rays, so no two fans match
## Air drag, meters per second of speed lost each second (Godot's particle damping is a fixed loss of speed per second,
## in pixels, so it is scaled by the surfer's size on screen): the slow droplets hang near the tail while the fast ones
## fly on, so the fan thins out with range.
const DRAG := Vector2(1.0, 2.0)
const GRAVITY_METERS := 6.0          # a little less than real, so the arcs stay open
const DROPLET_SCALE := 0.8           # droplet size relative to the surfer's scale
const WAKE_AMOUNT := 36
const WAKE_LIFETIME := 1.6
const HAND_AMOUNT := 40
const HAND_LIFETIME := 0.45
const HAND_SPEED := Vector2(1.4, 3.2)  # meters per second, up and back from the fingers
## The cutback's curtain: a steady stream off the outside rail, aimed where the rail throws it each frame, so as the board
## swings round the stream paints a curving sheet (the slow-motion clip, 41 to 44 s), hanging a while as it falls.
const RAIL_AMOUNT := 160
const RAIL_LIFETIME := 1.2
const RAIL_SPEED := Vector2(2.5, 7.0)  # meters per second at full strength (half of it at the least)
const RAIL_SPREAD := 16.0
const RAIL_FROM := 0.08              # below this strength the rail throws nothing
## Pixels per meter the textures were drawn for; particle scales are relative to this.
const REFERENCE_PIXELS_PER_METER := 104.0
## The ride's flow (Rider.flow) makes every fan fuller and faster, from FLOW_LOW to FLOW_HIGH times, and from
## RIM_FROM to RIM_FULL the fine droplets at the fan's edge catch the mood's spray_rim highlight.
const FLOW_LOW := 0.85
const FLOW_HIGH := 1.3
const RIM_FROM := 0.75
const RIM_FULL := 0.95

var _pixels_per_meter := REFERENCE_PIXELS_PER_METER
var _next := 0
var _back := Node2D.new()
var _fans: Array[CPUParticles2D] = []
var _edges: Array[CPUParticles2D] = []
var _cores: Array[CPUParticles2D] = []
var _splash: CPUParticles2D
var _wake: CPUParticles2D
var _hand: CPUParticles2D
var _rail: CPUParticles2D
var _droplet := SprayTextures.droplet()
var _blob := SprayTextures.blob()
var _sheet := SprayTextures.sheet()
var _gradient := Gradient.new()
var _behind := ShaderMaterial.new()  # the back layer leaves out the real-time surfer's silhouette
var _edge_gradient := Gradient.new()
var _flow := 0.0
var _rim := 0.0
var _mood: MoodData
var _fall_off := Curve.new()


func _init() -> void:
	# Everything is attached here, not in _ready, so a spray that is never started cannot orphan nodes.
	_fall_off.add_point(Vector2(0.0, 1.0))
	_fall_off.add_point(Vector2(1.0, 0.35))
	_gradient.add_point(0.55, Color.WHITE)
	_edge_gradient.add_point(0.55, Color.WHITE)
	for i in POOL:
		_fans.append(_make_emitter(_back, _droplet))
		_cores.append(_make_emitter(_back, _blob))
		_edges.append(_make_emitter(self, _droplet))
		_edges[-1].color_ramp = _edge_gradient
	_splash = _make_emitter(self, _droplet)
	_wake = _make_emitter(_back, _sheet)
	_setup_wake()
	_hand = _make_emitter(self, _droplet)
	_setup_hand()
	_rail = _make_emitter(_back, _droplet)
	_setup_rail()
	_behind.shader = load("res://shaders/spray_behind.gdshader") as Shader
	for emitter: CPUParticles2D in _back.get_children():
		emitter.material = _behind
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


## Throws a fan of spray off the board's tail. `strength` is 0 (a small flick) to 1 (the full fan); `centre_degrees` is
## the way it goes on screen (0 is right, negative is up), off the outside of the turn.
func burst(strength: float, centre_degrees := FAN_CENTRE, giant := 0.0) -> void:
	var s := clampf(strength, 0.0, 1.0)
	var big := clampf(giant, 0.0, 1.0) * s
	var half_width := lerpf(FAN_HALF_WIDTH_GENTLE, FAN_HALF_WIDTH_FULL, pow(s, 0.7)) * (1.0 + GIANT_WIDTH * big)
	var speeds := FAN_SPEED_GENTLE.lerp(FAN_SPEED_FULL, s) * (1.0 + GIANT_SPEED * big)
	var life := lerpf(FAN_LIFETIME_GENTLE, FAN_LIFETIME_FULL, s) * (1.0 + GIANT_LIFE * big)
	var lively := lerpf(FLOW_LOW, FLOW_HIGH, _flow)
	speeds *= lively
	var more := (1.0 + GIANT_AMOUNT * big) * lively
	var index := _next % POOL
	_next += 1
	var size_scale := DROPLET_SCALE * _pixels_per_meter / REFERENCE_PIXELS_PER_METER

	_fire(_fans[index], int(lerpf(FAN_AMOUNT_GENTLE, FAN_AMOUNT_FULL, s) * more), life, centre_degrees, half_width, speeds, size_scale)
	# (the giant fan is a backdrop: in the gold standard he reads in front of it, so few of its droplets fly in front of him)
	_fire(_edges[index], int(lerpf(0.0, EDGE_AMOUNT_FULL, s * s) * more * (1.0 - GIANT_FRONT_CUT * big)), life * 0.9, centre_degrees, half_width * 1.12, speeds * EDGE_SPEED_BOOST, size_scale * 0.6)
	_fire(_cores[index], int(lerpf(2.0, CORE_AMOUNT_FULL, s)), life * 0.6, centre_degrees, half_width * 0.8, speeds * 0.5, size_scale * 1.1)


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


## A hand dragged through the face throws a thin sheet of droplets up and back. `at` is the hand on screen (in the
## parent's pixels) and `amount` 0 (none) to 1.
func set_hand_drag(at: Vector2, amount: float) -> void:
	_hand.position = at - position
	var wanted := int(HAND_AMOUNT * clampf(amount, 0.0, 1.0))
	_hand.emitting = wanted > 0
	if wanted > 0 and wanted != _hand.amount:
		_hand.amount = wanted


## The curtain the rail throws carving round a cutback: `amount` 0 (none) to 1, `angle_degrees` the way it leaves the
## tail on screen (0 is right, negative is up).
func set_rail(amount: float, angle_degrees: float) -> void:
	var on := amount > RAIL_FROM
	if on != _rail.emitting:
		_rail.emitting = on
	if on:
		var strength := lerpf(0.5, 1.0, clampf(amount, 0.0, 1.0))
		_rail.direction = Vector2.from_angle(deg_to_rad(angle_degrees))
		_rail.initial_velocity_min = RAIL_SPEED.x * strength * _pixels_per_meter
		_rail.initial_velocity_max = RAIL_SPEED.y * strength * _pixels_per_meter


## The real-time surfer's silhouette (WaveStage.surfer_mask()), so the spray behind him leaves his shape out; null
## when the sprite surfer is used (it is a 2D node, and the back layer already sits behind it).
func set_surfer_mask(mask: Texture2D) -> void:
	_behind.set_shader_parameter("surfer_mask", mask)
	_behind.set_shader_parameter("masked", mask != null)


## Puts the spray on the board's tail. `tail` is in the parent's pixels, `pixels_per_meter` is the
## surfer's on-screen scale, and `drift` is how fast the water slides past, in pixels per second.
func follow(tail: Vector2, pixels_per_meter: float, drift: float) -> void:
	position = tail
	_back.position = tail
	_pixels_per_meter = pixels_per_meter
	var gravity := Vector2(0.0, GRAVITY_METERS * pixels_per_meter)
	for emitter in _all_emitters():
		emitter.gravity = gravity if emitter != _wake else Vector2.ZERO
		if emitter != _wake:
			emitter.damping_min = DRAG.x * pixels_per_meter
			emitter.damping_max = DRAG.y * pixels_per_meter
	_wake.initial_velocity_min = drift * 0.9
	_wake.initial_velocity_max = drift * 1.25
	_wake.scale_amount_min = 0.45 * pixels_per_meter / REFERENCE_PIXELS_PER_METER
	_wake.scale_amount_max = 0.95 * pixels_per_meter / REFERENCE_PIXELS_PER_METER
	_wake.emission_rect_extents = Vector2(0.25, 0.05) * pixels_per_meter
	_hand.initial_velocity_min = HAND_SPEED.x * pixels_per_meter
	_hand.initial_velocity_max = HAND_SPEED.y * pixels_per_meter
	_hand.scale_amount_min = 0.25 * DROPLET_SCALE * pixels_per_meter / REFERENCE_PIXELS_PER_METER
	_hand.scale_amount_max = 0.55 * DROPLET_SCALE * pixels_per_meter / REFERENCE_PIXELS_PER_METER
	_rail.scale_amount_min = 0.6 * DROPLET_SCALE * pixels_per_meter / REFERENCE_PIXELS_PER_METER
	_rail.scale_amount_max = 1.3 * DROPLET_SCALE * pixels_per_meter / REFERENCE_PIXELS_PER_METER


## Tints the spray from the mood: cream and peach where the sun lands, violet as the droplets fall into shade.
func apply_mood(mood: MoodData) -> void:
	_mood = mood
	_gradient.set_color(0, mood.foam_lit.lerp(mood.sun_glint, 0.35))
	_gradient.set_color(1, mood.foam_lit)
	_gradient.set_color(2, Color(mood.foam_shade, 0.0))
	_tint_edges()


## How well the ride is flowing, 0 to 1 (Rider.flow): fuller, faster fans, and a bright rim on them when it is high.
func set_flow(amount: float) -> void:
	_flow = clampf(amount, 0.0, 1.0)
	var rim := smoothstep(RIM_FROM, RIM_FULL, _flow)
	if absf(rim - _rim) > 0.02 or (rim != _rim and (rim == 0.0 or rim == 1.0)):
		_rim = rim
		_tint_edges()


func _tint_edges() -> void:
	if _mood == null:
		return
	_edge_gradient.set_color(0, _mood.foam_lit.lerp(_mood.sun_glint, 0.35).lerp(_mood.spray_rim, _rim))
	_edge_gradient.set_color(1, _mood.foam_lit.lerp(_mood.spray_rim, _rim * 0.7))
	_edge_gradient.set_color(2, Color(_mood.foam_shade.lerp(_mood.spray_rim, _rim * 0.4), 0.0))


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
		if emitter == _wake or emitter == _hand or emitter == _rail:
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
	all.append(_hand)
	all.append(_rail)
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
	emitter.damping_min = DRAG.x * REFERENCE_PIXELS_PER_METER
	emitter.damping_max = DRAG.y * REFERENCE_PIXELS_PER_METER
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


## A steady stream, up and back from the fingers (he rides toward the left), off until a hand drags.
func _setup_hand() -> void:
	_hand.one_shot = false
	_hand.explosiveness = 0.0
	_hand.amount = HAND_AMOUNT
	_hand.lifetime = HAND_LIFETIME
	_hand.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	_hand.direction = Vector2(0.55, -1.0)
	_hand.spread = 24.0
	_hand.emitting = false


## A steady stream off the outside rail, off until a cutback carves round.
func _setup_rail() -> void:
	_rail.one_shot = false
	_rail.explosiveness = 0.0
	_rail.amount = RAIL_AMOUNT
	_rail.lifetime = RAIL_LIFETIME
	_rail.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
	_rail.direction = Vector2.from_angle(deg_to_rad(FAN_CENTRE))
	_rail.spread = RAIL_SPREAD
	_rail.emitting = false


## Sets up one fan emitter for a burst and starts it.
func _fire(emitter: CPUParticles2D, amount: int, life: float, centre_degrees: float, half_width: float, speeds: Vector2, droplet_scale: float) -> void:
	if amount <= 0:
		return
	_set_fan_points(emitter, centre_degrees, half_width)
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
## spread), at a random speed, so the fan shows radial lines of droplets instead of a random cloud. The rays shift a
## little each burst, so the spokes are irregular, as in the photos, and no two fans match.
func _set_fan_points(emitter: CPUParticles2D, centre_degrees: float, half_width_degrees: float) -> void:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	var gap := 1.0 / float(FAN_RAYS - 1)
	for i in FAN_RAYS:
		var t := clampf(i * gap + randf_range(-RAY_JITTER, RAY_JITTER) * gap, 0.0, 1.0) - 0.5
		points.append(Vector2.ZERO)
		normals.append(Vector2.from_angle(deg_to_rad(centre_degrees + t * 2.0 * half_width_degrees)))
	emitter.emission_points = points
	emitter.emission_normals = normals
