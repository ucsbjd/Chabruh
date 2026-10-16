extends Control
## Composes the look: owns the shared layout (horizon, sun), advances time and travel, frames the
## 3D wave with the camera, stands the stand-in surfer on its surface, and feeds the current mood
## to every layer. Layers are the child nodes, drawn back to front.

## How fast the 2D scenery slides, in screen heights per second. The surfer travels right to left,
## so the world slides left to right.
const TRAVEL_SPEED := 0.16
const HORIZON := 0.40
const SUN_X_FRACTION := 0.40
const SUN_Y := 0.20
## The 2D backdrop is composed for at least this width (in screen heights). On a narrower screen
## the middle of it is shown and the sides are cropped. (The 3D wave crops through its camera.)
const MIN_LAYOUT_ASPECT := 1.5

## How quickly the camera follows the surfer, per second. A little lag is what lets you see them climb the face.
const CAMERA_FOLLOW_RATE := 3.5
## The water, and with it the scenery, slides past this much faster or slower with the surfer's speed.
const TRAVEL_SPEED_SLOW := 0.55
const TRAVEL_SPEED_FAST := 1.45
## The camera always looks down the line, left from behind the surfer, so the wave coming toward them
## fills the screen and the break stays at their back. It eases a little less far round as a barrel forms.
## Degrees, and the surfer's place across the screen.
const CAMERA_YAW_OPEN := 30.0
const CAMERA_YAW_BARREL := 24.0
const SURFER_SCREEN_X_OPEN := 0.47
const SURFER_SCREEN_X_BARREL := 0.50
const CAMERA_SWING_RATE := 2.5
## Temporary controls for trying waves: how fast the held keys change things, per second.
const SIZE_RATE := 0.4
const HOLLOW_RATE := 0.4
const DEFAULT_SIZE := 0.6
const DEFAULT_HOLLOW := 0.5
const DEFAULT_PEEL_OFFSET := 3.0
const DEFAULT_POSE := "surfer"
## The surfer sits on the face at an angle that follows the wave, but never tips past this, in degrees.
const MAX_GROUND_ANGLE := 14.0
## Where the board's tail is, in meters from the board's centre (right and down, before the board tilts):
## the spray is thrown from here.
const BOARD_TAIL := Vector2(0.8, 0.05)
## The water slides past the surfer this much faster than the far scenery, which is what carries the wake.
const WAKE_DRIFT_FACTOR := 1.7
## The temporary B key throws a burst of the next strength in this list, so they can be judged one by one.
const TEST_BURSTS: Array[float] = [0.15, 0.4, 0.7, 1.0]
## With ?autoburst in the URL (for a phone, which has no S key) a test burst is thrown this often, in seconds.
const AUTO_BURST_EVERY := 2.4
## The , and . keys slow everything down or speed it up (the ride, the wave, the spray), in these steps and limits.
const GAME_SPEED_STEP := 0.1
const GAME_SPEED_MIN := 0.5
const GAME_SPEED_MAX := 2.5
## At the top of the wave (above this height up the face) a turn also throws a fan off the front of the board, where
## the front foot drives the rail through the lip, this strong relative to the tail's.
const FRONT_SPRAY_FROM := 0.6
const FRONT_SPRAY_SHARE := 1.1
## The spray leaves the tail the way the rider throws it (off the outside of the turn, up over the crest at the lip): the
## direction is projected this many meters out to find its angle on screen, which stays between these angles (degrees,
## 0 is right, negative is up), so it never fires down into the face.
const SPRAY_PROBE := 1.5
const SPRAY_ANGLE_UP := -165.0
const SPRAY_ANGLE_DOWN := 20.0
## The hotkeys that play a move (MovePlayer), and how hollow the wave is made for the tube if it cannot barrel yet.
const MOVE_KEYS := {KEY_L: "lip_hit", KEY_C: "cutback", KEY_F: "floater", KEY_T: "tube", KEY_P: "pump"}
const TUBE_HOLLOW := 0.9
const TAKE_OVER_MOTION := 3.0       # pixels the mouse must move to take the controls back from a move being played

