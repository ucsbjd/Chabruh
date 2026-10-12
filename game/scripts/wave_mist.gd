class_name WaveMist
extends RefCounted
## The spray that blows off the crest, as a thin curtain standing on the wave's top edge and following
## it down the line. The curtain is only a surface to hang the shader's drifting droplets on: it is
## dense where the wave is breaking (and over the whitewater behind it), and sparse spindrift elsewhere.
## Vertex colour red is how much mist there is at that distance.

const FIRST := -24.0                  # meters ahead of the peel point, so this is behind it
const LAST := 50.0
const STEP := 0.75
const ROWS := 4                       # points up the curtain
const HEIGHT_OF_WAVE := 0.62          # how tall the thickest mist stands, as a fraction of the wave's height
const LEAN := 0.35                    # the wind leans the top of the curtain away from the beach, meters per meter up


static func build(model: WaveModel) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var columns := int((LAST - FIRST) / STEP) + 1
	for i in columns:
		var d := FIRST + i * STEP
		var base := model.crest_point(d)
		var amount := model.mist_at(d)
		var stands := model.height() * HEIGHT_OF_WAVE * (0.25 + 0.75 * amount)
		for row in ROWS:
			var up := row / float(ROWS - 1)
			vertices.append(base + Vector3(0.0, up * stands, -up * stands * LEAN))
			colors.append(Color(amount, 0.0, 0.0, 1.0))
			uvs.append(Vector2(-d, up))
	for i in columns - 1:
		for row in ROWS - 1:
			var a := i * ROWS + row
			var b := a + 1
			var c := a + ROWS
			var e := c + 1
			indices.append_array(PackedInt32Array([a, b, c, b, e, c]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
