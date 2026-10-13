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
const DEFAULT_POSE := "placeholder"
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
var _tuning: TuningData = preload("res://data/tuning.tres")
var _calibration: Calibration
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


func _ready() -> void:
	for child in get_children():
		if child is RidgeLayer:
			child.build(HORIZON)
			_ridges.append(child)
		elif child is CanvasItem and child.material is ShaderMaterial:
			_register(child.material)
	for material in _stage.materials():
		_register(material)
	_register(_surfer.toon_material)
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
	rider.step(delta, _ride_input.steer, _ride_input.height, _stage.model, _tuning)
	var strength := rider.take_burst()
	if strength > 0.0:
		burst(strength)
	_spray.set_wake(lerpf(0.2, 1.0, rider.speed))
	_travel += TRAVEL_SPEED * lerpf(TRAVEL_SPEED_SLOW, TRAVEL_SPEED_FAST, rider.speed) * delta
	for material in _materials:
		material.set_shader_parameter("time", _time)
		material.set_shader_parameter("travel", _travel)
	for ridge in _ridges:
		ridge.place(_travel, size.y, _crop)
	_place_surfer_and_spray()
	_wave_spray.update(_stage, _time)
	if _auto_burst:
		_auto_burst_in -= delta
		if _auto_burst_in <= 0.0:
			_auto_burst_in = AUTO_BURST_EVERY
			_throw_test_burst()


func _unhandled_input(event: InputEvent) -> void:
	_ride_input.handle(event, size)
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_M:
			Palette.cycle()
		elif event.pressed and not event.echo and event.keycode == KEY_R:
			set_wave(DEFAULT_SIZE, DEFAULT_HOLLOW, DEFAULT_PEEL_OFFSET)
			_ride_input.reset()
		elif event.pressed and not event.echo and event.keycode == KEY_P:
			set_surfer_pose(SurferSprites.ORDER[(_pose_index + 1) % SurferSprites.ORDER.size()])
		elif event.pressed and not event.echo and event.keycode == KEY_B:
			_throw_test_burst()
	# A double click or double tap changes the mood (touches arrive as emulated mouse clicks).
	elif event is InputEventMouseButton:
		if event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
			Palette.cycle()


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


## Throws spray off the board's tail, strength 0 (a flick) to 1 (the full fan). The rider calls this from the riding.
func burst(strength: float) -> void:
	_spray.burst(strength)


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
	# Tilt the surfer with the face: the slope of the wave under their feet, ahead of them to the left.
	var ahead_px := _stage.project(model.surface_point(rider.d + 0.6, rider.u))
	var behind_px := _stage.project(model.surface_point(rider.d - 0.6, rider.u))
	var slope := rad_to_deg(atan2(behind_px.y - ahead_px.y, behind_px.x - ahead_px.x))
	_surfer.set_ground_angle(clampf(slope, -MAX_GROUND_ANGLE, MAX_GROUND_ANGLE))

	var pixels_per_meter := (feet_px.y - head_px.y) / WaveModel.SURFER_HEIGHT
	_spray.follow(feet_px + (BOARD_TAIL * pixels_per_meter).rotated(_surfer.rotation), pixels_per_meter, TRAVEL_SPEED * size.y * WAKE_DRIFT_FACTOR)


## Temporary: - and = change the wave's size, [ and ] its hollowness. (The arrow keys and WASD ride.)
func _read_held_keys(delta: float) -> void:
	var size_change := (float(Input.is_key_pressed(KEY_EQUAL)) - float(Input.is_key_pressed(KEY_MINUS))) * SIZE_RATE * delta
	var hollow_change := (float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))) * HOLLOW_RATE * delta
	if size_change != 0.0 or hollow_change != 0.0:
		var keep_camera := _first_frame
		set_wave(_stage.model.size + size_change, _stage.model.hollowness + hollow_change, rider.d)
		_first_frame = keep_camera


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
	_wave_spray.apply_mood(mood)


## A number from the page URL (for example ?size=0.8), or `fallback` when it is missing.
func _url_number(key: String, fallback: float) -> float:
	var text := UrlParams.get_value(key)
	return text.to_float() if text.is_valid_float() else fallback
