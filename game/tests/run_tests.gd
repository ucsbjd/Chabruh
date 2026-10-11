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
	_test_tuning()
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


func _test_tuning() -> void:
	var tuning := load("res://data/tuning.tres") as TuningData
	_check(tuning != null, "tuning resource loads as TuningData")
	if tuning != null:
		_check(tuning.reach > 0.0, "tuning reach is positive")


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
	print("%s  %s" % ["ok  " if condition else "FAIL", name])
