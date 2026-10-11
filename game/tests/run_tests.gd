extends SceneTree
## Headless smoke test. Run from the repo root:
##   godot_console --headless --path game --script res://tests/run_tests.gd
## Exits with the number of failed checks, so any failure is a non-zero exit code.

# Autoloads are not global names in --script mode, so reach the Palette code through its script.
const PaletteScript := preload("res://scripts/palette.gd")

# Colour uniforms that RidgeLayer sets from code, so they are not mood properties.
const CODE_FED_COLOURS: Array[String] = ["ridge_color"]

var _failures := 0


func _initialize() -> void:
	_test_main_scene()
	_test_moods()
	_test_shader_colours()
	_test_ridge_layer()
	_test_wave_model()
	_test_wave_section()
	_test_wave_mesh()
	_test_noise_textures()
	_test_pose_library()
	_test_surfer()
	_test_tuning()
	await _test_world()
	print("%s: %d failed" % ["FAIL" if _failures > 0 else "PASS", _failures])
	quit(_failures)


func _test_main_scene() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "main scene loads")
	if packed == null:
		return
	var main := packed.instantiate()
	_check(main != null, "main scene instantiates")
	_check(main.get_script() != null, "main scene script compiled")
	main.free()


func _test_moods() -> void:
	_check(root.has_node("Palette"), "Palette autoload exists")
	var expected := MoodData.property_names()
	_check(expected.size() > 0, "MoodData declares colour roles")
	_check(PaletteScript.MOOD_ORDER.has(PaletteScript.DEFAULT_MOOD), "default mood is one of the moods")
	for mood_name: String in PaletteScript.MOOD_ORDER:
		var table: Dictionary = PaletteScript.MOODS[mood_name]
		var missing: Array[String] = []
		for property in expected:
			if not table.has(property):
				missing.append(property)
		var unknown: Array[String] = []
		for key: String in table:
			if not key in expected:
				unknown.append(key)
		_check(missing.is_empty(), "%s mood defines every role %s" % [mood_name, missing])
		_check(unknown.is_empty(), "%s mood has no unknown roles %s" % [mood_name, unknown])

	var sunset := PaletteScript.build("sunset")
	var neon := PaletteScript.build("neon")
	var halfway := sunset.mixed_with(neon, 0.5)
	_check(halfway.sky_top.is_equal_approx(sunset.sky_top.lerp(neon.sky_top, 0.5)), "moods blend colours")
	_check(is_equal_approx(halfway.glow_strength, lerpf(sunset.glow_strength, neon.glow_strength, 0.5)), "moods blend strengths")


## Every colour uniform in a shader must be a MoodData property, or world.gd would never feed it
## (unless the code that owns the material feeds it, as listed in CODE_FED_COLOURS).
func _test_shader_colours() -> void:
	var names := MoodData.property_names()
	var shader_count := 0
	for file in DirAccess.get_files_at("res://shaders"):
		if not file.ends_with(".gdshader"):
			continue
		shader_count += 1
		var shader := load("res://shaders/" + file) as Shader
		for uniform in shader.get_shader_uniform_list():
			if uniform.type == TYPE_COLOR and not uniform.name in CODE_FED_COLOURS:
				_check(uniform.name in names, "%s: colour uniform '%s' is a MoodData role" % [file, uniform.name])
	_check(shader_count > 0, "shaders were found")


func _test_ridge_layer() -> void:
	var layer := RidgeLayer.new()
	layer.palm_clusters = 2
	layer.build(0.4)
	layer.apply_mood(PaletteScript.build("sunset"))
	var ridge: Polygon2D = layer.get_child(0)
	var palms: Polygon2D = layer.get_child(1)
	var sunset := PaletteScript.build("sunset")
	_check(ridge.polygon.size() > 0, "ridge has an outline")
	_check(ridge.material is ShaderMaterial, "ridge is coloured by a shader, not by redrawing polygons")
	_check(ridge.material.get_shader_parameter("ridge_color") == sunset.ridge_far, "ridge takes its colour from the mood")
	_check(palms.polygons.size() > 0, "palms were built")
	layer.free()


