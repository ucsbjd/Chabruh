extends Control
## Composes the look: owns the shared layout (horizon, sun), advances time and travel, and feeds
## the current mood to every layer. Layers are the child nodes, drawn back to front.

## How fast the scenery slides, in screen heights per second. The surfer travels right to left,
## so the world slides left to right.
const TRAVEL_SPEED := 0.16
const HORIZON := 0.40
const SUN_X_FRACTION := 0.36
const SUN_Y := 0.30
## The scene is composed for at least this width (in screen heights). On a narrower screen,
## such as a phone held upright, the middle of the composition is shown and the sides are cropped.
const MIN_LAYOUT_ASPECT := 1.5

var _time := 0.0
var _travel := 0.0
var _crop := 0.0   # screen heights hidden on each side when the screen is narrower than the layout

var _ridges: Array[RidgeLayer] = []
## Each shader material with the mood properties it declares as uniforms.
var _mood_uniforms: Array[Dictionary] = []
var _materials: Array[ShaderMaterial] = []


func _ready() -> void:
	for child in get_children():
		if child is RidgeLayer:
			child.build(HORIZON)
			_ridges.append(child)
		elif child is CanvasItem and child.material is ShaderMaterial:
			_register(child.material)
	resized.connect(_on_resized)
	Palette.changed.connect(_apply_mood)
	_on_resized()
	_apply_mood()


func _process(delta: float) -> void:
	_time += delta
	_travel += TRAVEL_SPEED * delta
	for material in _materials:
		material.set_shader_parameter("time", _time)
		material.set_shader_parameter("travel", _travel)
	for ridge in _ridges:
		ridge.place(_travel, size.y, _crop)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_M:
			Palette.cycle()
	# Touches arrive as emulated mouse clicks, so this one branch covers phone and desktop.
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Palette.cycle()


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