var _time := 0.0
var _travel := 0.0
var _crop := 0.0   # screen heights hidden on each side when the screen is narrower than the layout
## The surfer's motion on the wave, driven by the input.
var rider := Rider.new()
## How far ahead of the peel point the surfer is, in meters. Positive is ahead (to the left),
## negative is behind it, where the lip throws and the barrel is.
var peel_offset: float:
	get:
		return rider.d
var _swing := 0.0   # 0 on an open wave, 1 on a full barrel
var _first_frame := true
var _focus := Vector3.ZERO
var _ride_input := RideInput.new()
var _moves := MovePlayer.new()      # plays a move through the controls when its hotkey is pressed
var _tuning: TuningData = preload("res://data/tuning.tres")
var _calibration: Calibration
var _key_help := Label.new()
var _surfer3d: Surfer3D
var _readout := Label.new()
var _speed_label := Label.new()  # the game speed, always on screen so it shows in screenshots
var _front_spray := SurferSpray.new()
var _pose_index := SurferSprites.ORDER.find(DEFAULT_POSE)
var _test_burst := 0
var _auto_burst_in := AUTO_BURST_EVERY
var _auto_burst := false

var _ridges: Array[RidgeLayer] = []
## Each shader material with the mood properties it declares as uniforms.
var _mood_uniforms: Array[Dictionary] = []
var _materials: Array[ShaderMaterial] = []

@onready var _stage: WaveStage = $WaveStage
@onready var _surfer: Surfer = $Surfer
@onready var _spray: SurferSpray = $Spray
@onready var _wave_spray: WaveSpray = $WaveSpray
@onready var _panel: DebugPanel = $DebugPanel


func _init() -> void:
	# Attached now, not in _ready, so a scene that is never started cannot orphan it.
	add_child(_ride_input)


func _notification(what: int) -> void:
	# The labels and the second fan are attached in _ready; a scene freed before that must free them itself.
	if what == NOTIFICATION_PREDELETE:
		for orphan: Node in [_key_help, _readout, _speed_label, _front_spray]:
			if is_instance_valid(orphan) and orphan.get_parent() == null:
				orphan.free()


func _ready() -> void:
	_add_key_help()
	# The second fan, off the front foot, sits with the tail's fan in front of the surfer.
	add_child(_front_spray)
	move_child(_front_spray, _spray.get_index() + 1)
	_front_spray.set_wake(0.0)
	var url_speed := UrlParams.get_value("speed")
	if url_speed.is_valid_float():
		Engine.time_scale = clampf(url_speed.to_float(), GAME_SPEED_MIN, GAME_SPEED_MAX)
	_show_game_speed()
	_set_surfer_3d(not UrlParams.has("sprite"))  # the real-time surfer is the default; ?sprite or the 3 key brings the sprite back
	for child in get_children():
		if child is RidgeLayer:
			child.build(HORIZON)
			_ridges.append(child)
		elif child is CanvasItem and child.material is ShaderMaterial:
			_register(child.material)
	for material in _stage.materials():
		_register(material)
	_register(_surfer.toon_material)
	_stage.carve_trail.draw_speed = _tuning.v_draw_base
	_auto_burst = UrlParams.has("autoburst")
	if UrlParams.has("calibrate"):
		_calibration = Calibration.new()
		add_child(_calibration)
		_calibration.start(_ride_input, rider)
	_panel.values_changed.connect(_on_panel_changed)
	resized.connect(_on_resized)
	Palette.changed.connect(_apply_mood)
	_on_resized()
	_apply_mood()
	set_wave(_url_number("size", DEFAULT_SIZE), _url_number("hollow", DEFAULT_HOLLOW), _url_number("peel", DEFAULT_PEEL_OFFSET))
	var requested_pose := UrlParams.get_value("pose")
	set_surfer_pose(requested_pose if SurferSprites.has_animation(requested_pose) else DEFAULT_POSE)