func _test_wave_model() -> void:
	var wave := WaveModel.new()

	wave.size = 0.0
	var small := wave.height()
	wave.size = 1.0
	var big := wave.height()
	_check(is_equal_approx(small, WaveModel.MIN_HEIGHT) and is_equal_approx(big, WaveModel.MAX_HEIGHT), "size spans the minimum to the maximum height")
	wave.size = 0.5
	var surfers := wave.height() / WaveModel.SURFER_HEIGHT
	_check(surfers > 1.4 and surfers < 2.0, "the default wave is about 1.7 surfers tall, like the key frames (%.2f)" % surfers)

	_check(wave.taper_at(0.0) > wave.taper_at(20.0) and wave.taper_at(20.0) > wave.taper_at(45.0), "the wall tapers down the line")
	_check(wave.crest_height_at(-8.0) < wave.crest_height_at(0.0) * 0.2, "the wall collapses behind the peel point")
	_check(wave.crest_height_at(-WaveModel.PROFILE_BEHIND) < 0.01, "the wave has faded out at the far end behind")

	var feet := wave.surface_point(2.0, 0.5)
	_check(is_equal_approx(feet.x, -2.0), "ahead of the peel point is toward negative x, along the crest")
	_check(is_zero_approx(wave.surface_point(2.0, 0.0).y), "height 0 on the face is the trough")
	_check(wave.surface_point(2.0, 1.0).y > feet.y and feet.y > 0.0, "the face climbs from the trough to its top")
	_check(wave.surface_point(2.0, 1.0).y < wave.crest_point(2.0).y + 0.001, "the top of the face is at or under the crest")
	_check(wave.surface_normal(2.0, 0.5).z > 0.0 and is_equal_approx(wave.surface_normal(2.0, 0.5).length(), 1.0), "the face looks out toward the beach")
	_check(wave.face_angle(1.0) > wave.face_angle(0.0), "the face steepens toward the crest")

	wave.size = 1.0
	wave.hollowness = 1.0
	_check(wave.barrel() > 0.9, "a big hollow wave is a full barrel")
	_check(wave.zone_at(8.0) == WaveModel.Zone.SHOULDER, "far ahead of the break is the shoulder")
	_check(wave.zone_at(2.0) == WaveModel.Zone.POCKET, "just ahead of the break is the pocket")
	_check(wave.zone_at(-1.0) == WaveModel.Zone.BARREL, "just behind the break of a hollow wave is the barrel")
	_check(wave.zone_at(-9.0) == WaveModel.Zone.WHITEWATER, "far behind the break is whitewater")
	var lip := wave.lip_tip_point(-1.0)
	_check(lip.z > wave.crest_point(-1.0).z, "the lip is thrown out toward the beach, past the crest")
	wave.hollowness = 0.0
	_check(is_zero_approx(wave.barrel()) and wave.zone_at(-1.0) == WaveModel.Zone.WHITEWATER, "a spilling wave has no barrel")
	wave.size = 0.0
	wave.hollowness = 1.0
	_check(is_zero_approx(wave.barrel()), "a tiny wave cannot hold a barrel")

	_check(is_equal_approx(WaveModel.peel_speed_for(0.5, 30.0), 1.0), "at a 30 degree peel angle the break moves at twice the wave speed")
	_check(is_equal_approx(WaveModel.peel_angle_for(0.5, 1.0), 30.0), "peel angle is the inverse of peel speed")
	wave.celerity = 0.5
	wave.peel_angle_degrees = 40.0
	_check(is_equal_approx(wave.peel_speed(), 0.5 / sin(deg_to_rad(40.0))), "the model's peel speed is celerity over sin of the peel angle")

	wave.size = 0.7
	wave.hollowness = 0.8
	var profile := wave.bake_profile()
	_check(profile.get_width() == WaveModel.PROFILE_WIDTH and profile.get_format() == Image.FORMAT_RGBAH, "the baked profile is a half-float strip")
	var matches := true
	for index in [150, 256, 380, 450]:
		var d := WaveModel.sample_distance(index)
		var pixel := profile.get_pixel(index, 0)
		var section := wave.section(d)
		matches = matches and absf(pixel.r - wave.crest_height_at(d)) < 0.01 and absf(pixel.g - section.points[section.face_to].x) < 0.01
		matches = matches and absf(pixel.b - wave.curl_at(d)) < 0.002 and absf(pixel.a - wave.foam_at(d)) < 0.002
	_check(matches, "the baked profile matches the model at sample points")


