class_name WaveMesh
extends RefCounted
## Sweeps the wave's cross-sections along the crest into a 3D mesh. Stations are packed close
## around the break, where the shape changes fastest, and spread out far down the line.
##
## Each vertex carries (in its colour) four shading attributes from the section: height up the
## wave, foam, how deep inside the barrel it is, and how thin (translucent) the water is. The
## UVs are (distance along the outline, distance along the crest) in meters, so a texture
## laid on the mesh is foreshortened by perspective for free.
##
## The vertex positions are the thrown lip. Two more shapes ride along so the shader can make the
## lip lift, throw and fall without a rebuild: CUSTOM0 holds (y, z) of the lifted shape and then
## of the landed shape, and UV2 holds (how much lip there is here, how much whitewater).

const CUSTOM_FORMAT := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


## Distances d (meters ahead of the peel point) of the stations, from far behind to far ahead.
static func station_distances() -> PackedFloat32Array:
	var distances := PackedFloat32Array([-30.0, -24.0, -19.0, -15.0, -12.0, -9.5, -8.0])
	var d := -7.0
	while d < 10.0:
		distances.append(d)
		d += 0.5
	distances.append_array(PackedFloat32Array([11.5, 13.0, 15.0, 17.5, 20.0, 23.0, 26.0, 30.0, 35.0, 40.0, 46.0, 52.0, 60.0]))
	return distances


static func build(model: WaveModel) -> ArrayMesh:
	var distances := station_distances()
	var sections: Array[WaveSection] = []
	var lifted: Array[WaveSection] = []
	var landed: Array[WaveSection] = []
	for d in distances:
		var thrown := model.section(d)
		sections.append(thrown)
		# Where there is no lip the three shapes are the same, so do the work once.
		var has_lip := model.throw_at(d) > 0.0
		lifted.append(model.section_key(d, WaveModel.LipShape.LIFTED) if has_lip else thrown)
		landed.append(model.section_key(d, WaveModel.LipShape.LANDED) if has_lip else thrown)
	var per_station := sections[0].points.size()

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var custom := PackedFloat32Array()
	for i in distances.size():
		var section := sections[i]
		var lip_here := model.throw_at(distances[i])
		var whitewater := model.whitewater_at(distances[i])
		# Distance along the outline, counted from the lip's tip: positive down the face, negative over
		# the back, so the shader can make a pattern climb toward the tip from both sides.
		var along := PackedFloat32Array([0.0])
		for j in range(1, per_station):
			along.append(along[j - 1] + section.points[j].distance_to(section.points[j - 1]))
		var from_tip := along[section.lip_tip]
		for j in per_station:
			var p := section.points[j]
			vertices.append(Vector3(-distances[i], p.y, p.x))
			colors.append(Color(section.height_fraction[j], section.foam[j], section.cavity[j], section.translucency[j]))
			uvs.append(Vector2(along[j] - from_tip, -distances[i]))
			uv2s.append(Vector2(lip_here, whitewater))
			var up := lifted[i].points[j]
			var down := landed[i].points[j]
			custom.append_array(PackedFloat32Array([up.y, up.x, down.y, down.x]))

	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in distances.size():
		for j in per_station:
			var across := vertices[_index(i, mini(j + 1, per_station - 1), per_station)] - vertices[_index(i, maxi(j - 1, 0), per_station)]
			var down_line := vertices[_index(mini(i + 1, distances.size() - 1), j, per_station)] - vertices[_index(maxi(i - 1, 0), j, per_station)]
			normals[_index(i, j, per_station)] = down_line.cross(across).normalized()

	var indices := PackedInt32Array()
	for i in distances.size() - 1:
		for j in per_station - 1:
			var a := _index(i, j, per_station)
			var b := _index(i, j + 1, per_station)
			var c := _index(i + 1, j, per_station)
			var e := _index(i + 1, j + 1, per_station)
			indices.append_array(PackedInt32Array([a, b, c, b, e, c]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, CUSTOM_FORMAT)
	return mesh


static func _index(station: int, point: int, per_station: int) -> int:
	return station * per_station + point
