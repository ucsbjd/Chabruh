extends SceneTree
## Headless smoke test. Run from the repo root:
##   godot_console --headless --path game --script res://tests/run_tests.gd
## Exits with the number of failed checks, so any failure is a non-zero exit code.

var _failures := 0


func _initialize() -> void:
	_test_main_scene()
	_test_palette()
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


func _test_palette() -> void:
	_check(root.has_node("Palette"), "Palette autoload exists")
	_check(Palette.SKY_STOPS.size() >= 2, "sky has at least two colour stops")


func _test_tuning() -> void:
	var tuning := load("res://data/tuning.tres") as TuningData
	_check(tuning != null, "tuning resource loads as TuningData")
	if tuning != null:
		_check(tuning.reach > 0.0, "tuning reach is positive")


func _check(condition: bool, name: String) -> void:
	if not condition:
		_failures += 1
	print("%s  %s" % ["ok  " if condition else "FAIL", name])
