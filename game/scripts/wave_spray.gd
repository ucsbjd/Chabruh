class_name WaveSpray
extends Node2D
## The spit: when the lip falls into the trough it punches a burst of spray out of the barrel's mouth,
## forward and up. It fires from a few places along the break, each time that bit of lip lands, so it
## stays in step with the lip the shader is animating. (The mist along the crest is in the 3D scene:
## see WaveMist and mist3d.gdshader.)

## Meters ahead of the peel point where lips land: one every few meters through the break.
const SPIT_POINTS: Array[float] = [-0.5, -2.6, -4.7, -7.2, -9.8]
const ARC_CENTRE := -122.0           # degrees on screen (0 right, negative up): forward, up and over
const ARC_HALF_WIDTH := 40.0
const RAYS := 18
const SPEEDS := Vector2(1.4, 5.2)    # meters per second
const AMOUNT_GENTLE := 12
const AMOUNT_FULL := 64
const LIFETIME := 0.95
const GRAVITY_METERS := 6.0
const DRAG := Vector2(0.7, 1.3)
const DROPLET_SCALE := 0.7
const REFERENCE_PIXELS_PER_METER := 104.0

var _emitters: Array[CPUParticles2D] = []
var _last_phase: Array[float] = []
var _droplet := SprayTextures.droplet()
var _gradient := Gradient.new()
var _fall_off := Curve.new()
var _spat := 0


func _init() -> void:
	_fall_off.add_point(Vector2(0.0, 1.0))
	_fall_off.add_point(Vector2(1.0, 0.35))
	_gradient.add_point(0.55, Color.WHITE)
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	for i in RAYS:
		var t := i / float(RAYS - 1) - 0.5
		points.append(Vector2.ZERO)
		normals.append(Vector2.from_angle(deg_to_rad(ARC_CENTRE + t * 2.0 * ARC_HALF_WIDTH)))
	for i in SPIT_POINTS.size():
		var emitter := CPUParticles2D.new()
		emitter.emitting = false
		emitter.one_shot = true
		emitter.explosiveness = 0.9
		emitter.local_coords = false
		emitter.texture = _droplet
		emitter.particle_flag_align_y = true
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_DIRECTED_POINTS
		emitter.emission_points = points
		emitter.emission_normals = normals
		emitter.direction = Vector2.RIGHT
		emitter.spread = 2.0
		emitter.damping_min = DRAG.x
		emitter.damping_max = DRAG.y
		emitter.scale_amount_curve = _fall_off
		emitter.color_ramp = _gradient
		emitter.lifetime = LIFETIME
		emitter.amount = AMOUNT_FULL
		add_child(emitter)
		_emitters.append(emitter)
		_last_phase.append(-1.0)


## Call every frame: follows the break on screen and fires the spit as each lip lands.
func update(stage: WaveStage, at_time: float) -> void:
	var model := stage.model
	for i in SPIT_POINTS.size():
		var d := SPIT_POINTS[i]
		var phase := stage.lip_phase_at(d, at_time)
		var crossed := _last_phase[i] >= 0.0 and _last_phase[i] < WaveStage.LIP_LANDING_PHASE and phase >= WaveStage.LIP_LANDING_PHASE
		_last_phase[i] = phase
		var landing := model.lip_landing_point(d)
		var at := stage.project(landing)
		var emitter := _emitters[i]
		emitter.position = at
		if not crossed:
			continue
		var pixels_per_meter := at.distance_to(stage.project(landing + Vector3.UP))
		# A big hollow wave spits hard; a small spilling one only puffs.
		var strength := model.throw_at(d) * (0.3 + 0.7 * model.barrel()) * (0.45 + 0.55 * model.size)
		# Behind the break the whitewater itself crashes and throws spray, whatever the wave.
		strength = maxf(strength, model.whitewater_at(d) * (0.45 + 0.4 * model.size))
		if strength > 0.02:
			_fire(emitter, strength, pixels_per_meter)


## Tints the droplets from the mood.
func apply_mood(mood: MoodData) -> void:
	_gradient.set_color(0, mood.foam_lit.lerp(mood.sun_glint, 0.35))
	_gradient.set_color(1, mood.foam_lit)
	_gradient.set_color(2, Color(mood.foam_shade, 0.0))


## Throws one spit now, strength 0 to 1, from the next lip in turn (also used to look at it).
func spit(strength: float, stage: WaveStage) -> void:
	var d := SPIT_POINTS[_spat % SPIT_POINTS.size()]
	var landing := stage.model.lip_landing_point(d)
	var at := stage.project(landing)
	_emitters[_spat % SPIT_POINTS.size()].position = at
	_fire(_emitters[_spat % SPIT_POINTS.size()], strength, at.distance_to(stage.project(landing + Vector3.UP)))
	_spat += 1


## The most droplets the spit can have alive at once.
func particle_budget() -> int:
	var total := 0
	for emitter in _emitters:
		total += emitter.amount
	return total


func _fire(emitter: CPUParticles2D, strength: float, pixels_per_meter: float) -> void:
	var s := clampf(strength, 0.0, 1.0)
	emitter.amount = int(lerpf(AMOUNT_GENTLE, AMOUNT_FULL, s))
	emitter.initial_velocity_min = SPEEDS.x * pixels_per_meter
	emitter.initial_velocity_max = lerpf(SPEEDS.x * 1.8, SPEEDS.y, s) * pixels_per_meter
	emitter.gravity = Vector2(0.0, GRAVITY_METERS * pixels_per_meter)
	var droplet_scale := DROPLET_SCALE * pixels_per_meter / REFERENCE_PIXELS_PER_METER
	emitter.scale_amount_min = droplet_scale * 0.6
	emitter.scale_amount_max = droplet_scale * 1.3
	emitter.restart()
	emitter.emitting = true
