extends Label
## Frame-rate readout for testing on a phone. Shown with ?fps in the URL; the backtick key
## toggles it anywhere.

const REFRESH_SECONDS := 0.5

var _since_refresh := 0.0


func _ready() -> void:
	visible = UrlParams.has("fps")


func _process(delta: float) -> void:
	_since_refresh += delta
	if visible and _since_refresh >= REFRESH_SECONDS:
		_since_refresh = 0.0
		text = "%d fps" % Engine.get_frames_per_second()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_QUOTELEFT:
		visible = not visible
