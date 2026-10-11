class_name WaveLayer
extends ColorRect
## Draws the wave with wave.gdshader. It owns the WaveModel, bakes the model's profile into a
## small texture whenever size or hollowness change, and tells the shader where the peel point
## is. The peel point is the only thing that moves each frame, and it moves with a uniform.

## The model that shapes this wave. Change its size and hollowness, then call rebake().
var model := WaveModel.new()

## Where the peel point is, in the scene's layout units (screen heights across, from the left).
var peel_x := 1.2:
	set(value):
		peel_x = value
		_uniform("peel_x", value)

var _profile: ImageTexture
var _cells: ImageTexture
var _warp: ImageTexture


func _ready() -> void:
	_profile = ImageTexture.create_from_image(model.bake_profile())
	_cells = NoiseTextures.cells()
	_warp = NoiseTextures.warp()
	_uniform("profile", _profile)
	_uniform("noise_cells", _cells)
	_uniform("noise_warp", _warp)
	_uniform("profile_d0", -WaveModel.PROFILE_BEHIND)
	_uniform("profile_d1", WaveModel.PROFILE_AHEAD)
	_uniform("peel_x", peel_x)
	rebake()


func _exit_tree() -> void:
	# The material is a sub-resource shared by the scene, so let go of the textures explicitly.
	for parameter in [&"profile", &"noise_cells", &"noise_warp"]:
		_uniform(parameter, null)


## Re-reads the model after its size or hollowness changed.
func rebake() -> void:
	_profile.update(model.bake_profile())
	_uniform("barrel", model.barrel())
	_uniform("hollowness", model.hollowness)
	_uniform("wave_height", model.height())


func _uniform(parameter: StringName, value: Variant) -> void:
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter(parameter, value)