func _test_wave_section() -> void:
	var wave := WaveModel.new()
	wave.size = 0.8
	wave.hollowness = 1.0
	var section := wave.section(-1.0)
	var count := section.points.size()
	_check(count > 20 and section.height_fraction.size() == count and section.foam.size() == count, "a section has shading attributes for every point")
	var highest := 0.0
	for point in section.points:
		highest = maxf(highest, point.y)
	_check(is_equal_approx(section.points[section.crest].y, highest), "the crest is the highest point of the section")
	_check(absf(highest - wave.crest_height_at(-1.0)) < wave.crest_height_at(-1.0) * 0.12, "the section is as tall as the wave (%.2f of %.2f m)" % [highest, wave.crest_height_at(-1.0)])
	_check(is_zero_approx(section.face_point(0.0).y) and section.face_point(1.0).y > section.face_point(0.5).y, "the face runs from the trough up")
	_check(section.points[section.lip_tip].x > section.points[section.crest].x, "the lip tip is beyond the crest toward the beach")


func _test_wave_mesh() -> void:
	var wave := WaveModel.new()
	wave.size = 0.9
	wave.hollowness = 1.0
	var mesh := WaveMesh.build(wave)
	_check(mesh.get_surface_count() == 1, "the wave is one mesh surface")
	var arrays := mesh.surface_get_arrays(0)
	var stations := WaveMesh.station_distances().size()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	_check(vertices.size() == stations * wave.section(0.0).points.size(), "the mesh has one ring of vertices per station")
	_check(arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_NORMAL] != null and arrays[Mesh.ARRAY_TEX_UV] != null, "the mesh carries normals, shading attributes and UVs")
	var box := mesh.get_aabb()
	_check(box.position.x < -WaveModel.PROFILE_AHEAD * 0.9 and box.end.x > WaveModel.PROFILE_BEHIND * 0.9, "the mesh runs the length of the profile")
	_check(box.size.y > wave.height() * 0.8 and box.size.y < wave.height() * 1.25, "the mesh is as tall as the wave (%.2f of %.2f m)" % [box.size.y, wave.height()])
	_check(is_equal_approx(WaveMesh.station_distances()[0], -WaveModel.PROFILE_BEHIND) and is_equal_approx(WaveMesh.station_distances()[stations - 1], WaveModel.PROFILE_AHEAD), "the stations cover the whole profile")


func _test_noise_textures() -> void:
	for texture: ImageTexture in [NoiseTextures.cells(), NoiseTextures.warp()]:
		var image := texture.get_image()
		_check(image.get_width() == NoiseTextures.SIZE and image.get_height() == NoiseTextures.SIZE, "a noise texture is the expected size")
	var cells := NoiseTextures.cells().get_image()
	var darkest := 1.0
	var brightest := 0.0
	for y in cells.get_height():
		for x in cells.get_width():
			var value := cells.get_pixel(x, y).r
			darkest = minf(darkest, value)
			brightest = maxf(brightest, value)
	_check(darkest < 0.05 and brightest > 0.9, "the cell texture spans dark edges to bright centres")


