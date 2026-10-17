class_name WaveCarveTrail
extends MeshInstance3D
## The mark the board leaves on the face: a ribbon of foam cut by the rail, a thin wake behind a trimming board and a wide
## white gouge out of a bottom turn or a cutback. Its points live in wave coordinates (d, u), so the wave carries them: they
## fall behind toward the curl as the break peels on (the water stays where it is), the water drawing up the face lifts
## them toward the lip, and the whitewater swallows them. One small triangle strip, rebuilt from the same arrays each frame.
##
## The wave's cross-section is too slow to build for every point every frame (about 0.1 ms each), so the face is cached as
## a grid: one column per WaveMesh station, filled the first time a point needs it, and one row per point up the face, so
## the ribbon lies on the triangles that are drawn. Each column also keeps the lifted and landed shapes of the lip's cycle,
## so the ribbon rises and falls with the face as wave3d.gdshader morphs it.

const CAPACITY := 32                  # points remembered behind the board
const LIFETIME := 1.4                 # seconds a point lasts
const RECORD_EVERY := LIFETIME / CAPACITY
const WIDTH_TRIM := 0.18              # meters: the thin wake of a board in trim...
const WIDTH_CARVE := 0.85             # ...and the gouge of a full-power turn
const WIDTH_GAIN := 1.6               # the gouge is full width at a power of 1 / WIDTH_GAIN
const WIDEN := 0.25                   # meters per second the foam spreads as it ages
const STRENGTH_TRIM := 0.35           # how solid the wake of a trimming board is; a full-power turn's gouge is solid
const LIFT_OFF := 0.03                # meters off the face, so the water never covers it
const TAIL_BEHIND := 0.28             # meters back along the board from the back foot (the spot being ridden) to the tail
const FADE_TOP := 0.85                # foam drawn up past this height on the face goes over the falls, gone by the top
const DRIFT := 1.0                    # the points fall behind at this share of the peel speed
const SEGMENTS := WaveModel.POINTS_FACE   # rows up the face: the drawn mesh's own points
const ROWS := SEGMENTS + 1

## Meters per second the water draws up the face per unit of WaveModel.draw_at: the rider's v_draw_base, so the foam climbs
## exactly as the water lifts him.
var draw_speed := 1.1

var _model: WaveModel
var _mesh := ArrayMesh.new()
var _stations := WaveMesh.station_distances()
## Per station, empty until needed: the face's points (z, y) from the top (u = 1) down to the trough, thrown, lifted and
## landed, then the thrown face's normals.
var _shapes: Array[PackedVector2Array] = []
## Per station: meters along the face per unit of u at each row, then the water's climb at each row (face heights a second
## per m/s of draw), then how much lip there is.
var _scalars: Array[PackedFloat32Array] = []

# The ring of points, newest at _newest. Wave coordinates, width in meters, strength 0 to 1, age in seconds, and how far
# (meters) the tail had travelled through the water when it left the point, which pins the foam pattern to the water.
var _d := PackedFloat32Array()
var _u := PackedFloat32Array()
var _width := PackedFloat32Array()
var _strength := PackedFloat32Array()
var _age := PackedFloat32Array()
var _along := PackedFloat32Array()
var _newest := -1
var _count := 0
var _since_record := 0.0
var _travelled := 0.0

# The strip, refilled in place every frame.
var _arrays := []
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for ring: PackedFloat32Array in [_d, _u, _width, _strength, _age, _along]:
		ring.resize(CAPACITY)
	_arrays.resize(Mesh.ARRAY_MAX)


## Takes a new wave shape: the cached face is thrown away and refilled as points need it. The points themselves stay.
func rebuild(model: WaveModel) -> void:
	_model = model
	_shapes.clear()
	_scalars.clear()
	_shapes.resize(_stations.size())
	_scalars.resize(_stations.size())


## Forgets the trail (the surfer was put somewhere, not ridden there).
func clear() -> void:
	_count = 0
	_newest = -1
	_since_record = 0.0
	_mesh.clear_surfaces()


