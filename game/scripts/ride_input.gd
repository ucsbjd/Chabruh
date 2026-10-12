class_name RideInput
extends Node
## Turns every kind of pointing into two numbers: `steer` (0 behind, close to the curl, up to 1 far
## ahead, to the left) and `height` (0 at the bottom of the face, 1 at the top). Mouse X points at a
## place along the wave; the mouse wheel, a trackpad's two-finger scroll, a touch screen's two-finger
## drag and the arrow keys or WASD nudge them. The Rider smooths and limits the result, not this.

## Every raw input is announced (kind, amount, position) so the calibration run can record it.
signal raw_event(kind: String, amount: Vector2, where: Vector2)

const REST_STEER := 0.49             # the pocket
const REST_HEIGHT := 0.5
## On a touch screen the full face is this fraction of the screen height of finger travel.
const TOUCH_FACE_FRACTION := 0.45

var steer := REST_STEER
var height := REST_HEIGHT
var tuning: TuningData = preload("res://data/tuning.tres")

var _touches := {}
var _busy := Vector2.ZERO            # how much recent scrolling there was in (steering, height), fading
var _busy_at := 0.0


func reset() -> void:
	steer = REST_STEER
	height = REST_HEIGHT


## Feed every input event through here. `view` is the size of the screen, in pixels. `now` is the event's time
## in seconds (leave it out to use the clock; a replay of a recording passes the recorded time).
func handle(event: InputEvent, view: Vector2, now := -1.0) -> void:
	if event is InputEventMouseMotion:
		if _touches.size() < 2:
			steer = _shape(1.0 - event.position.x / maxf(view.x, 1.0))
			raw_event.emit("mouse", event.relative, event.position)
	elif event is InputEventMouseButton and event.pressed:
		var amount: float = event.factor if event.factor > 0.0 else 1.0
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT:
				raw_event.emit("wheel", Vector2(event.button_index, amount), event.position)
				_scroll(event.button_index, amount, now if now >= 0.0 else Time.get_ticks_msec() / 1000.0)
			_:
				return
	elif event is InputEventPanGesture:
		# Fingers moving up the pad (negative y) lift the surfer.
		height += -event.delta.y * tuning.pan_height_gain * (-1.0 if tuning.invert_pan_height else 1.0)
		steer += -event.delta.x * tuning.pan_steer_gain * (-1.0 if tuning.invert_pan_steer else 1.0)
		raw_event.emit("pan", event.delta, Vector2.ZERO)
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			# Two fingers moving together: each reports its own move, so take half of each.
			var move: Vector2 = event.relative * 0.5
			height += -move.y / (view.y * TOUCH_FACE_FRACTION)
			steer += -move.x / (view.x * TOUCH_FACE_FRACTION)
			raw_event.emit("touch_drag", move, event.position)
	_clamp()


## One step of wheel or trackpad scroll. `now` is in seconds.
func _scroll(button: int, amount: float, now: float) -> void:
	var vertical := button == MOUSE_BUTTON_WHEEL_UP or button == MOUSE_BUTTON_WHEEL_DOWN
	var eased := tuning.wheel_cap * tanh(amount / tuning.wheel_cap)
	_busy *= exp(-(now - _busy_at) / tuning.axis_lock_window)
	_busy_at = now
	var mine := _busy.y if vertical else _busy.x
	var other := _busy.x if vertical else _busy.y
	if other > 0.02 and mine * tuning.axis_lock_ratio < other:
		return
	if vertical:
		_busy.y += eased
	else:
		_busy.x += eased
	match button:
		MOUSE_BUTTON_WHEEL_UP:
			height += tuning.wheel_height_step * eased
		MOUSE_BUTTON_WHEEL_DOWN:
			height -= tuning.wheel_height_step * eased
		MOUSE_BUTTON_WHEEL_LEFT:
			steer += tuning.wheel_steer_step * eased
		MOUSE_BUTTON_WHEEL_RIGHT:
			steer -= tuning.wheel_steer_step * eased


## Held keys: call every frame.
func process(delta: float) -> void:
	var up := float(Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S))
	var ahead := float(Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)) - float(Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D))
	if up != 0.0 or ahead != 0.0:
		height += up * tuning.key_rate * delta
		steer += ahead * tuning.key_rate * delta
		raw_event.emit("key", Vector2(ahead, up) * delta, Vector2.ZERO)
		_clamp()


## Dead zone and response curve, applied around the middle of the screen: the middle is the pocket.
func _shape(value: float) -> float:
	var c := value * 2.0 - 1.0
	var magnitude := absf(c)
	if magnitude < tuning.dead_zone:
		return REST_STEER
	magnitude = (magnitude - tuning.dead_zone) / (1.0 - tuning.dead_zone)
	magnitude = pow(magnitude, tuning.response_curve) * tuning.reach / 0.8
	return clampf(REST_STEER + 0.5 * signf(c) * magnitude, 0.0, 1.0)


func _clamp() -> void:
	steer = clampf(steer, 0.0, 1.0)
	height = clampf(height, 0.0, 1.0)