## Poses the surfer rides in, with both feet on the board.
const RIDING_POSES: Array[String] = ["pop_up", "trim", "bottom_turn", "top_turn", "cutback", "barrel", "air", "floater", "paddle"]


func _test_pose_library() -> void:
	_check(PoseLibrary.ORDER.size() == PoseLibrary.POSES.size(), "the gallery order lists every pose")
	var complete_and_known := true
	var labelled := true
	for pose_name in PoseLibrary.ORDER:
		labelled = labelled and PoseLibrary.LABELS.has(pose_name) and PoseLibrary.has_pose(pose_name)
		for key: String in PoseLibrary.POSES[pose_name]:
			complete_and_known = complete_and_known and PoseLibrary.DEFAULT.has(key)
		complete_and_known = complete_and_known and PoseLibrary.complete(pose_name).size() == PoseLibrary.DEFAULT.size()
	_check(complete_and_known, "every pose fills in every joint and names no unknown joint")
	_check(labelled, "every pose has a label")
	var distinct := true
	for a in PoseLibrary.ORDER:
		for b in PoseLibrary.ORDER:
			distinct = distinct and (a == b or PoseLibrary.complete(a) != PoseLibrary.complete(b))
	_check(distinct, "no two poses are the same")
	_check(PoseLibrary.complete("nonsense") == PoseLibrary.DEFAULT, "an unknown pose name gives the default pose")


func _test_surfer() -> void:
	var surfer := Surfer.new()
	surfer.place(Vector2(640.0, 500.0), 180.0)
	_check(surfer.position == Vector2(640.0, 500.0), "the surfer's feet go where they are put")
	_check(is_equal_approx(surfer.scale.y * Surfer.STANDING_HEIGHT, 180.0), "the surfer is as tall as asked")

	surfer.set_pose("nonsense", 0.0)
	_check(surfer.pose_name() == "trim", "an unknown pose name changes nothing")

	var on_board := true
	var reach := true
	for pose_name in RIDING_POSES:
		surfer.set_pose(pose_name, 0.0)
		var values := PoseLibrary.complete(pose_name)
		for side in ["l", "r"]:
			var target := Vector2(values["foot_%s_x" % side], values["foot_%s_y" % side])
			var ankle := surfer.ankle_on_board(side)
			reach = reach and ankle.distance_to(target) < 0.02
			on_board = on_board and absf(ankle.x) < Surfer.BOARD_HALF and absf(ankle.y) < 0.2
	_check(reach, "in every riding pose each ankle reaches the spot it is asked to stand on")
	_check(on_board, "in every riding pose both feet stand on the board")

	# Blend from one pose to another a step at a time: the feet stay on the board, and nothing jumps.
	surfer.set_pose("trim", 0.0)
	surfer.set_pose("top_turn", Surfer.BLEND_SECONDS)
	var smooth := true
	var feet_kept := true
	var last := {"l": surfer.ankle_on_board("l"), "r": surfer.ankle_on_board("r")}
	for step in 30:
		surfer._process(0.01)
		for side in ["l", "r"]:
			var ankle := surfer.ankle_on_board(side)
			smooth = smooth and ankle.distance_to(last[side]) < 0.05
			feet_kept = feet_kept and absf(ankle.x) < Surfer.BOARD_HALF and absf(ankle.y) < 0.2
			last[side] = ankle
	_check(smooth, "blending between poses moves the feet smoothly, with no jumps")
	_check(feet_kept, "the feet stay on the board for the whole blend")
	var values := PoseLibrary.complete("top_turn")
	_check(absf(surfer.board_transform().get_rotation() - deg_to_rad(values.board_rot)) < deg_to_rad(1.0), "the board ends tilted to the pose (give or take the idle sway)")

	surfer.set_pose("air", 0.0)
	var air_height := surfer.board_transform().origin.y
	surfer.set_pose("trim", 0.0)
	_check(air_height > surfer.board_transform().origin.y, "the board sits lower in the air than on the wave")

	_check(surfer.materials().size() == 2, "the surfer's light uses two materials, so a mood fade redraws nothing")
	surfer.free()


