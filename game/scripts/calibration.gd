class_name Calibration
extends Control
## A dev-only run (start the game with --calibrate, or add ?calibrate to the page) that asks for each move
## in turn, five times, and records exactly what the hands did: every raw input event with its time, and the
## surfer's path that resulted. The result is a JSON file that tools/analyze_calibration.py averages, and the
## averages set the input dials in data/tuning.tres. This is a tool for tuning, not part of the game, so it
## is the one place that shows text.

const MOVES: Array[Dictionary] = [
	{"id": "up_down", "title": "Up and down the wave", "how": "Slide up to the top of the wave, then back down to the bottom. Start by going UP. Do two or three round trips."},
	{"id": "bottom_to_top", "title": "Bottom turn into a top turn", "how": "Drop low, drive up the face to the top, then snap it back down."},
	{"id": "cutback", "title": "Cutback", "how": "Run ahead along the wave, then swing back toward the curl, and out again."},
	{"id": "hit_lip", "title": "Hit the lip", "how": "Drive up hard to the very top of the wave and snap it."},
	{"id": "floater", "title": "Floater", "how": "Glide along the very top edge of the wave, steady."},
	{"id": "trim", "title": "Trim", "how": "Hold a steady line across the middle of the face. Barely move."},
]
const TRIALS_PER_MOVE := 5
const TRIAL_LIMIT_SECONDS := 15.0
const TRACE_EVERY := 1.0 / 30.0
const SAVE_DIRECTORY := "calibration"

enum Phase { WAITING, RECORDING, DONE }

var _input: RideInput
var _rider: Rider
var _phase := Phase.WAITING
var _move_index := 0
var _trial := 0
var _trial_time := 0.0
var _next_trace := 0.0
var _events: Array = []
var _trace: Array = []
var _results: Array = []
var _session := Time.get_datetime_string_from_system().replace(":", "-")
var _label := Label.new()
var _status := Label.new()


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for label: Label in [_label, _status]:
		label.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.2, 0.9))
		label.add_theme_constant_override("outline_size", 8)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	_label.add_theme_font_size_override("font_size", 26)
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.offset_left = 40.0
	_label.offset_right = -40.0
	_label.offset_top = 36.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_left = 40.0
	_status.offset_right = -40.0
	_status.offset_top = -150.0
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Connects to the input and the rider it will record.
func start(input: RideInput, rider: Rider) -> void:
	_input = input
	_rider = rider
	_input.raw_event.connect(_on_raw_event)
	_show_prompt()


func _process(delta: float) -> void:
	if _phase != Phase.RECORDING:
		return
	_trial_time += delta
	if _trial_time >= _next_trace:
		_next_trace += TRACE_EVERY
		_trace.append([_r(_trial_time), _r(_rider.d), _r(_rider.u), _r(_rider.speed), _r(_rider.sharpness)])
	if _trial_time > TRIAL_LIMIT_SECONDS:
		_finish_trial()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_SPACE:
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		match _phase:
			Phase.WAITING:
				_begin_trial()
			Phase.RECORDING:
				_finish_trial()
	elif event.keycode == KEY_ESCAPE:
		_save(true)
		get_tree().quit()


func _begin_trial() -> void:
	_input.reset()
	_rider.place(Rider.d_for(RideInput.REST_STEER), Rider.u_for(RideInput.REST_HEIGHT))
	_events.clear()
	_trace.clear()
	_trial_time = 0.0
	_next_trace = 0.0
	_phase = Phase.RECORDING
	_label.text = "%s\n\nRECORDING %d of %d. Press SPACE when you are done." % [MOVES[_move_index].title, _trial + 1, TRIALS_PER_MOVE]


func _finish_trial() -> void:
	_results.append({
		"move": MOVES[_move_index].id,
		"trial": _trial + 1,
		"duration": _r(_trial_time),
		"events": _events.duplicate(),
		"trace": _trace.duplicate(),
	})
	_trial += 1
	if _trial >= TRIALS_PER_MOVE:
		_trial = 0
		_move_index += 1
	_save()
	if _move_index >= MOVES.size():
		_phase = Phase.DONE
		_save(true)
		_label.text = "All done. Thank you!\nSaved to %s" % _save_path()
		_status.text = "Press ESCAPE to close."
	else:
		_phase = Phase.WAITING
		_show_prompt()


func _show_prompt() -> void:
	var move := MOVES[_move_index]
	_label.text = "Move %d of %d: %s\n%s\n\nTrial %d of %d. Press SPACE to start, do the move with two fingers, then SPACE again." % [
		_move_index + 1, MOVES.size(), move.title, move.how, _trial + 1, TRIALS_PER_MOVE]
	_status.text = "Two-finger scroll on the trackpad, or the mouse wheel, moves the surfer up and down the wave. Mouse left and right steers. ESCAPE saves and quits."


func _on_raw_event(kind: String, amount: Vector2, where: Vector2) -> void:
	if _phase == Phase.RECORDING:
		_events.append([_r(_trial_time), kind, _r(amount.x), _r(amount.y), _r(where.x), _r(where.y)])


func _save_path() -> String:
	# Next to the project when run from source, in the user folder otherwise.
	var folder := ProjectSettings.globalize_path("res://").path_join("..").path_join(SAVE_DIRECTORY).simplify_path()
	if OS.has_feature("template"):
		folder = OS.get_user_data_dir().path_join(SAVE_DIRECTORY)
	return folder.path_join("session-%s.json" % _session)


func _save(final := false) -> void:
	var path := _save_path()
	var payload := JSON.stringify({"created": _session, "tuning": _tuning_snapshot(), "trials": _results})
	if OS.has_feature("web"):
		# A browser cannot write a file, so offer one download when the run ends, not after every trial.
		if final:
			JavaScriptBridge.download_buffer(payload.to_utf8_buffer(), "calibration-%s.json" % _session, "application/json")
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(payload)
		file.close()


func _tuning_snapshot() -> Dictionary:
	var snapshot := {}
	for info in _input.tuning.get_property_list():
		if info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			snapshot[info.name] = _input.tuning.get(info.name)
	return snapshot


static func _r(value: float) -> float:
	return snappedf(value, 0.001)