## One frame of riding: the wave carries the points, the board's tail leaves a new one every RECORD_EVERY seconds, and the
## strip is rebuilt. (d, u) is the spot being ridden (the back foot), `heading` the rider's heading (0 down the line,
## positive up the face), `power` how hard the rail is biting (speed times sharpness, 0 to 1), `travel` how far the break has peeled (WaveStage.lip_travel).
func carve(delta: float, d: float, u: float, heading: float, power: float, travel: float) -> void:
	if _model == null or delta <= 0.0:
		return
	_advect(delta)
	var tail_d := d - TAIL_BEHIND * cos(heading)
	var tail_u := clampf(u - TAIL_BEHIND * sin(heading) / _scalar(tail_d, u, 0), 0.0, 1.0)
	var width := lerpf(WIDTH_TRIM, WIDTH_CARVE, clampf(power * WIDTH_GAIN, 0.0, 1.0))
	var strength := lerpf(STRENGTH_TRIM, 1.0, clampf(power, 0.0, 1.0))
	if _count > 0:
		_travelled = _along[_newest] + _water_distance(_d[_newest], _u[_newest], tail_d, tail_u)
	_since_record += delta
	if _count == 0 or _since_record >= RECORD_EVERY:
		_since_record = 0.0 if _count == 0 else minf(_since_record - RECORD_EVERY, RECORD_EVERY)
		_newest = (_newest + 1) % CAPACITY
		_count = mini(_count + 1, CAPACITY)
		_d[_newest] = tail_d
		_u[_newest] = tail_u
		_width[_newest] = width
		_strength[_newest] = strength
		_age[_newest] = 0.0
		_along[_newest] = _travelled
	_build(tail_d, tail_u, width, strength, travel)


## How many points the trail has now (not counting the one at the board).
func point_count() -> int:
	return _count


## The i-th newest point as (d, u, width, age).
func point(i: int) -> Vector4:
	var k := _index(i)
	return Vector4(_d[k], _u[k], _width[k], _age[k])


## The i-th newest point's strength, 0 to 1.
func point_strength(i: int) -> float:
	return _strength[_index(i)]


## Where on the face (d, u) is, as the shaders draw it once the break has peeled `travel` meters, LIFT_OFF meters off the water: a world position.
func face_point(d: float, u: float, travel: float) -> Vector3:
	var morph := WaveStage.lip_morph(WaveStage.lip_phase_at(d, travel))
	return _point(d, u, morph.x, morph.y)


func _index(i: int) -> int:
	return (_newest - i + CAPACITY) % CAPACITY


## The wave carries every point: back toward the curl as the break peels on, up the face with the water's draw. The foam
## spreads as it ages, and the oldest points go.
func _advect(delta: float) -> void:
	var back := DRIFT * _model.peel_speed() * delta
	for i in _count:
		var k := _index(i)
		_d[k] -= back
		_u[k] = minf(_u[k] + draw_speed * _scalar(_d[k], _u[k], ROWS) * delta, 1.0)
		_width[k] += WIDEN * delta
		_age[k] += delta
	while _count > 0 and _age[_index(_count - 1)] >= LIFETIME:
		_count -= 1


## Meters between two places on the face, as the water sees them.
func _water_distance(d0: float, u0: float, d1: float, u1: float) -> float:
	return Vector2(d1 - d0, (u1 - u0) * _scalar(d1, u1, 0)).length()


## Fills the strip: the board's tail first, then the points from newest to oldest, each one a pair of vertices either side
## of the track, on the face.
func _build(tail_d: float, tail_u: float, tail_width: float, tail_strength: float, travel: float) -> void:
	var n := _count + 1
	_mesh.clear_surfaces()
	if n < 2:
		return
	_vertices.resize(n * 2)
	_colors.resize(n * 2)
	_uvs.resize(n * 2)
	_uv2s.resize(n * 2)
	var side := Vector2(0.0, 1.0)
	for i in n:
		var d := tail_d if i == 0 else _d[_index(i - 1)]
		var u := tail_u if i == 0 else _u[_index(i - 1)]
		var width := tail_width if i == 0 else _width[_index(i - 1)]
		var strength := tail_strength if i == 0 else _strength[_index(i - 1)]
		var age := 0.0 if i == 0 else _age[_index(i - 1)]
		var along := _travelled if i == 0 else _along[_index(i - 1)]
		# Across the track, in meters on the face: square to the line from the point before to the point after.
		var stretch := _scalar(d, u, 0)
		var before := Vector2(tail_d, tail_u) if i <= 1 else Vector2(_d[_index(i - 2)], _u[_index(i - 2)])
		var after := Vector2(d, u) if i == n - 1 else Vector2(_d[_index(i)], _u[_index(i)])
		var run := Vector2(before.x - after.x, (before.y - after.y) * stretch)
		if run.length_squared() > 1e-6:
			side = Vector2(-run.y, run.x).normalized()
		var half := side * (width * 0.5)
		var morph := WaveStage.lip_morph(WaveStage.lip_phase_at(d, travel))
		var fade := strength * (1.0 - _model.whitewater_at(d)) * (1.0 - smoothstep(FADE_TOP, 1.0, u))
		var colour := Color(u, age / LIFETIME, 0.0, fade)
		for edge in 2:
			var flip := -1.0 if edge == 0 else 1.0
			var v := i * 2 + edge
			_vertices[v] = _point(d + half.x * flip, u + half.y * flip / stretch, morph.x, morph.y)
			_colors[v] = colour
			_uvs[v] = Vector2(along, width * 0.5 * flip)
			_uv2s[v] = Vector2(flip, 0.0)
	_arrays[Mesh.ARRAY_VERTEX] = _vertices
	_arrays[Mesh.ARRAY_COLOR] = _colors
	_arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLE_STRIP, _arrays)


