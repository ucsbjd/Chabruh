class_name DebugPanel
extends PanelContainer
## Temporary sliders for trying the wave out, usable with a mouse or a finger. Shown with ?debug
## in the URL or the D key. Step 5 replaces this with the real tuning panel.

signal values_changed(size: float, hollowness: float, peel_offset: float)

const PEEL_MIN := -1.2
const PEEL_MAX := 2.5

var _size := HSlider.new()
var _hollow := HSlider.new()
var _peel := HSlider.new()


func _init() -> void:
	# The sliders are fields, so attach them now: a scene that is never started must not orphan them.
	var rows := VBoxContainer.new()
	add_child(rows)
	_add_row(rows, "size", _size, 0.0, 1.0)
	_add_row(rows, "hollow", _hollow, 0.0, 1.0)
	_add_row(rows, "peel", _peel, PEEL_MIN, PEEL_MAX)


func _ready() -> void:
	visible = UrlParams.has("debug")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_D:
		visible = not visible


## Moves the sliders to these values without announcing a change.
func show_values(size: float, hollowness: float, peel_offset: float) -> void:
	_size.set_value_no_signal(size)
	_hollow.set_value_no_signal(hollowness)
	_peel.set_value_no_signal(peel_offset)


func _add_row(rows: VBoxContainer, label_text: String, slider: HSlider, low: float, high: float) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(70.0, 0.0)
	slider.min_value = low
	slider.max_value = high
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(240.0, 30.0)
	slider.value_changed.connect(_on_slider_changed)
	row.add_child(label)
	row.add_child(slider)
	rows.add_child(row)


func _on_slider_changed(_value: float) -> void:
	values_changed.emit(_size.value, _hollow.value, _peel.value)
