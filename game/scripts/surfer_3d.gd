class_name Surfer3D
extends Node3D
## The real-time surfer: a skinned model (tools/foundry/export_surfer_glb.py makes surfer.glb) that lives inside the
## wave's own 3D stage, so the lip and the mist can pass in front of him and the camera can move around him.
## Poses are baked in the model as one-frame animations (board level, feet already pinned by IK in Blender). They are
## never played: the bones are blended in code by weights that follow their targets on a short spring, so any pose
## can be interrupted at any moment.

const MODEL := "res://assets/models/surfer.glb"
const BASE_POSE := "trim"
## Seconds for a pose weight to close most of the way to its target.
const BLEND_TIME := 0.12
## How much the board tilts with the wave face (0 flat to the sea, 1 flush with the face).
const FACE_ALIGN := 0.55
## Bones that lead a turn, root to tip, and how much of the lead each takes.
const LEAD_BONES := [["spine02", 0.15], ["spine01", 0.2], ["neck01", 0.15], ["neck02", 0.15], ["head", 0.3]]

var material := ShaderMaterial.new()
var skeleton: Skeleton3D
var _poses := {}  # pose name -> {bone index -> [position, rotation]}
var _targets := {}
var _weights := {}
var _lead := 0.0  # radians the head and chest are already turned into the coming move


func _init() -> void:
	material.shader = load("res://shaders/surfer3d.gdshader") as Shader
	var scene := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(scene)
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = material
	skeleton = scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for pose_name in player.get_animation_list():
		_poses[String(pose_name)] = _read_pose(player.get_animation(pose_name))
		_weights[String(pose_name)] = 0.0
		_targets[String(pose_name)] = 0.0
	player.get_parent().remove_child(player)
	player.free()
	_apply()


func pose_names() -> Array:
	return _poses.keys()


## Sets how strongly a pose should show (0 to 1); the surfer eases toward it. The base pose is always underneath.
func set_target(pose_name: String, weight_value: float) -> void:
	if _targets.has(pose_name):
		_targets[pose_name] = clampf(weight_value, 0.0, 1.0)


func target(pose_name: String) -> float:
	return _targets.get(pose_name, 0.0)


func weight(pose_name: String) -> float:
	return _weights.get(pose_name, 0.0)


func _process(delta: float) -> void:
	step(delta)


## Moves the pose weights toward their targets by `delta` seconds and re-poses the bones.
func step(delta: float) -> void:
	var k := 1.0 - exp(-delta / BLEND_TIME)
	for pose_name: String in _weights:
		_weights[pose_name] = lerpf(_weights[pose_name], _targets[pose_name], k)
	_apply()


## Stands the surfer on the wave at (d, u), heading down the line, the board tilted part-way to the face.
func stand_on(model: WaveModel, d: float, u: float) -> void:
	_place(model, d, u, 0.0, 0.0)


## Drives the surfer from the rider's physical state: where he is and which way his nose points, the board rolled
## onto its rail by the turn, the baked poses blended by how he is moving, and the head and chest leading the turn.
func follow(rider: Rider, model: WaveModel, delta: float) -> void:
	_place(model, rider.d, rider.u, rider.theta, rider.rail_roll)
	var bottom := clampf(rider.omega / 2.2, 0.0, 1.0) * clampf(1.0 - rider.u, 0.2, 1.0)
	var top := clampf(-rider.omega / 2.0, 0.0, 1.0) * clampf(rider.u, 0.3, 1.0)
	var barrel := model.barrel_amount_at(rider.d, rider.u)
	var crouch := clampf(rider.compression, 0.0, 1.0) * (1.0 - barrel * 0.5)
	# The poses are layered on the trim pose; keep their total at one so no joint is pushed past a baked pose.
	var total := bottom + top + crouch
	var scale := 1.0 / maxf(total, 1.0)
	set_target("bottom_turn", bottom * scale)
	set_target("top_turn", top * scale)
	set_target("crouch", crouch * scale)
	_lead = rider.lead
	step(delta)


func _place(model: WaveModel, d: float, u: float, theta: float, roll: float) -> void:
	var normal := model.surface_normal(d, u).normalized()
	var t_crest := Vector3(-1.0, 0.0, 0.0)  # down the line
	var t_face := normal.cross(t_crest).normalized()  # up the face, toward the lip
	t_crest = t_face.cross(normal).normalized()
	var forward := (t_crest * cos(theta) + t_face * sin(theta)).normalized()
	var up := Vector3.UP.lerp(normal, FACE_ALIGN).normalized()
	# The model's nose points down its -X and its chest toward -Z; its +X is the tail.
	var along := (-forward - up * (-forward).dot(up)).normalized()
	var basis := Basis(along, up, along.cross(up))
	# Rolling about the board's own length puts the toe-side (wave-side) rail down for a positive roll.
	basis = basis * Basis(Vector3.RIGHT, roll)
	transform = Transform3D(basis, model.surface_point(d, u))


func _apply() -> void:
	var base: Dictionary = _poses.get(BASE_POSE, {})
	for bone: int in base:
		var bone_position: Vector3 = base[bone][0]
		var bone_rotation: Quaternion = base[bone][1]
		for pose_name: String in _weights:
			var w: float = _weights[pose_name]
			if w <= 0.001 or pose_name == BASE_POSE or not _poses[pose_name].has(bone):
				continue
			bone_position = bone_position.lerp(_poses[pose_name][bone][0], w)
			bone_rotation = bone_rotation.slerp(_poses[pose_name][bone][1], w)
		skeleton.set_bone_pose_position(bone, bone_position)
		skeleton.set_bone_pose_rotation(bone, bone_rotation)
	_apply_lead()


func _read_pose(animation: Animation) -> Dictionary:
	var pose := {}
	for t in animation.get_track_count():
		var bone := skeleton.find_bone(String(animation.track_get_path(t)).get_slice(":", 1))
		if bone < 0 or animation.track_get_key_count(t) == 0:
			continue
		if not pose.has(bone):
			pose[bone] = [skeleton.get_bone_rest(bone).origin, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()]
		match animation.track_get_type(t):
			Animation.TYPE_POSITION_3D:
				pose[bone][0] = animation.track_get_key_value(t, 0)
			Animation.TYPE_ROTATION_3D:
				pose[bone][1] = animation.track_get_key_value(t, 0)
	return pose


## Turns the neck, head and upper back about the vertical, so the surfer looks and torques into a turn before the
## board has come round. Bones are visited root to tip so each sees its parent's final pose.
func _apply_lead() -> void:
	if absf(_lead) < 0.001:
		return
	for entry in LEAD_BONES:
		var bone := skeleton.find_bone(entry[0])
		if bone < 0:
			continue
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var world_twist := Basis(Vector3.UP, -_lead * entry[1])
		var local_twist := parent_basis.inverse() * world_twist * parent_basis
		skeleton.set_bone_pose_rotation(bone, local_twist.get_rotation_quaternion() * skeleton.get_bone_pose_rotation(bone))
