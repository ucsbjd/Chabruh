class_name WaveMistBuilder
extends RefCounted
## The curtain built a few columns at a time (see WaveMesh.Builder). It stands on the crest as the mesh is built; the
## shader scales it with the live reef and swell like the wave.
## (Its own script rather than an inner class of WaveMist: see WaveMeshBuilder.)

const FIRST := -24.0                  # meters ahead of the peel point, so this is behind it
const LAST := 50.0
const STEP := 0.75
const ROWS := 4                       # points up the curtain
const HEIGHT_OF_WAVE := 0.62          # how tall the thickest mist stands, as a fraction of the wave's height
const LEAN := 0.35                    # the wind leans the top of the curtain away from the beach, meters per meter up

var mesh: ArrayMesh
var _model: WaveModel
var _columns := int((LAST - FIRST) / STEP) + 1
var _done := 0
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()


func _init(model: WaveModel) -> void:
	_model = model


## Does up to about `budget_usec` microseconds of work; true once the mesh is ready.
func step(budget_usec: int) -> bool:
	var start := Time.get_ticks_usec()
	while _done < _columns:
		var d := FIRST + _done * STEP
		var base := _model.base_crest_point(d)
		var amount := _model.mist_at(d)
		var stands := _model.height() * HEIGHT_OF_WAVE * (0.25 + 0.75 * amount)
		for row in ROWS:
			var up := row / float(ROWS - 1)
			_vertices.append(base + Vector3(0.0, up * stands, -up * stands * LEAN))
			_colors.append(Color(amount, 0.0, 0.0, 1.0))
			_uvs.append(Vector2(-d, up))
		_done += 1
		if Time.get_ticks_usec() - start > budget_usec:
			return false
	if mesh == null:
		mesh = _assemble()
	return true

func _assemble() -> ArrayMesh:
	var indices := PackedInt32Array()
	for i in _columns - 1:
		for row in ROWS - 1:
			var a := i * ROWS + row
			var b := a + 1
			var c := a + ROWS
			var e := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, e, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result
