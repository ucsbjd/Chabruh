class_name NoiseTextures
extends RefCounted
## Two small seamless noise textures, generated once at load. The wave shader samples these
## instead of computing noise per pixel, which is what keeps it cheap on a phone.

const SIZE := 256


## Cell-edge network: dark (near 0) along thin lines that split the plane into big polygons,
## brighter toward the middle of each cell. Gives the pale veins on the face and the foam clumps.
static func cells() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	noise.cellular_jitter = 1.0
	noise.frequency = 0.035
	noise.seed = 7
	return _texture(noise)


## Smooth blotchy noise, used to wobble band edges and to cut ragged shapes.
static func warp() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.frequency = 0.02
	noise.seed = 21
	return _texture(noise)


static func _texture(noise: FastNoiseLite) -> ImageTexture:
	var image := noise.get_seamless_image(SIZE, SIZE)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)