func _process(delta: float) -> void:
	_time += delta
	_ride_input.process(delta)
	_read_held_keys(delta)
	_moves.update(delta, rider, _ride_input)
	_show_game_speed()
	rider.step(delta, _ride_input.steer, _ride_input.take_height_push(), _stage.model, _tuning)
	if _readout.visible:
		_readout.text = "%s   speed %.1f m/s   heading %d deg   turn %.1f   crouch %.2f   lean %d deg   load %.1f g   stall %.1f
charge %.1f   release %.1f   float %.1f   spray %.2f   %s" % [
			rider.move, rider.v, roundi(rad_to_deg(rider.theta)), rider.omega, rider.compression, roundi(rad_to_deg(rider.carve)), rider.load_g,
			rider.stall, rider.charge, rider.release, rider.afloat, rider.spray_power, _balance_note()]
		_readout.modulate = Color(1.0, 0.55, 0.5, 0.9) if rider.strain > 1.0 else Color(1, 1, 1, 0.6)
	var strength := rider.take_burst()
	if strength > 0.0:
		burst(strength, rider.burst_release)
	_spray.set_wake(lerpf(0.2, 1.0, rider.speed))
	_travel += TRAVEL_SPEED * lerpf(TRAVEL_SPEED_SLOW, TRAVEL_SPEED_FAST, rider.speed) * delta
	for material in _materials:
		material.set_shader_parameter("time", _time)
		material.set_shader_parameter("travel", _travel)
	for ridge in _ridges:
		ridge.place(_travel, size.y, _crop)
	_place_surfer_and_spray()
	_wave_spray.update(_stage, _time)
	_stage.carve_trail.carve(delta, rider.d, rider.u, rider.theta, rider.spray_power, _time)
	if _auto_burst:
		_auto_burst_in -= delta
		if _auto_burst_in <= 0.0:
			_auto_burst_in = AUTO_BURST_EVERY
			_throw_test_burst()


func _unhandled_input(event: InputEvent) -> void:
	_ride_input.handle(event, size)
	if _moves.playing() and _takes_over(event):
		_moves.stop()
	if event is InputEventKey and event.pressed and not event.echo and MOVE_KEYS.has(event.keycode):
		play_move(MOVE_KEYS[event.keycode])
	elif event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_M:
			Palette.cycle()
		elif event.pressed and not event.echo and event.keycode == KEY_R:
			set_wave(DEFAULT_SIZE, DEFAULT_HOLLOW, DEFAULT_PEEL_OFFSET)
			_ride_input.reset()
		elif event.pressed and not event.echo and event.keycode == KEY_O:
			set_surfer_pose(SurferSprites.ORDER[(_pose_index + 1) % SurferSprites.ORDER.size()])
		elif event.pressed and not event.echo and event.keycode == KEY_B:
			_throw_test_burst()
		elif event.pressed and not event.echo and event.keycode == KEY_1:
			if _surfer3d:
				_surfer3d.set_target("bottom_turn", 1.0 - _surfer3d.target("bottom_turn"))
			else:
				_surfer.play_once("bottom_turn")
		elif event.pressed and not event.echo and event.keycode == KEY_2 and _surfer3d:
			_surfer3d.set_target("crouch", 1.0 - _surfer3d.target("crouch"))
		elif event.pressed and not event.echo and event.keycode == KEY_3:
			_set_surfer_3d(_surfer3d == null)
		elif event.pressed and not event.echo and event.keycode == KEY_H:
			_key_help.visible = not _key_help.visible
			_readout.visible = _key_help.visible
		elif event.pressed and (event.keycode == KEY_COMMA or event.keycode == KEY_PERIOD):
			var step := GAME_SPEED_STEP if event.keycode == KEY_PERIOD else -GAME_SPEED_STEP
			Engine.time_scale = clampf(snappedf(Engine.time_scale + step, GAME_SPEED_STEP), GAME_SPEED_MIN, GAME_SPEED_MAX)
			_show_game_speed()
	# A double click or double tap changes the mood (touches arrive as emulated mouse clicks).
	elif event is InputEventMouseButton:
		if event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			Palette.cycle()


