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

## Where the stand-in surfer stands on the wave's face: 0 at the trough, 1 at the top of the face.
const SURFER_FACE_HEIGHT := 0.5
## The camera looks left from behind the surfer, and swings round to look right from ahead of them as
## a barrel forms, so the tube's mouth faces the camera. Degrees, and the surfer's place across the screen.
const CAMERA_YAW_OPEN := 30.0
const CAMERA_YAW_BARREL := -26.0
const SURFER_SCREEN_X_OPEN := 0.44
const SURFER_SCREEN_X_BARREL := 0.54
const CAMERA_SWING_RATE := 2.5
## Temporary controls: how fast the held keys change things, per second.
const SIZE_RATE := 0.4
const HOLLOW_RATE := 0.4
const PEEL_RATE := 8.0
const DEFAULT_SIZE := 0.6
const DEFAULT_HOLLOW := 0.5
const DEFAULT_PEEL_OFFSET := 3.0
const DEFAULT_POSE := "trim"
## The surfer sits on the face at an angle that follows the wave, but never tips past this, in degrees.
const MAX_GROUND_ANGLE := 14.0

var _time := 0.0
var _travel := 0.0
var _crop := 0.0   # screen heights hidden on each side when the screen is narrower than the layout
## How far ahead of the peel point the surfer is, in meters. Positive is ahead (to the left),
## negative is behind it, where the lip throws and the barrel is.
var peel_offset := DEFAULT_PEEL_OFFSET
var _swing := 0.0   # 0 behind the surfer, 1 swung round to the barrel side
var _first_frame := true
var _pose_index := PoseLibrary.ORDER.find(DEFAULT_POSE)

var _ridges: Array[RidgeLayer] = []
## Each shader material with the mood properties it declares as uniforms.
var _mood_uniforms: Array[Dictionary] = []
var _materials: Array[ShaderMaterial] = []

@onready var _stage: WaveStage = $WaveStage
@onready var _surfer: Surfer = $Surfer
@onready var _spray: ColorRect = $Spray
@onready var _panel: DebugPanel = $DebugPanel


func _ready() -> void:
	for child in get_children():
		if child is RidgeLayer:
			child.build(HORIZON)
			_ridges.append(child)
		elif child is CanvasItem and child.material is ShaderMaterial:
			_register(child.material)
	for material in _stage.materials():
		_register(material)
	_panel.values_changed.connect(_on_panel_changed)
	resized.connect(_on_resized)
	Palette.changed.connect(_apply_mood)
	_on_resized()
	_apply_mood()
	set_wave(_url_number("size", DEFAULT_SIZE), _url_number("hollow", DEFAULT_HOLLOW), _url_number("peel", DEFAULT_PEEL_OFFSET))
	var requested_pose := UrlParams.get_value("pose")
	set_surfer_pose(requested_pose if PoseLibrary.has_pose(requested_pose) else DEFAULT_POSE, 0.0)


func _process(delta: float) -> void:
	_time += delta
	_travel += TRAVEL_SPEED * delta
	_read_held_keys(delta)
	for material in _materials:
		material.set_shader_parameter("time", _time)
		material.set_shader_parameter("travel", _travel)
	for ridge in _ridges:
		ridge.place(_travel, size.y, _crop)
	_place_surfer_and_spray()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_M:
			Palette.cycle()
		elif event.pressed and not event.echo and event.keycode == KEY_R:
			set_wave(DEFAULT_SIZE, DEFAULT_HOLLOW, DEFAULT_PEEL_OFFSET)
		elif event.pressed and not event.echo and event.keycode == KEY_P:
			set_surfer_pose(PoseLibrary.ORDER[(_pose_index + 1) % PoseLibrary.ORDER.size()])
	# Touches arrive as emulated mouse clicks, so this one branch covers phone and desktop.
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Palette.cycle()