## The face at (d, u) with the lip's cycle `lift` and `fall` of the way through (before the amount of lip there), LIFT_OFF
## off the water. Between stations and rows it blends straight across, as the drawn triangles do.
func _point(d: float, u: float, lift: float, fall: float) -> Vector3:
	var i := _station(d)
	var t := clampf((d - _stations[i]) / (_stations[i + 1] - _stations[i]), 0.0, 1.0)
	var r := (1.0 - clampf(u, 0.0, 1.0)) * SEGMENTS
	var k := mini(int(r), SEGMENTS - 1)
	var f := r - k
	var a := _shapes[i]
	var b := _shapes[i + 1]
	var lip_a := _scalars[i][ROWS * 2]
	var lip_b := _scalars[i + 1][ROWS * 2]
	var p := _morphed(a, k, f, lift * lip_a, fall * lip_a).lerp(_morphed(b, k, f, lift * lip_b, fall * lip_b), t) * _model.scale_at(d)
	var normal := a[ROWS * 3 + k].lerp(a[ROWS * 3 + k + 1], f).lerp(b[ROWS * 3 + k].lerp(b[ROWS * 3 + k + 1], f), t)
	p += normal.normalized() * LIFT_OFF
	return Vector3(-d, p.y, p.x)


## A column's face point between rows k and k + 1, morphed through the lip's cycle like the shader's vertices.
static func _morphed(shape: PackedVector2Array, k: int, f: float, lift: float, fall: float) -> Vector2:
	var thrown := shape[k].lerp(shape[k + 1], f)
	if lift == 0.0 and fall == 0.0:
		return thrown
	var lifted := shape[ROWS + k].lerp(shape[ROWS + k + 1], f)
	var landed := shape[ROWS * 2 + k].lerp(shape[ROWS * 2 + k + 1], f)
	return thrown + (lifted - thrown) * lift + (landed - thrown) * fall


## A cached number at (d, u), blended from the grid: `first` 0 is meters along the face per unit of u, ROWS the climb.
func _scalar(d: float, u: float, first: int) -> float:
	var i := _station(d)
	var t := clampf((d - _stations[i]) / (_stations[i + 1] - _stations[i]), 0.0, 1.0)
	var r := (1.0 - clampf(u, 0.0, 1.0)) * SEGMENTS
	var k := mini(int(r), SEGMENTS - 1)
	var f := r - k
	var a := _scalars[i]
	var b := _scalars[i + 1]
	return lerpf(lerpf(a[first + k], a[first + k + 1], f), lerpf(b[first + k], b[first + k + 1], f), t)


## The station at or before d (so d lies between it and the next), with both columns filled.
func _station(d: float) -> int:
	var i := clampi(_stations.bsearch(d) - 1, 0, _stations.size() - 2)
	if _shapes[i].is_empty():
		_fill(i)
	if _shapes[i + 1].is_empty():
		_fill(i + 1)
	return i


func _fill(i: int) -> void:
	var d := _stations[i]
	var lip := _model.throw_at(d)
	# The face as the mesh is built: the reef and the swell scale it live in _point, as the wave shader does.
	var thrown := _model.base_section_key(d, WaveModel.LipShape.THROWN)
	# Where there is no lip the shader does not morph, so the other two shapes are the thrown one.
	var lifted := _model.base_section_key(d, WaveModel.LipShape.LIFTED) if lip > 0.0 else thrown
	var landed := _model.base_section_key(d, WaveModel.LipShape.LANDED) if lip > 0.0 else thrown
	var face_height := maxf(1.2, _model.base_crest_height_at(d))
	var shape := PackedVector2Array()
	shape.resize(ROWS * 4)
	var scalars := PackedFloat32Array()
	scalars.resize(ROWS * 2 + 1)
	for k in ROWS:
		var p := thrown.face_from + k
		var u := 1.0 - k / float(SEGMENTS)
		shape[k] = thrown.points[p]
		shape[ROWS + k] = lifted.points[p]
		shape[ROWS * 2 + k] = landed.points[p]
		shape[ROWS * 3 + k] = thrown.face_normal(u)
		var below := mini(p + 1, thrown.face_to)
		scalars[k] = maxf(thrown.points[below - 1].distance_to(thrown.points[below]) * SEGMENTS, 0.05)
		scalars[ROWS + k] = _model.draw_at(d, u) / face_height
	scalars[ROWS * 2] = lip
	_shapes[i] = shape
	_scalars[i] = scalars
