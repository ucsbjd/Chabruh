extends Control
## Composes the look: owns the shared layout (horizon, sun, where the surfer stands), advances
## time and travel, and feeds the current mood to every layer. Layers are the child nodes, drawn
## back to front.

## How fast the scenery slides, in screen heights per second. The surfer travels right to left,
## so the world slides left to right.
const TRAVEL_SPEED := 0.16
const HORIZON := 0.40
const SUN_X_FRACTION := 0.40
const SUN_Y := 0.20
## The scene is composed for at least this width (in screen heights). On a narrower screen,
## such as a phone held upright, the middle of the composition is shown and the sides are cropped.
const MIN_LAYOUT_ASPECT := 1.5

## Where the stand-in surfer stands: across the layout, and how far up the wave's face.
const SURFER_X_FRACTION := 0.44
const SURFER_FACE_HEIGHT := 0.5
## Temporary controls: how fast the held keys change things, per second.
const SIZE_RATE := 0.4
const HOLLOW_RATE := 0.4
const PEEL_RATE := 0.6
const DEFAULT_SIZE := 0.6
const DEFAULT_HOLLOW := 0.5
const DEFAULT_PEEL_OFFSET := 0.45

var _time := 0.0
var _travel := 0.0
var _crop := 0.0   # screen heights hidden on each side when the screen is narrower than the layout
var _layout_aspect := MIN_LAYOUT_ASPECT
## How far ahead of the peel point the surfer is. Positive is ahead (to the left), negative is
## behind it, where the lip throws and the barrel is.
var peel_offset := DEFAULT_PEEL_OFFSET

var _ridges: Array[RidgeLayer] = []
## Each shader material with the mood properties it declares as uniforms.
var _mood_uniforms: Array[Dictionary] = []
var _materials: Array[ShaderMaterial] = []

@onready var _wave: WaveLayer = $Wave
@onready var _surfer: ScaleMarker = $ScaleMarker
@onready var _panel: DebugPanel = $DebugPanel


func _ready() -> void:
	for child in get_children():
		if child is RidgeLayer:
			child.build(HORIZON)
			_ridges.append(child)
		elif child is CanvasItem and child.material is ShaderMaterial:
			_register(child.material)
	_panel.values_changed.connect(_on_panel_changed)
	resized.connect(_on_resized)
	Palette.changed.connect(_apply_mood)
	_on_resized()
	_apply_mood()
	set_wave(_url_number("size", DEFAULT_SIZE), _url_number("hollow", DEFAULT_HOLLOW), _url_number("peel", DEFAULT_PEEL_OFFSET))


func _process(delta: float) -> void:
	_time += delta
	_travel += TRAVEL_SPEED * delta
	_read_held_keys(delta)
	for material in _materials:
		material.set_shader_parameter("time", _time)
		material.set_shader_parameter("travel", _travel)
	for ridge in _ridges:
		ridge.place(_travel, size.y, _crop)
	var surfer_x := _layout_aspect * SURFER_X_FRACTION
	_wave.peel_x = surfer_x + peel_offset
	_surfer.place(_wave.model, surfer_x, peel_offset, SURFER_FACE_HEIGHT, size.y, _crop)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_M:
			Palette.cycle()
		elif event.pressed and not event.echo and event.keycode == KEY_R:
			_wave.model.size = DEFAULT_SIZE
			_wave.model.hollowness = DEFAULT_HOLLOW
			peel_offset = DEFAULT_PEEL_OFFSET
			_apply_wave()
	# Touches arrive as emulated mouse clicks, so this one branch covers phone and desktop.
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Palette.cycle()


## Up and down change the size, [ and ] the hollowness, left and right slide the surfer along the
## wave (left is ahead of the peel point, right lets the break catch up).
func _read_held_keys(delta: float) -> void:
	var size_change := Input.get_axis("ui_down", "ui_up") * SIZE_RATE * delta
	var hollow_change := (float(Input.is_key_pressed(KEY_BRACKETRIGHT)) - float(Input.is_key_pressed(KEY_BRACKETLEFT))) * HOLLOW_RATE * delta
	var peel_change := Input.get_axis("ui_right", "ui_left") * PEEL_RATE * delta
	if size_change != 0.0 or hollow_change != 0.0 or peel_change != 0.0:
		_wave.model.size += size_change
		_wave.model.hollowness += hollow_change
		peel_offset = clampf(peel_offset + peel_change, DebugPanel.PEEL_MIN, DebugPanel.PEEL_MAX)
		_apply_wave()


## Sets the wave's size and hollowness (both 0 to 1) and how far ahead of the peel point the surfer is.
func set_wave(wave_size: float, hollowness: float, ahead_of_peel: float) -> void:
	_wave.model.size = wave_size
	_wave.model.hollowness = hollowness
	peel_offset = clampf(ahead_of_peel, DebugPanel.PEEL_MIN, DebugPanel.PEEL_MAX)
	_apply_wave()


func _on_panel_changed(wave_size: float, hollowness: float, ahead_of_peel: float) -> void:
	_wave.model.size = wave_size
	_wave.model.hollowness = hollowness
	peel_offset = ahead_of_peel
	_wave.rebake()


func _apply_wave() -> void:
	_wave.rebake()
	_panel.show_values(_wave.model.size, _wave.model.hollowness, peel_offset)


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
	_layout_aspect = maxf(aspect, MIN_LAYOUT_ASPECT)
	_crop = (_layout_aspect - aspect) * 0.5
	var sun_pos := Vector2(_layout_aspect * SUN_X_FRACTION, SUN_Y)
	for material in _materials:
		material.set_shader_parameter("aspect", aspect)
		material.set_shader_parameter("layout_aspect", _layout_aspect)
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