## Sets the wave's size and hollowness (both 0 to 1) and how far ahead of the peel point, in
## meters, the surfer is.
func set_wave(wave_size: float, hollowness: float, ahead_of_peel: float) -> void:
	_stage.model.size = wave_size
	_stage.model.hollowness = hollowness
	peel_offset = clampf(ahead_of_peel, DebugPanel.PEEL_MIN, DebugPanel.PEEL_MAX)
	_stage.rebuild()
	_panel.show_values(wave_size, hollowness, peel_offset)


## Eases the surfer into a pose from PoseLibrary (temporary: step 5 picks poses from how they ride).
func set_surfer_pose(pose_name: String, seconds := Surfer.BLEND_SECONDS) -> void:
	_pose_index = maxi(PoseLibrary.ORDER.find(pose_name), 0)
	_surfer.set_pose(pose_name, seconds)


## Frames the camera on the surfer and stands the surfer and the spray cloud on the wave.
func _place_surfer_and_spray() -> void:
	var model := _stage.model
	var feet := model.surface_point(peel_offset, SURFER_FACE_HEIGHT)
	var target_swing := model.barrel()
	_swing = target_swing if _first_frame else lerpf(_swing, target_swing, 1.0 - exp(-CAMERA_SWING_RATE * get_process_delta_time()))
	_first_frame = false
	_stage.frame(feet, lerpf(CAMERA_YAW_OPEN, CAMERA_YAW_BARREL, _swing), lerpf(SURFER_SCREEN_X_OPEN, SURFER_SCREEN_X_BARREL, _swing))
	var feet_px := _stage.project(feet)
	var head_px := _stage.project(feet + Vector3(0.0, WaveModel.SURFER_HEIGHT, 0.0))
	_surfer.place(feet_px, feet_px.y - head_px.y)
	# Tilt the surfer with the face: the slope of the wave under their feet, ahead of them to the left.
	var ahead_px := _stage.project(model.surface_point(peel_offset + 0.6, SURFER_FACE_HEIGHT))
	var behind_px := _stage.project(model.surface_point(peel_offset - 0.6, SURFER_FACE_HEIGHT))
	var slope := rad_to_deg(atan2(behind_px.y - ahead_px.y, behind_px.x - ahead_px.x))
	_surfer.set_ground_angle(clampf(slope, -MAX_GROUND_ANGLE, MAX_GROUND_ANGLE))

	var crest_px := _stage.project(model.crest_point(0.0))
	var pixels_per_meter := (feet_px.y - head_px.y) / WaveModel.SURFER_HEIGHT
	var spray_material := _spray.material as ShaderMaterial
	spray_material.set_shader_parameter("centre", Vector2(crest_px.x / size.x * (size.x / size.y), crest_px.y / size.y))
	spray_material.set_shader_parameter("radius", minf(model.height() * 0.7 * pixels_per_meter / size.y, 0.30))


## Up and down change the size, [ and ] the hollowness, left and right slide the surfer along the
## wave (left is ahead of the peel point, right lets the break catch up).
func _read_held_keys(delta: float) -> void:
	var size_change := Input.get_axis("ui_down", "ui_up") * SIZE_RATE * delta
	var hollow_change := (float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))) * HOLLOW_RATE * delta
	var peel_change := Input.get_axis("ui_right", "ui_left") * PEEL_RATE * delta
	if size_change != 0.0 or hollow_change != 0.0 or peel_change != 0.0:
		set_wave(_stage.model.size + size_change, _stage.model.hollowness + hollow_change, peel_offset + peel_change)


func _on_panel_changed(wave_size: float, hollowness: float, ahead_of_peel: float) -> void:
	_stage.model.size = wave_size
	_stage.model.hollowness = hollowness
	peel_offset = ahead_of_peel
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


## A number from the page URL (for example ?size=0.8), or `fallback` when it is missing.
func _url_number(key: String, fallback: float) -> float:
	var text := UrlParams.get_value(key)
	return text.to_float() if text.is_valid_float() else fallback