## Runs the whole scene for a few frames with a big hollow wave and checks the pieces agree.
func _test_world() -> void:
	var world: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	world.set_wave(0.9, 1.0, 0.3)
	await process_frame
	await process_frame
	var stage: WaveStage = world.get_node("WaveStage")
	var materials := stage.materials()
	_check(materials.size() == 2 and materials[0].get_shader_parameter("noise_cells") is ImageTexture and materials[0].get_shader_parameter("noise_warp") is ImageTexture, "the wave shader has its noise textures")
	_check(materials[1].get_shader_parameter("profile") is ImageTexture, "the sea shader has the wave's profile texture")
	var mood: MoodData = root.get_node("Palette").current
	_check(materials[0].get_shader_parameter("wave_mid") == mood.wave_mid and materials[1].get_shader_parameter("swell_top") == mood.swell_top, "the 3D wave and sea are fed the mood's colours")
	_check(stage.model.barrel() > 0.5, "a big hollow wave is a barrel")

	var feet := stage.model.surface_point(world.peel_offset, world.SURFER_FACE_HEIGHT)
	var feet_px := stage.project(feet)
	var surfer: Surfer = world.get_node("Surfer")
	_check(surfer.position.is_equal_approx(feet_px), "the surfer stands on the face in the running scene")
	_check(is_equal_approx(surfer.scale.y * Surfer.STANDING_HEIGHT, feet_px.y - stage.project(feet + Vector3(0.0, WaveModel.SURFER_HEIGHT, 0.0)).y), "the surfer is the standard 1.8 m tall on screen")
	_check(absf(rad_to_deg(surfer.rotation)) <= world.MAX_GROUND_ANGLE, "the surfer tilts with the face, but never past the limit")
	world.set_surfer_pose("top_turn", 0.0)
	_check(surfer.pose_name() == "top_turn", "the scene can switch the surfer's pose")
	_check(surfer.materials()[0].get_shader_parameter("surfer_shade") == mood.surfer_shade and surfer.materials()[1].get_shader_parameter("surfer_rim") == mood.surfer_rim, "the surfer is fed the mood's shade and rim colours")
	var gallery: PoseGallery = world.get_node("PoseGallery")
	_check(not gallery.visible, "the pose gallery stays hidden unless asked for")
	gallery.open()
	await process_frame
	var surfers := 0
	for child in gallery.get_children():
		surfers += int(child is Surfer)
	_check(gallery.visible and surfers == PoseLibrary.ORDER.size() + 1, "the gallery shows every pose plus a cycler")
	gallery.close()
	_check(absf(feet_px.y / world.size.y - WaveStage.SURFER_SCREEN_Y) < 0.01, "the camera puts the surfer's feet at the planned height on screen")
	var head_px := stage.project(feet + Vector3(0.0, WaveModel.SURFER_HEIGHT, 0.0))
	var surfer_fraction := (feet_px.y - head_px.y) / world.size.y
	_check(surfer_fraction > 0.18 and surfer_fraction < 0.36, "the surfer is about a quarter of the screen height, like the key frames (%.2f)" % surfer_fraction)

	var spray := (world.get_node("Spray") as ColorRect).material as ShaderMaterial
	var spray_centre: Vector2 = spray.get_shader_parameter("centre")
	_check(spray.get_shader_parameter("radius") > 0.0 and spray_centre.y > 0.0 and spray_centre.y < 1.0, "the spray is centred on the crest, on screen")
	world.free()
	await process_frame


func _test_tuning() -> void:
	var tuning := load("res://data/tuning.tres") as TuningData
	_check(tuning != null, "tuning resource loads as TuningData")
	if tuning != null:
		_check(tuning.reach > 0.0, "tuning reach is positive")


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
	print("%s  %s" % ["ok  " if condition else "FAIL", name])
