class_name ScaleMarker
extends Node2D
## A stand-in surfer so the wave's size can be judged: a few flat shapes seen from behind with
## arms wide, standing on the face. Step 4 replaces it with the real, posed surfer.
## Shapes are built once in surfer units (the standing height is TOTAL_HEIGHT, up is negative,
## the origin is between the feet), so moving it never redraws anything.

const TOTAL_HEIGHT := 0.88
const HAIR := Color("#2A1F2D")


func _ready() -> void:
	_add(PackedVector2Array([Vector2(-0.52, -0.01), Vector2(-0.30, -0.045), Vector2(0.34, -0.045), Vector2(0.54, -0.01), Vector2(0.34, 0.025), Vector2(-0.30, 0.025)]), Palette.BOARD)
	_add(PackedVector2Array([Vector2(0.06, -0.04), Vector2(0.15, -0.04), Vector2(0.14, -0.36), Vector2(0.03, -0.36)]), Palette.SUIT_SECONDARY)
	_add(PackedVector2Array([Vector2(-0.20, -0.04), Vector2(-0.11, -0.04), Vector2(-0.06, -0.36), Vector2(-0.17, -0.36)]), Palette.SUIT_SECONDARY)
	_add(PackedVector2Array([Vector2(-0.19, -0.33), Vector2(0.17, -0.33), Vector2(0.16, -0.47), Vector2(-0.17, -0.47)]), Palette.SUIT_SECONDARY)
	_add(PackedVector2Array([Vector2(-0.17, -0.45), Vector2(0.16, -0.45), Vector2(0.15, -0.70), Vector2(-0.16, -0.70)]), Palette.SUIT_PRIMARY)
	_add(PackedVector2Array([Vector2(-0.15, -0.66), Vector2(-0.50, -0.58), Vector2(-0.52, -0.63), Vector2(-0.16, -0.72)]), Palette.SUIT_PRIMARY)
	_add(PackedVector2Array([Vector2(0.14, -0.66), Vector2(0.48, -0.74), Vector2(0.49, -0.79), Vector2(0.13, -0.72)]), Palette.SUIT_PRIMARY)
	_add(PackedVector2Array([Vector2(-0.50, -0.58), Vector2(-0.57, -0.58), Vector2(-0.58, -0.63), Vector2(-0.52, -0.63)]), Palette.SKIN)
	_add(PackedVector2Array([Vector2(0.48, -0.74), Vector2(0.55, -0.76), Vector2(0.56, -0.81), Vector2(0.49, -0.79)]), Palette.SKIN)
	_add(PackedVector2Array([Vector2(-0.035, -0.70), Vector2(0.035, -0.70), Vector2(0.03, -0.74), Vector2(-0.03, -0.74)]), Palette.SKIN)
	_add(_circle(Vector2(0.0, -0.80), 0.065, 10), HAIR)


## Puts the surfer on the face at `d` ahead of the peel point and `u` of the way up the face.
## `x` is the surfer's place across the layout; `unit` is the screen height in pixels and `crop`
## the layout width hidden off the left edge of a narrow screen.
func place(model: WaveModel, x: float, d: float, u: float, unit: float, crop: float) -> void:
	position = Vector2((x - crop) * unit, model.surface_y(d, u) * unit)
	scale = Vector2.ONE * (WaveModel.SURFER_HEIGHT / TOTAL_HEIGHT * unit)


func _add(points: PackedVector2Array, colour: Color) -> void:
	var shape := Polygon2D.new()
	shape.polygon = points
	shape.color = colour
	add_child(shape)


func _circle(centre: Vector2, radius: float, points: int) -> PackedVector2Array:
	var outline := PackedVector2Array()
	for i in points:
		outline.append(centre + Vector2.from_angle(TAU * i / points) * radius)
	return outline
