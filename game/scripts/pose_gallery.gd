class_name PoseGallery
extends Control
## A pose gallery for judging the surfer, shown with ?gallery in the URL: every pose in a labelled grid,
## plus a big cycler that eases from pose to pose (tap, click, or left and right keys; space pauses).
## It covers the scene with the wave's own colours behind it, so the surfer is judged against them.

const COLUMNS := 4
const ROWS := 3
## How long the cycler holds a pose before moving on, seconds.
const HOLD_SECONDS := 1.6
## The grid takes the left part of the screen and the cycler the right, as fractions of the width.
const GRID_WIDTH := 0.64
const CELL_SURFER_HEIGHT := 0.56      # of the cell's height
const CYCLER_SURFER_HEIGHT := 0.44    # of the screen's height

var _background: ColorRect
var _cells: Array[ColorRect] = []
var _surfers: Array[Surfer] = []
var _labels: Array[Label] = []
var _cycler: Surfer
var _cycler_label: Label
var _cycler_index := 0
var _timer := 0.0
var _paused := false
var _built := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	if UrlParams.has("gallery"):
		open()


## Builds the gallery the first time it is shown, then shows it.
func open() -> void:
	if not _built:
		_build()
	visible = true
	set_process(true)
	_layout()


func close() -> void:
	visible = false
	set_process(false)


func _build() -> void:
	_built = true
	_background = ColorRect.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	for pose_name in PoseLibrary.ORDER:
		var cell := ColorRect.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cell)
		_cells.append(cell)
		var surfer := Surfer.new()
		surfer.set_pose(pose_name, 0.0)
		add_child(surfer)
		_surfers.append(surfer)
		_labels.append(_add_label(PoseLibrary.LABELS[pose_name], 15))
	_cycler = Surfer.new()
	_cycler.set_pose(PoseLibrary.ORDER[0], 0.0)
	add_child(_cycler)
	_cycler_label = _add_label("", 22)
	# Looked up by path, not by name: the test runner compiles this script before autoloads exist.
	get_node("/root/Palette").changed.connect(_apply_mood)
	_apply_mood()
	_show_cycler_pose()


func _process(delta: float) -> void:
	if _paused:
		return
	_timer += delta
	if _timer >= HOLD_SECONDS:
		_step(1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_step(1)
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_RIGHT:
		_step(1)
	elif event.keycode == KEY_LEFT:
		_step(-1)
	elif event.keycode == KEY_SPACE:
		_paused = not _paused


func _step(direction: int) -> void:
	_cycler_index = posmod(_cycler_index + direction, PoseLibrary.ORDER.size())
	_timer = 0.0
	_show_cycler_pose()


func _show_cycler_pose() -> void:
	var pose_name: String = PoseLibrary.ORDER[_cycler_index]
	_cycler.set_pose(pose_name)
	_cycler_label.text = PoseLibrary.LABELS[pose_name]


func _layout() -> void:
	if not _built:
		return
	_background.position = Vector2.ZERO
	_background.size = size
	var margin := size.y * 0.03
	var grid := Rect2(margin, margin, size.x * GRID_WIDTH - margin, size.y - margin * 2.0)
	var cell_size := Vector2(grid.size.x / COLUMNS, grid.size.y / ROWS)
	for i in _cells.size():
		var origin := grid.position + Vector2((i % COLUMNS) * cell_size.x, (i / COLUMNS) * cell_size.y)
		_cells[i].position = origin + Vector2.ONE * 3.0
		_cells[i].size = cell_size - Vector2.ONE * 6.0
		_surfers[i].place(origin + Vector2(cell_size.x * 0.5, cell_size.y * 0.80), cell_size.y * CELL_SURFER_HEIGHT)
		_labels[i].position = origin + Vector2(10.0, 6.0)
	var stage := Rect2(size.x * GRID_WIDTH, margin, size.x * (1.0 - GRID_WIDTH) - margin, size.y - margin * 2.0)
	_cycler.place(stage.position + Vector2(stage.size.x * 0.5, stage.size.y * 0.80), size.y * CYCLER_SURFER_HEIGHT)
	_cycler_label.position = stage.position + Vector2(8.0, 4.0)


func _apply_mood() -> void:
	var mood: MoodData = get_node("/root/Palette").current
	_background.color = mood.wave_deep
	for cell in _cells:
		cell.color = mood.wave_mid


func _add_label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#FDE9DE"))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 5)
	add_child(label)
	return label
