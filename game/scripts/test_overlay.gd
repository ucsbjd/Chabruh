class_name TestOverlay
extends VBoxContainer
## Testing only: a column of small buttons down the right of the screen, one per hotkey, that trigger the game's events
## and stages (reef sections, the barrel, a wipeout, a lull, each part of the evening). Each works by key or by a click
## or tap, so a phone can use them too. A line at the top says what the reef and the evening are doing. H hides it with
## the other test text.

const FONT_SIZE := 13
const BUTTON_ALPHA := 0.72

var _actions := {}                   # keycode to the callable it runs
var _status := Label.new()
var _groups := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	_status.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_status.add_theme_constant_override("outline_size", 4)
	_status.modulate = Color(1, 1, 1, 0.75)
	add_child(_status)


## A heading for the buttons that follow.
func add_group(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	_groups[title] = label


## A button and a hotkey that both run `action`.
func add_action(keycode: Key, text: String, action: Callable) -> void:
	_actions[keycode] = action
	var button := Button.new()
	button.text = "%s   %s" % [OS.get_keycode_string(keycode), text]
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	button.flat = true
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	button.modulate = Color(1, 1, 1, BUTTON_ALPHA)
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	button.add_theme_constant_override("outline_size", 4)
	# (no padding: a tight column that leaves the wave in view)
	var bare := StyleBoxEmpty.new()
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, bare)
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.6))
	button.pressed.connect(action)
	add_child(button)


## Runs the action for a pressed key; true if there was one.
func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or not _actions.has(event.keycode):
		return false
	(_actions[event.keycode] as Callable).call()
	return true


func has_key(keycode: Key) -> bool:
	return _actions.has(keycode)


func set_status(text: String) -> void:
	_status.text = text


func status() -> String:
	return _status.text