## Plays a move through the controls (MovePlayer.MOVES): the hotkeys L, C, F, T and P. The tube needs a wave that
## barrels, so if this one cannot it is made hollower first.
func play_move(move_name: String) -> void:
	if move_name == "tube" and _stage.model.barrel() < WaveModel.BARREL_THRESHOLD + 0.1:
		_stage.model.hollowness = maxf(_stage.model.hollowness, TUBE_HOLLOW)
		_stage.rebuild()
		_panel.show_values(_stage.model.size, _stage.model.hollowness, peel_offset)
	_moves.play(move_name)
	_show_game_speed()


## Whether an input event is the player taking the controls back from a move being played.
func _takes_over(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		return event.relative.length() > TAKE_OVER_MOTION
	if event is InputEventKey:
		return event.pressed and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_A, KEY_S, KEY_D]
	return event is InputEventMouseButton or event is InputEventPanGesture or event is InputEventScreenDrag or event is InputEventScreenTouch


## Debug: whether the input is one a real surfer could ride. He never falls here, but the readout says when he would.
func _balance_note() -> String:
	var note := "balance ok" if rider.strain <= 1.0 else "a real surfer would fall: " + rider.strain_reason
	return "%s   (strain %.1f, %d times so far)" % [note, rider.strain, rider.falls]


## Sets the wave's size and hollowness (both 0 to 1) and how far ahead of the peel point, in
## meters, the surfer is.
func set_wave(wave_size: float, hollowness: float, ahead_of_peel: float) -> void:
	_stage.model.size = wave_size
	_stage.model.hollowness = hollowness
	_place_rider(clampf(ahead_of_peel, DebugPanel.PEEL_MIN, DebugPanel.PEEL_MAX))
	_stage.rebuild()
	_first_frame = true
	_panel.show_values(wave_size, hollowness, peel_offset)


## Puts the surfer at a place along the wave (and mid face) and points the input at it, so they stay there.
func _place_rider(meters_ahead: float) -> void:
	_ride_input.steer = Rider.steer_for(meters_ahead)
	_ride_input.height = RideInput.REST_HEIGHT
	rider.place(meters_ahead, Rider.u_for(RideInput.REST_HEIGHT))
	_stage.carve_trail.clear()


## Throws spray off the board's tail, strength 0 (a flick) to 1 (the full fan). The rider calls this from the riding;
## `giant` (0 to 1) is how much of it is the speed he sheds stopping at the top, which throws the giant fan.
func burst(strength: float, giant := 0.0) -> void:
	var tail := _surfer3d.tail_point() if _surfer3d else Vector3.ZERO
	_spray.burst(strength, _spray_angle(tail), giant)
	# At the top of the wave the front foot drives the rail through the lip and throws its own, bigger fan.
	var top := smoothstep(FRONT_SPRAY_FROM, 0.85, rider.u)
	if top > 0.05:
		var front := _surfer3d.front_foot_point() if _surfer3d else Vector3.ZERO
		_front_spray.burst(clampf(strength * FRONT_SPRAY_SHARE * top, 0.0, 1.0), _spray_angle(front), giant)


## Which way on screen the spray leaves a point on the board (degrees, 0 right, negative up), from the way the rider
## throws it. The sprite surfer has no board in the 3D stage, so its spray keeps the fan's usual angle.
func _spray_angle(from: Vector3) -> float:
	if _surfer3d == null:
		return SurferSpray.FAN_CENTRE
	var a := _stage.project(from)
	var b := _stage.project(from + rider.spray_dir * SPRAY_PROBE)
	if a.distance_to(b) < 1.0:
		return SurferSpray.FAN_CENTRE
	var angle := rad_to_deg((b - a).angle())
	# (pointing down and to the left, the nearest allowed angle is up and to the left, round the other way)
	if angle > SPRAY_ANGLE_DOWN:
		return SPRAY_ANGLE_UP if angle > 90.0 + SPRAY_ANGLE_DOWN * 0.5 else SPRAY_ANGLE_DOWN
	return maxf(angle, SPRAY_ANGLE_UP)


