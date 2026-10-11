class_name RidgeLayer
extends Node2D
## One silhouette layer on the horizon: a ridge line and, optionally, palms standing on it.
## Built once in height units (1.0 is the screen height) and scaled to the screen by world.gd.
## The pattern repeats every PERIOD, so scrolling is a position shift that wraps.

const PERIOD := 4.0
const SAMPLE_STEP := 0.05
const SPAN_FROM := -1          # periods built to the left of 0
const SPAN_TO := 2             # periods built to the right of 0 (so up to 2 * PERIOD wide)
const PALM_TRUNK_WIDTH := 0.010
const FROND_COUNT := 7
const FROND_STEPS := 8

## How far this layer slides per unit of travel. Distant layers use small values.
@export var parallax := 0.05
@export var ridge_height := 0.06
@export var ridge_seed := 1.0
## Mood property that colours the ridge, and how much of its base fades into the haze.
@export var ridge_role := &"ridge_far"
@export_range(0.0, 1.0) var haze_amount := 0.5
## Palm clusters per PERIOD (0 for none) and how tall a palm stands.
@export var palm_clusters := 0
@export var palm_height := 0.17

var _horizon := 0.0
var _ridge := Polygon2D.new()
var _palms := Polygon2D.new()
var _base_count := 0


func _init() -> void:
	add_child(_ridge)
	add_child(_palms)


## Builds the ridge and palms standing on a horizon at height `horizon_y`. Call once.
func build(horizon_y: float) -> void:
	_horizon = horizon_y
	_build_ridge()
	_build_palms()


## Slides the layer for the given travel and scales it to a screen `unit` pixels high.
## `crop` is how much of the composition is hidden off the left edge (see MIN_LAYOUT_ASPECT).
func place(travel: float, unit: float, crop: float) -> void:
	scale = Vector2(unit, unit)
	position.x = (fposmod(travel * parallax, PERIOD) - crop) * unit


func apply_mood(mood: MoodData) -> void:
	var top: Color = mood.get(ridge_role)
	var base := top.lerp(mood.haze, haze_amount)
	var colors := PackedColorArray()
	for i in _base_count:
		colors.append(top)
	for i in _base_count:
		colors.append(base)
	_ridge.vertex_colors = colors
	_palms.color = mood.palm


func _height_at(x: float) -> float:
	var u := TAU * x / PERIOD
	var n := 0.55 * sin(u + ridge_seed) + 0.30 * sin(3.0 * u + ridge_seed * 2.3) + 0.15 * sin(7.0 * u + ridge_seed * 4.1)
	return ridge_height * pow(clampf(0.5 + 0.5 * n, 0.0, 1.0), 1.4)


func _build_ridge() -> void:
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var x := SPAN_FROM * PERIOD
	while x <= SPAN_TO * PERIOD:
		top.append(Vector2(x, _horizon - _height_at(x)))
		bottom.append(Vector2(x, _horizon + 0.004))
		x += SAMPLE_STEP
	_base_count = top.size()
	bottom.reverse()
	# apply_mood colours the vertices in this order: every top point, then every bottom point.
	_ridge.polygon = top + bottom


func _build_palms() -> void:
	if palm_clusters == 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ridge_seed * 1000.0)
	var points := PackedVector2Array()
	var shapes: Array = []
	for period in range(SPAN_FROM, SPAN_TO):
		for cluster in palm_clusters:
			var centre := (period + (cluster + rng.randf_range(0.2, 0.8)) / palm_clusters) * PERIOD
			for palm in rng.randi_range(2, 3):
				var x := centre + (palm - 1) * rng.randf_range(0.05, 0.09)
				var lean := rng.randf_range(-0.35, 0.35)
				var tall := palm_height * rng.randf_range(0.75, 1.15)
				_add_palm(points, shapes, Vector2(x, _horizon - _height_at(x) + 0.006), tall, lean, rng)
	_palms.polygon = points
	_palms.polygons = shapes


# A palm is a tapering curved trunk plus a fan of drooping fronds, appended to one shared polygon.
func _add_palm(points: PackedVector2Array, shapes: Array, base: Vector2, tall: float, lean: float, rng: RandomNumberGenerator) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var crown := base
	for i in 7:
		var t := i / 6.0
		crown = base + Vector2(lean * tall * t * t, -tall * t)
		var half := lerpf(PALM_TRUNK_WIDTH, PALM_TRUNK_WIDTH * 0.5, t)
		left.append(crown + Vector2(-half, 0.0))
		right.append(crown + Vector2(half, 0.0))
	right.reverse()
	_append_shape(points, shapes, left + right)

	for k in FROND_COUNT:
		var angle := lerpf(-PI * 0.97, -PI * 0.03, k / float(FROND_COUNT - 1)) + rng.randf_range(-0.12, 0.12)
		var length := tall * rng.randf_range(0.42, 0.58)
		var spine := PackedVector2Array()
		var side_a := PackedVector2Array()
		var side_b := PackedVector2Array()
		for i in FROND_STEPS + 1:
			var s := i / float(FROND_STEPS)
			var point := crown + Vector2(cos(angle), sin(angle)) * length * s + Vector2(0.0, length * 0.55 * s * s)
			spine.append(point)
		for i in spine.size():
			var ahead := spine[mini(i + 1, spine.size() - 1)] - spine[maxi(i - 1, 0)]
			var normal := Vector2(-ahead.y, ahead.x).normalized()
			var half := length * 0.13 * pow(sin(PI * (i / float(FROND_STEPS)) * 0.92 + 0.12), 0.8)
			side_a.append(spine[i] + normal * half)
			side_b.append(spine[i] - normal * half)
		side_b.reverse()
		_append_shape(points, shapes, side_a + side_b)


func _append_shape(points: PackedVector2Array, shapes: Array, outline: PackedVector2Array) -> void:
	var first := points.size()
	points.append_array(outline)
	var indices := PackedInt32Array()
	for i in outline.size():
		indices.append(first + i)
	shapes.append(indices)
