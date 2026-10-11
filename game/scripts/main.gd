extends Node2D
## Step 1 placeholder: a sunset, a sun and a moving sea line. It only proves that rendering,
## resizing and animation work in the web build. Real art starts in step 2.

const HORIZON_FRACTION := 0.62
const SUN_RADIUS := 90.0
const SEA_LINE_COUNT := 5
const SEA_LINE_STEP := 16.0
const SEA_LINE_WIDTH := 3.0
const WAVE_AMPLITUDE := 5.0
const WAVE_LENGTH := 170.0
const WAVE_SPEED := 45.0

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	var horizon := size.y * HORIZON_FRACTION
	_draw_sky(size.x, horizon)
	draw_circle(Vector2(size.x * 0.5, horizon - SUN_RADIUS * 0.3), SUN_RADIUS, Palette.SUN)
	draw_rect(Rect2(0.0, horizon, size.x, size.y - horizon), Palette.WAVE_DEEP)
	_draw_sea_lines(size, horizon)


func _draw_sky(width: float, horizon: float) -> void:
	var stops := Palette.SKY_STOPS
	var bands := stops.size() - 1
	for i in bands:
		var top := horizon * i / bands
		var bottom := horizon * (i + 1) / bands
		draw_polygon(
			PackedVector2Array([Vector2(0.0, top), Vector2(width, top), Vector2(width, bottom), Vector2(0.0, bottom)]),
			PackedColorArray([stops[i], stops[i], stops[i + 1], stops[i + 1]]))


func _draw_sea_lines(size: Vector2, horizon: float) -> void:
	var depth := size.y - horizon
	for line in SEA_LINE_COUNT:
		var near := float(line + 1) / (SEA_LINE_COUNT + 1)
		var base_y := horizon + depth * near * near
		var amplitude := WAVE_AMPLITUDE * (0.4 + near * 1.6)
		var drift := _time * WAVE_SPEED * (0.5 + near)
		var points := PackedVector2Array()
		for x in range(0, int(size.x) + int(SEA_LINE_STEP), int(SEA_LINE_STEP)):
			var y := base_y + sin((x + drift) / WAVE_LENGTH * TAU) * amplitude
			points.append(Vector2(x, y))
		draw_polyline(points, Palette.WAVE_LIGHT, SEA_LINE_WIDTH * (0.5 + near))
