class_name WaveStage
extends Control
## The wave and the sea, drawn in 3D inside a transparent SubViewport and shown as one layer of
## the 2D scene. The game stays 2D (sprites, layers, parallax); only the wave's body is a small
## 3D mesh, so it gets real perspective and a real barrel. A telephoto camera sits behind the
## surfer on the beach side, looking a little down the line.

const WAVE_SHADER := preload("res://shaders/wave3d.gdshader")
const WATER_SHADER := preload("res://shaders/water3d.gdshader")
const MIST_SHADER := preload("res://shaders/mist3d.gdshader")
const CARVE_SHADER := preload("res://shaders/carve3d.gdshader")

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
## A reshape (the wave following the reef or the tide) is built over several frames, this many microseconds a frame.
const RESHAPE_BUDGET_USEC := 2500
## The real-time surfer is also drawn alone, at MASK_SCALE of the screen's size, on the render layer SURFER_LAYER (a bit
## mask), so the 2D spray that should fall behind him can leave out his silhouette (surfer_mask()). This 3D stage is one
## layer of the 2D scene, below all the spray, so without it the whole fan paints over him.
const SURFER_LAYER := 2
const MASK_SCALE := 0.5

## The model that shapes this wave. Change its size and hollowness, then call rebuild().
var model := WaveModel.new()
## The foam the board cuts into the face. The world feeds it from the rider every frame.
var carve_trail := WaveCarveTrail.new()

var _viewport := SubViewport.new()
var _camera := Camera3D.new()
var _mask_viewport := SubViewport.new()
var _mask_camera := Camera3D.new()
var _wave_mesh := MeshInstance3D.new()
var _water_mesh := MeshInstance3D.new()
var _mist_mesh := MeshInstance3D.new()
var _picture := TextureRect.new()
var _wave_material := ShaderMaterial.new()
var _water_material := ShaderMaterial.new()
var _mist_material := ShaderMaterial.new()
var _carve_material := ShaderMaterial.new()
var _profile: ImageTexture
var _cells: ImageTexture
var _warp: ImageTexture
var _scroll := 0.0
var _mesh_job: WaveMeshBuilder
var _mist_job: WaveMistBuilder


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
	_mask_viewport.transparent_bg = true
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_mask_viewport)
	_mask_camera.near = _camera.near
	_mask_camera.far = _camera.far
	_mask_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_mask_camera.cull_mask = SURFER_LAYER
	_mask_viewport.add_child(_mask_camera)

	_wave_material.shader = WAVE_SHADER
	_water_material.shader = WATER_SHADER
	_mist_material.shader = MIST_SHADER
	_wave_mesh.material_override = _wave_material
	_viewport.add_child(_wave_mesh)
	_mist_mesh.material_override = _mist_material
	_mist_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_viewport.add_child(_mist_mesh)
	_carve_material.shader = CARVE_SHADER
	carve_trail.material_override = _carve_material
	_viewport.add_child(carve_trail)

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
	# (the surfer's silhouette is drawn from the same world as the wave, the surfer alone)
	_mask_viewport.world_3d = _viewport.find_world_3d()
	resized.connect(_fit_viewport)
	_fit_viewport()
	rebuild()


func _process(delta: float) -> void:
	_scroll += SEA_SCROLL_SPEED * delta
	_water_material.set_shader_parameter("scroll", _scroll)
	_advance_reshape()
	feed_reef()


func _exit_tree() -> void:
	# The materials are ours, but the textures are big; let go of them explicitly.
	for material in materials():
		material.set_shader_parameter("noise_cells", null)
		material.set_shader_parameter("noise_warp", null)
	_water_material.set_shader_parameter("profile", null)


## Puts something else (the real-time surfer) in the same 3D stage, so it shares the camera and the depth with the wave.
func add_actor(node: Node3D) -> void:
	_viewport.add_child(node)


## The surfer alone, as a picture the size of this stage at MASK_SCALE: opaque where he is (see SURFER_LAYER).
func surfer_mask() -> Texture2D:
	return _mask_viewport.get_texture()


## The shader materials, so the world can feed them the mood's colours.
func materials() -> Array[ShaderMaterial]:
	return [_wave_material, _water_material, _mist_material, _carve_material]


## Rebuilds the mesh and profile after the model's size or hollowness changed.
func rebuild() -> void:
	_mesh_job = null
	_mist_job = null
	_wave_mesh.mesh = WaveMesh.build(model)
	_mist_mesh.mesh = WaveMist.build(model)
	_profile.update(model.bake_profile())
	carve_trail.rebuild(model)