## Shows the game speed in the corner and in the key list.
func _show_game_speed() -> void:
	_speed_label.text = "game speed %.1fx" % Engine.time_scale + ("   playing: " + MovePlayer.LABELS[_moves.move] if _moves.playing() else "")
	_key_help.text = _key_help_text()


## Temporary: the next of the rising test strengths, so each fan can be judged (B key, or ?autoburst on a phone).
func _throw_test_burst() -> void:
	burst(TEST_BURSTS[_test_burst % TEST_BURSTS.size()])
	_test_burst += 1


## Plays one of the surfer's animations from SurferSprites (temporary: step 6 picks them from how they ride).
func set_surfer_pose(pose_name: String) -> void:
	_pose_index = maxi(SurferSprites.ORDER.find(pose_name), 0)
	_surfer.set_pose(pose_name)


## Frames the camera on the surfer and stands the surfer and the spray cloud on the wave.
func _place_surfer_and_spray() -> void:
	var model := _stage.model
	var feet := model.surface_point(rider.d, rider.u)
	_focus = feet if _first_frame else _focus.lerp(feet, 1.0 - exp(-CAMERA_FOLLOW_RATE * get_process_delta_time()))
	var target_swing := model.barrel()
	_swing = target_swing if _first_frame else lerpf(_swing, target_swing, 1.0 - exp(-CAMERA_SWING_RATE * get_process_delta_time()))
	_first_frame = false
	_stage.frame(_focus, lerpf(CAMERA_YAW_OPEN, CAMERA_YAW_BARREL, _swing), lerpf(SURFER_SCREEN_X_OPEN, SURFER_SCREEN_X_BARREL, _swing))
	var feet_px := _stage.project(feet)
	var head_px := _stage.project(feet + Vector3(0.0, WaveModel.SURFER_HEIGHT, 0.0))
	_surfer.place(feet_px, feet_px.y - head_px.y)
	if _surfer3d:
		_surfer3d.follow(rider, model, get_process_delta_time())
		_spray.set_hand_drag(_stage.project(_surfer3d.hand_spray_point), _surfer3d.hand_spray)
		_spray.set_rail(rider.rail_spray, _spray_angle(_surfer3d.tail_point()))
	else:
		_spray.set_hand_drag(Vector2.ZERO, 0.0)
		_spray.set_rail(rider.rail_spray, SurferSpray.FAN_CENTRE)
	# Tilt the surfer with the face: the slope of the wave under their feet, ahead of them to the left.
	var ahead_px := _stage.project(model.surface_point(rider.d + 0.6, rider.u))
	var behind_px := _stage.project(model.surface_point(rider.d - 0.6, rider.u))
	var slope := rad_to_deg(atan2(behind_px.y - ahead_px.y, behind_px.x - ahead_px.x))
	_surfer.set_ground_angle(clampf(slope, -MAX_GROUND_ANGLE, MAX_GROUND_ANGLE))

	var pixels_per_meter := (feet_px.y - head_px.y) / WaveModel.SURFER_HEIGHT
	var drift := TRAVEL_SPEED * size.y * WAKE_DRIFT_FACTOR
	if _surfer3d:  # off the real board: its tail, and the front foot
		_spray.follow(_stage.project(_surfer3d.tail_point()), pixels_per_meter, drift)
		_front_spray.follow(_stage.project(_surfer3d.front_foot_point()), pixels_per_meter, drift)
	else:
		_spray.follow(feet_px + (BOARD_TAIL * pixels_per_meter).rotated(_surfer.rotation), pixels_per_meter, drift)
		_front_spray.follow(feet_px, pixels_per_meter, drift)


## Temporary: - and = change the wave's size, [ and ] its hollowness. (The arrow keys and WASD ride.)
func _read_held_keys(delta: float) -> void:
	var size_change := (float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))) * SIZE_RATE * delta
	var hollow_change := (float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))) * HOLLOW_RATE * delta
	if size_change != 0.0 or hollow_change != 0.0:
		var keep_camera := _first_frame
		set_wave(_stage.model.size + size_change, _stage.model.hollowness + hollow_change, rider.d)
		_first_frame = keep_camera


