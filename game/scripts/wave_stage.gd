class_name WaveStage
extends Control
## The wave and the sea, drawn in 3D inside a transparent SubViewport and shown as one layer of
## the 2D scene. The game stays 2D (sprites, layers, parallax); only the wave's body is a small
## 3D mesh, so it gets real perspective and a real barrel. A telephoto camera sits behind the
## surfer on the beach side, looking a little down the line.

const WAVE_SHADER := preload("res://shaders/wave3d.gdshader")
const WATER_SHADER := preload("res://shaders/water3d.gdshader")
const MIST_SHADER := preload("res://shaders/mist3d.gdshader")

## Camera: a long lens, so perspective is gentle but clear. Distances are meters.
const CAMERA_DISTANCE := 19.0
const CAMERA_FOV := 21.0                 # vertical, degrees
const HORIZON_Y := 0.40                  # where the horizon sits on screen, 0 top to 1 bottom
## How far down the screen the surfer's feet sit, as a fraction of the height.
const SURFER_SCREEN_Y := 0.70
const SEA_SCROLL_SPEED := 6.0            # meters per second the sea slides past
## The lip's cycle (see wave3d.gdshader): seconds from one lift to the next, and meters along the crest
## between lips in the same state. Spray that follows the lip reads the same numbers.
const LIP_PERIOD := 5.5
const LIP_SPACING := 15.0
## How far into the cycle the lip has fallen and landed, where the spit happens.
const LIP_LANDING_PHASE := 0.68

## The model that shapes this wave. Change its size and hollowness, then call rebuild().
var model := WaveModel.new()

var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _wave_mesh := MeshInstance3D.new()
var _water_mesh := MeshInstance3D.new()
var _mist_mesh := MeshInstance3D.new()
var _picture := TextureRect.new()
var _wave_material := ShaderMaterial.new()
var _water_material := ShaderMaterial.new()
var _mist_material := ShaderMaterial.new()
var _profile: ImageTexture
var _cells: ImageTexture
var _warp: ImageTexture
var _scroll := 0.0


func _init() -> void:
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_camera.fov = CAMERA_FOV
	_camera.near = 1.0
	_camera.far = 6000.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_camera)

	_wave_material.shader = WAVE_SHADER
	_water_material.shader = WATER_SHADER
	_mist_material.shader = MIST_SHADER
	_wave_mesh.material_override = _wave_material
	_viewport.add_child(_wave_mesh)
	_mist_mesh.material_override = _mist_material
	_mist_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(_mist_mesh)

	var plane := PlaneMesh.new()
	plane.size = Vector2(8000.0, 8000.0)
	_water_mesh.mesh = plane
	_water_mesh.material_override = _water_material
	_water_mesh.position = Vector3(0.0, -0.03, 0.0)
	_viewport.add_child(_water_mesh)

	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.texture = _viewport.get_texture()
	add_child(_picture)


func _ready() -> void:
	_cells = NoiseTextures.cells()
	_warp = NoiseTextures.warp()
	_profile = ImageTexture.create_from_image(model.bake_profile())
	for material in materials():
		material.set_shader_parameter("noise_cells", _cells)
		material.set_shader_parameter("noise_warp", _warp)
	_water_material.set_shader_parameter("profile", _profile)
	_water_material.set_shader_parameter("profile_d0", -WaveModel.PROFILE_BEHIND)
	_water_material.set_shader_parameter("profile_d1", WaveModel.PROFILE_AHEAD)
	_wave_material.set_shader_parameter("lip_period", LIP_PERIOD)
	_wave_material.set_shader_parameter("lip_spacing", LIP_SPACING)
	resized.connect(_fit_viewport)
	_fit_viewport()
	rebuild()


func _process(delta: float) -> void:
	_scroll += SEA_SCROLL_SPEED * delta
	_water_material.set_shader_parameter("scroll", _scroll)


func _exit_tree() -> void:
	# The materials are ours, but the textures are big; let go of them explicitly.
	for material in materials():
		material.set_shader_parameter("noise_cells", null)
		material.set_shader_parameter("noise_warp", null)
	_water_material.set_shader_parameter("profile", null)


## The two shader materials, so the world can feed them the mood's colours.
## Puts something else (the real-time surfer) in the same 3D stage, so it shares the camera and the depth with the wave.
func add_actor(node: Node3D) -> void:
	_viewport.add_child(node)


func materials() -> Array[ShaderMaterial]:
	return [_wave_material, _water_material, _mist_material]


## Rebuilds the mesh and profile after the model's size or hollowness changed.
func rebuild() -> void:
	_wave_mesh.mesh = WaveMesh.build(model)
	_mist_mesh.mesh = WaveMist.build(model)
	_profile.update(model.bake_profile())


## Where in its cycle the lip is at d, 0 to 1, right now: the same number the shader computes.
## It reaches LIP_LANDING_PHASE as the lip falls.
func lip_phase_at(d: float, at_time: float) -> float:
	return fposmod(at_time / LIP_PERIOD + d / LIP_SPACING, 1.0)


## Points the camera so that `focus` (the surfer's feet, in world meters) lands at `screen_x` (a
## fraction of the width) and SURFER_SCREEN_Y, and the horizon on HORIZON_Y. `yaw_degrees` turns the
## camera: positive looks left from behind the surfer, negative looks right from ahead of them.
func frame(focus: Vector3, yaw_degrees: float, screen_x: float) -> void:
	var tan_half := tan(deg_to_rad(CAMERA_FOV * 0.5))
	var aspect := float(_viewport.size.x) / float(_viewport.size.y)
	var pitch := atan((0.5 - HORIZON_Y) * 2.0 * tan_half)
	var basis := Basis.from_euler(Vector3(-pitch, deg_to_rad(yaw_degrees), 0.0), EULER_ORDER_YXZ)
	var ray := Vector3((screen_x - 0.5) * 2.0 * tan_half * aspect, -(SURFER_SCREEN_Y - 0.5) * 2.0 * tan_half, -1.0)
	_camera.basis = basis
	_camera.position = focus - basis * ray * CAMERA_DISTANCE


## Where a world position lands on this control, in pixels of this control.
func project(world: Vector3) -> Vector2:
	return _camera.unproject_position(world) / Vector2(_viewport.size) * size


func _fit_viewport() -> void:
	var window := get_window()
	var pixels := Vector2(window.size) if window != null else size
	_viewport.size = Vector2i(maxi(int(pixels.x), 16), maxi(int(pixels.y), 16))
