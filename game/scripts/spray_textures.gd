class_name SprayTextures
extends RefCounted
## The few little shapes every spray particle is drawn with: flat, hard-edged white ovals, like the
## droplets in the key frames. They are white so the mood can tint them; made once at load.

## A droplet stretched along its Y axis (particles align Y to their velocity, so it trails behind).
static func droplet() -> ImageTexture:
	return _oval(8, 38)


## A fatter, shorter oval for foam that lies on the water.
static func blob() -> ImageTexture:
	return _oval(36, 22)


## A long thin oval for the foam sheet trailing on the water behind the board.
static func sheet() -> ImageTexture:
	return _oval(56, 9)


## An oval of the given pixel size with a one-pixel soft edge.
static func _oval(width: int, height: int) -> ImageTexture:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var half := Vector2(width, height) * 0.5
	for y in height:
		for x in width:
			var offset := (Vector2(x + 0.5, y + 0.5) - half) / half
			var edge := 1.0 - offset.length()
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(edge * minf(half.x, half.y), 0.0, 1.0)))
	return ImageTexture.create_from_image(image)
