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
	_test_noise_textures()
	_test_scale_marker()
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

	_check(wave.crest_height_at(0.0) > wave.crest_height_at(1.0) and wave.crest_height_at(1.0) > wave.crest_height_at(3.0), "the wall tapers down the line")
	_check(wave.crest_height_at(-1.0) < wave.crest_height_at(0.0), "the wall collapses behind the peel point")
	_check(wave.base_y_at(3.0) < wave.base_y_at(0.0) and wave.base_y_at(3.0) > WaveModel.HORIZON, "the base line climbs toward the horizon down the line, but not past it")

	_check(is_equal_approx(wave.surface_y(0.3, 0.0), wave.base_y_at(0.3)), "height 0 on the face is the base line")
	_check(is_equal_approx(wave.surface_y(0.3, 1.0), wave.base_y_at(0.3) - wave.crest_height_at(0.3)), "height 1 on the face is the crest")
	_check(wave.face_angle(1.0) > wave.face_angle(0.0), "the face steepens toward the crest")

	wave.size = 1.0
	wave.hollowness = 1.0
	_check(wave.barrel() > 0.9, "a big hollow wave is a full barrel")
	_check(wave.zone_at(2.0) == WaveModel.Zone.SHOULDER, "far ahead of the break is the shoulder")
	_check(wave.zone_at(0.2) == WaveModel.Zone.POCKET, "just ahead of the break is the pocket")
	_check(wave.zone_at(-0.4) == WaveModel.Zone.BARREL, "just behind the break of a hollow wave is the barrel")
	_check(wave.zone_at(-1.5) == WaveModel.Zone.WHITEWATER, "far behind the break is whitewater")
	wave.hollowness = 0.0
	_check(is_zero_approx(wave.barrel()) and wave.zone_at(-0.4) == WaveModel.Zone.WHITEWATER, "a spilling wave has no barrel")
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
	for index in [0, 90, 256, 380, WaveModel.PROFILE_WIDTH - 1]:
		var d := WaveModel.sample_distance(index)
		var pixel := profile.get_pixel(index, 0)
		matches = matches and absf(pixel.r - wave.crest_height_at(d)) < 0.002 and absf(pixel.g - wave.base_y_at(d)) < 0.002
		matches = matches and absf(pixel.b - wave.throw_at(d)) < 0.002 and absf(pixel.a - wave.foam_at(d)) < 0.002
	_check(matches, "the baked profile matches the model at sample points")

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


func _test_scale_marker() -> void:
	var wave := WaveModel.new()
	var marker := ScaleMarker.new()
	marker.place(wave, 0.8, 0.3, 0.5, 720.0, 0.2)
	_check(is_equal_approx(marker.position.y, wave.surface_y(0.3, 0.5) * 720.0), "the stand-in surfer's feet are on the model's surface")
	_check(is_equal_approx(marker.position.x, (0.8 - 0.2) * 720.0), "the stand-in surfer shifts with the screen crop")
	_check(is_equal_approx(marker.scale.y * ScaleMarker.TOTAL_HEIGHT, WaveModel.SURFER_HEIGHT * 720.0), "the stand-in surfer is the standard surfer height")
	wave.size = 1.0
	marker.place(wave, 0.8, 0.3, 0.5, 720.0, 0.2)
	_check(is_equal_approx(marker.position.y, wave.surface_y(0.3, 0.5) * 720.0), "the surfer follows the surface when the wave grows")
	marker.free()


## Runs the whole scene for a few frames with a big hollow wave and checks the pieces agree.
func _test_world() -> void:
	var world: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await process_frame
	world.set_wave(0.9, 1.0, 0.3)
	await process_frame
	await process_frame
	var wave: WaveLayer = world.get_node("Wave")
	var material := wave.material as ShaderMaterial
	_check(material.get_shader_parameter("profile") is ImageTexture, "the wave shader has its profile texture")
	_check(material.get_shader_parameter("noise_cells") is ImageTexture and material.get_shader_parameter("noise_warp") is ImageTexture, "the wave shader has its noise textures")
	_check(wave.model.barrel() > 0.5 and is_equal_approx(material.get_shader_parameter("barrel"), wave.model.barrel()), "a big hollow wave tells the shader it is a barrel")
	_check(is_equal_approx(material.get_shader_parameter("peel_x"), wave.peel_x), "the shader knows where the peel point is")
	var marker: ScaleMarker = world.get_node("ScaleMarker")
	var expected_y := wave.model.surface_y(world.peel_offset, world.SURFER_FACE_HEIGHT) * world.size.y
	_check(absf(marker.position.y - expected_y) < 0.01, "the stand-in surfer stands on the face in the running scene")
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