## Starts building the wave again for the model's current shape dials, a little each frame (so it never hitches);
## the new mesh replaces the old one when it is done. Leave the model's size and hollowness alone until reshaping()
## is false.
func reshape() -> void:
	_mesh_job = WaveMeshBuilder.new(model)
	_mist_job = WaveMistBuilder.new(model)


## Whether a reshape is still being built.
func reshaping() -> bool:
	return _mesh_job != null


func _advance_reshape() -> void:
	if _mesh_job == null:
		return
	var start := Time.get_ticks_usec()
	if not _mesh_job.step(RESHAPE_BUDGET_USEC):
		return
	if not _mist_job.step(RESHAPE_BUDGET_USEC - (Time.get_ticks_usec() - start)):
		return
	_wave_mesh.mesh = _mesh_job.mesh
	_mist_mesh.mesh = _mist_job.mesh
	_mesh_job = null
	_mist_job = null
	_profile.update(model.bake_profile())
	carve_trail.rebuild(model)


## Passes the reef sections and the swell to the shaders, which scale and shape the built wave with them exactly as
## WaveModel.section_key does for the rider.
func feed_reef() -> void:
	var a := Vector4(1000.0, 0.001, 0.0, 0.0)
	var b := a
	if model.reef != null:
		a = model.reef.uniform_for(0, model.height(), WaveModel.MIN_HEIGHT, WaveModel.MAX_HEIGHT)
		b = model.reef.uniform_for(1, model.height(), WaveModel.MIN_HEIGHT, WaveModel.MAX_HEIGHT)
	for material: ShaderMaterial in [_wave_material, _water_material, _mist_material]:
		material.set_shader_parameter("reef_a", a)
		material.set_shader_parameter("reef_b", b)
		material.set_shader_parameter("swell", model.swell)


## Where in its cycle the lip is at d, 0 to 1, right now: the same number the shader computes.
## It reaches LIP_LANDING_PHASE as the lip falls.
static func lip_phase_at(d: float, at_time: float) -> float:
	return fposmod(at_time / LIP_PERIOD + d / LIP_SPACING, 1.0)


## How far a lip at `phase` of its cycle has lifted the wave (x) and dropped it (y), 0 to 1 each before the amount of lip
## there: the weights wave3d.gdshader's vertex morph uses, so whatever sits on the face can move with it.
static func lip_morph(phase: float) -> Vector2:
	var lift := smoothstep(0.86, 1.0, phase) + 1.0 - smoothstep(0.0, 0.28, phase)
	var fall := smoothstep(0.50, 0.66, phase) * (1.0 - smoothstep(0.74, 0.92, phase))
	return Vector2(lift, fall)


## Points the camera so that `focus` (the surfer's feet, in world meters) lands at `screen_x` (a
## fraction of the width) and SURFER_SCREEN_Y, and the horizon on HORIZON_Y. `yaw_degrees` turns the
## camera: positive looks left from behind the surfer, negative looks right from ahead of them. `fov_degrees` and
## `distance` (meters) let the camera tuck in a little for the barrel.
func frame(focus: Vector3, yaw_degrees: float, screen_x: float, fov_degrees := CAMERA_FOV, distance := CAMERA_DISTANCE) -> void:
	_camera.fov = fov_degrees
	var tan_half := tan(deg_to_rad(fov_degrees * 0.5))
	var aspect := float(_viewport.size.x) / float(_viewport.size.y)
	var pitch := atan((0.5 - HORIZON_Y) * 2.0 * tan_half)
	var basis := Basis.from_euler(Vector3(-pitch, deg_to_rad(yaw_degrees), 0.0), EULER_ORDER_YXZ)
	var ray := Vector3((screen_x - 0.5) * 2.0 * tan_half * aspect, -(SURFER_SCREEN_Y - 0.5) * 2.0 * tan_half, -1.0)
	_camera.basis = basis
	_camera.position = focus - basis * ray * distance
	_mask_camera.fov = fov_degrees
	_mask_camera.transform = _camera.transform


## Which way the camera looks, in world axes (its forward is -Z, its right +X).
func camera_basis() -> Basis:
	return _camera.basis


## Where a world position lands on this control, in pixels of this control.
func project(world: Vector3) -> Vector2:
	return _camera.unproject_position(world) / Vector2(_viewport.size) * size


func _fit_viewport() -> void:
	var window := get_window()
	var pixels := Vector2(window.size) if window != null else size
	_viewport.size = Vector2i(maxi(int(pixels.x), 16), maxi(int(pixels.y), 16))
	_mask_viewport.size = Vector2i(maxi(int(pixels.x * MASK_SCALE), 8), maxi(int(pixels.y * MASK_SCALE), 8))