## A faint key list in the lower left for testing. H hides it.
func _add_key_help() -> void:
	_key_help.text = _key_help_text()
	_key_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key_help.modulate = Color(1, 1, 1, 0.6)
	_key_help.add_theme_font_size_override("font_size", 15)
	_key_help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_key_help.add_theme_constant_override("outline_size", 5)
	_key_help.add_theme_constant_override("line_spacing", -4)
	_key_help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_key_help.position += Vector2(14.0, -225.0)
	add_child(_key_help)
	_readout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readout.modulate = Color(1, 1, 1, 0.6)
	_readout.add_theme_font_size_override("font_size", 15)
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_readout.add_theme_constant_override("outline_size", 5)
	_readout.position = Vector2(14.0, 44.0)
	add_child(_readout)
	_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_label.modulate = Color(1, 1, 1, 0.6)
	_speed_label.add_theme_font_size_override("font_size", 15)
	_speed_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_speed_label.add_theme_constant_override("outline_size", 5)
	# (it grows to the left, so the move being played fits on screen beside the speed)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_speed_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_speed_label.offset_left = -14.0
	_speed_label.offset_right = -14.0
	_speed_label.offset_top = 14.0
	add_child(_speed_label)


func _key_help_text() -> String:
	return "\n".join([
		"1   bottom turn (3D: toggle)", "2   crouch (3D only, toggle)", "3   3D surfer on / off",
		"L  hit the lip   C  cutback (hold down)   F  floater", "T  barrel crouch   P  pump   (any control takes over)",
		"O   next animation", "B   spray burst", "M   mood", "R   reset", "- =   wave size", "[ ]   hollow",
		", .   game speed (%.1fx)" % Engine.time_scale, "H   hide this"])


## Swaps the sprite surfer for the real-time one that lives inside the wave's 3D stage (or back).
func _set_surfer_3d(on: bool) -> void:
	if on and _surfer3d == null:
		_surfer3d = Surfer3D.new()
		_stage.add_actor(_surfer3d)
		_register(_surfer3d.material)
		_register(_surfer3d.veil)
		_apply_mood()
	elif not on and _surfer3d != null:
		_surfer3d.queue_free()
		_surfer3d = null
	_surfer.visible = not on


func _on_panel_changed(wave_size: float, hollowness: float, ahead_of_peel: float) -> void:
	_stage.model.size = wave_size
	_stage.model.hollowness = hollowness
	_place_rider(ahead_of_peel)
	_stage.rebuild()


func _register(material: ShaderMaterial) -> void:
	var declared: Array[String] = []
	for uniform in material.shader.get_shader_uniform_list():
		declared.append(uniform.name)
	var wanted: Array[String] = []
	for property in MoodData.property_names():
		if property in declared:
			wanted.append(property)
	_materials.append(material)
	_mood_uniforms.append({"material": material, "names": wanted})


func _on_resized() -> void:
	var aspect := size.x / size.y
	var layout_aspect := maxf(aspect, MIN_LAYOUT_ASPECT)
	_crop = (layout_aspect - aspect) * 0.5
	var sun_pos := Vector2(layout_aspect * SUN_X_FRACTION, SUN_Y)
	for material in _materials:
		material.set_shader_parameter("aspect", aspect)
		material.set_shader_parameter("layout_aspect", layout_aspect)
		material.set_shader_parameter("horizon", HORIZON)
		material.set_shader_parameter("sun_pos", sun_pos)


func _apply_mood() -> void:
	var mood := Palette.current
	for entry in _mood_uniforms:
		for name: String in entry.names:
			entry.material.set_shader_parameter(name, mood.get(name))
	for ridge in _ridges:
		ridge.apply_mood(mood)
	_spray.apply_mood(mood)
	_front_spray.apply_mood(mood)
	_wave_spray.apply_mood(mood)


## A number from the page URL (for example ?size=0.8), or `fallback` when it is missing.
func _url_number(key: String, fallback: float) -> float:
	var text := UrlParams.get_value(key)
	return text.to_float() if text.is_valid_float() else fallback
