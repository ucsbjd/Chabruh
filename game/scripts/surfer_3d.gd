class_name Surfer3D
extends Node3D
## The real-time surfer: a skinned model (tools/foundry/export_surfer_glb.py makes surfer.glb) that lives inside the
## wave's own 3D stage, so the lip and the mist can pass in front of him and the camera can move around him.
##
## Baked poses (one-frame animations, board level) give the body its overall shape: spine, hips, head. They are never
## played; the bones are blended by weights that follow their targets on a short spring, so any pose can be interrupted.
## On top of that the body is driven from the rider's physical state:
##  - the hips pivot toward the nose and the weight moves over the front foot as he drops down the face;
##  - the head and chest lead each turn;
##  - both legs are solved with a two-bone solver so the feet stay planted on the deck whatever the hips do;
##  - both arms are solved the same way toward hand targets that swing with the turn (trailing hand low in a bottom
##    turn, arms wide and up in a top turn, forward and down when dropping, a little sway all the time).
## In the model's own space: -X is the nose (down the line), -Z is the chest (toward the wave), +Y is up.

const MODEL := "res://assets/models/surfer.glb"
const BASE_POSE := "trim"
## Seconds for a pose weight to close most of the way to its target.
const BLEND_TIME := 0.12
## How much the board tilts with the wave face (0 flat to the sea, 1 flush with the face).
const FACE_ALIGN := 0.55
## Bones that lead a turn, root to tip, and how much of the lead each takes.
const LEAD_BONES := [["spine02", 0.15], ["spine01", 0.2], ["neck01", 0.15], ["neck02", 0.15], ["head", 0.3]]
## Hip pivot toward the nose when the nose points straight down the face, radians, and the weight shift over the front foot, meters.
const DIVE_YAW := 1.0
const DIVE_SHIFT := 0.12
const LEGS := [["upperleg02.L", "lowerleg01.L", "foot.L", -1.0], ["upperleg02.R", "lowerleg01.R", "foot.R", 1.0]]
const ARMS := [["upperarm02.L", "lowerarm01.L", "wrist.L", -1.0], ["upperarm02.R", "lowerarm01.R", "wrist.R", 1.0]]

var material := ShaderMaterial.new()
var skeleton: Skeleton3D
var _poses := {}  # pose name -> {bone index -> [position, rotation]}
var _targets := {}
var _weights := {}
var _lead := 0.0  # radians the head and chest are already turned into the coming move
var _dive := 0.0  # 0 to 1: how far the nose points down the face
var _tuck := 0.0  # 0 to 1: the back knee drops in toward the front leg
var _hand_offset := {-1.0: Vector3.ZERO, 1.0: Vector3.ZERO}
var _clock := 0.0
var _foot_target := {}  # side -> where the ankle stays, in the model's space (found from the trim pose)
var _foot_basis := {}   # side -> how the foot sits flat on the deck, in skeleton space
var _hand_rest := {}    # side -> where the hand rests in the trim pose, in the model's space


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
	var to_model := _skeleton_to_model()
	for leg in LEGS:
		var foot := skeleton.find_bone(leg[2])
		_foot_target[leg[3]] = to_model * skeleton.get_bone_global_pose(foot).origin
		_foot_basis[leg[3]] = skeleton.get_bone_global_pose(foot).basis
	for arm in ARMS:
		_hand_rest[arm[3]] = to_model * skeleton.get_bone_global_pose(skeleton.find_bone(arm[2])).origin
	_pose_body()


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
	_clock += delta
	var k := 1.0 - exp(-delta / BLEND_TIME)
	for pose_name: String in _weights:
		_weights[pose_name] = lerpf(_weights[pose_name], _targets[pose_name], k)
	_apply()
	_pose_body()


## Stands the surfer on the wave at (d, u), heading down the line, the board tilted part-way to the face.
func stand_on(model: WaveModel, d: float, u: float) -> void:
	_place(model, d, u, 0.0, 0.0)


## Drives the surfer from the rider's physical state: where he is and which way his nose points, the board rolled
## onto its rail by the turn, the baked poses blended by how he is moving, and the hips, arms and head following.
func follow(rider: Rider, model: WaveModel, delta: float) -> void:
	_place(model, rider.d, rider.u, rider.theta, rider.rail_roll)
	var bottom := clampf(rider.omega / 2.2, 0.0, 1.0) * clampf(1.0 - rider.u, 0.2, 1.0)
	var top := clampf(-rider.omega / 2.0, 0.0, 1.0) * clampf(rider.u, 0.3, 1.0)
	var barrel := model.barrel_amount_at(rider.d, rider.u)
	_dive = clampf(-rider.theta / 0.9, 0.0, 1.0)
	# Dropping down the face sinks the hips over the front foot like a crouch; so does a deep carve.
	var crouch := clampf(rider.compression + 0.35 * _dive, 0.0, 1.0) * (1.0 - barrel * 0.5)
	# The poses are layered on the trim pose; keep their total at one so no joint is pushed past a baked pose.
	var total := bottom + top + crouch
	var scale := 1.0 / maxf(total, 1.0)
	set_target("bottom_turn", bottom * scale)
	set_target("top_turn", top * scale)
	set_target("crouch", crouch * scale)
	_lead = rider.lead
	_tuck = maxf(bottom, clampf(barrel, 0.0, 1.0))
	_set_hand_offsets(bottom, top, crouch)
	step(delta)


## Where each hand wants to be, as a shift from its rest position in the model's space (-X nose, +Y up, -Z toward the wave).
func _set_hand_offsets(bottom: float, top: float, crouch: float) -> void:
	var sway := Vector3(sin(_clock * 1.3), sin(_clock * 1.7 + 1.0), sin(_clock * 0.9 + 2.0)) * 0.025
	var left := sway + Vector3(0.0, -0.12, -0.08) * crouch + Vector3(-0.15, -0.10, -0.15) * _dive
	var right := -sway + Vector3(0.0, -0.12, -0.08) * crouch + Vector3(-0.05, -0.15, -0.10) * _dive
	# Bottom turn: the front hand reaches down toward the rail, the trailing hand drops back toward the water.
	left += Vector3(-0.10, -0.25, -0.10) * bottom
	right += Vector3(0.25, -0.12, 0.05) * bottom
	# Top turn: arms open wide and up for leverage.
	left += Vector3(-0.25, 0.25, 0.0) * top
	right += Vector3(0.30, 0.35, 0.05) * top
	# The arms counter-swing against the head and chest as they lead.
	left += Vector3(-0.18, 0.0, 0.0) * _lead
	right += Vector3(0.18, 0.0, 0.0) * _lead
	_hand_offset[-1.0] = left
	_hand_offset[1.0] = right


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


## Blends the baked poses into the bones and adds the head-and-chest lead.
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


## Pivots the hips toward the nose and shifts the weight forward, then plants the feet and reaches the hands.
func _pose_body() -> void:
	var to_model := _skeleton_to_model()
	var to_skeleton := to_model.affine_inverse()
	_apply_hips(to_model)
	for leg in LEGS:
		var side: float = leg[3]
		var target: Vector3 = _foot_target[side]
		# The knees point toward the wave and the nose; the back knee tucks in toward the front leg in a deep turn.
		var knee_dir := Vector3(-0.1 - (_tuck * 0.5 if side > 0.0 else 0.0), 0.4, -0.9)
		_solve_two_bone(leg[0], leg[1], leg[2], to_skeleton * target, to_skeleton * (target + knee_dir))
		var foot := skeleton.find_bone(leg[2])
		skeleton.set_bone_pose_rotation(foot, _local_rotation(foot, _foot_basis[side]))
	for arm in ARMS:
		var side: float = arm[3]
		var shoulder_model: Vector3 = to_model * skeleton.get_bone_global_pose(skeleton.find_bone(arm[0])).origin
		var hand: Vector3 = _hand_rest[side] + _hand_offset[side]
		var elbow_dir := Vector3(side * 0.25, -0.15, 0.55)
		_solve_two_bone(arm[0], arm[1], arm[2], to_skeleton * hand, to_skeleton * (shoulder_model + elbow_dir))


func _apply_hips(to_model: Transform3D) -> void:
	var root := skeleton.find_bone("root")
	if root < 0 or _dive < 0.001:
		return
	var up := (to_model.basis.inverse() * Vector3.UP).normalized()
	var swing := Basis(up, _dive * DIVE_YAW)  # positive turns the chest from the wave toward the nose
	var global := skeleton.get_bone_global_pose(root)
	var pivot := (skeleton.get_bone_global_pose(skeleton.find_bone("upperleg02.L")).origin + skeleton.get_bone_global_pose(skeleton.find_bone("upperleg02.R")).origin) / 2.0
	var shift := to_model.basis.inverse() * (Vector3(-DIVE_SHIFT, -0.04, 0.0) * _dive)
	var turned := Transform3D(swing * global.basis, pivot + swing * (global.origin - pivot) + shift)
	skeleton.set_bone_pose_position(root, turned.origin)
	skeleton.set_bone_pose_rotation(root, turned.basis.get_rotation_quaternion())


## Turns the neck, head and upper back about the vertical, so the surfer looks and torques into a turn before the
## board has come round. Bones are visited root to tip so each sees its parent's final pose.
func _apply_lead() -> void:
	if absf(_lead) < 0.001:
		return
	for entry in LEAD_BONES:
		var bone := skeleton.find_bone(entry[0])
		if bone < 0:
			continue
		var world_twist := Basis(Vector3.UP, -_lead * entry[1])
		var parent := skeleton.get_bone_parent(bone)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
		var local_twist := parent_basis.inverse() * world_twist * parent_basis
		skeleton.set_bone_pose_rotation(bone, local_twist.get_rotation_quaternion() * skeleton.get_bone_pose_rotation(bone))


## Two-bone solver: bends root, middle and tip joints (all positions in the skeleton's space) so the tip reaches the
## target, with the middle joint (knee or elbow) pushed toward the pole point.
func _solve_two_bone(root: String, middle: String, tip: String, target: Vector3, pole: Vector3) -> void:
	var r := skeleton.find_bone(root)
	var m := skeleton.find_bone(middle)
	var t := skeleton.find_bone(tip)
	if r < 0 or m < 0 or t < 0:
		return
	var a := skeleton.get_bone_global_pose(r).origin
	var b := skeleton.get_bone_global_pose(m).origin
	var c := skeleton.get_bone_global_pose(t).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var to_target := target - a
	var reach := clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to_target.normalized()
	var along := (l1 * l1 - l2 * l2 + reach * reach) / (2.0 * reach)
	var bend := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var pole_dir := pole - a
	pole_dir = (pole_dir - dir * pole_dir.dot(dir)).normalized()
	_aim(r, b, a + dir * along + pole_dir * bend)
	_aim(m, skeleton.get_bone_global_pose(t).origin, a + dir * reach)


## Rotates a bone about its own joint so that the point `from` moves to the line toward `to`.
func _aim(bone: int, from: Vector3, to: Vector3) -> void:
	var global := skeleton.get_bone_global_pose(bone)
	var v1 := from - global.origin
	var v2 := to - global.origin
	if v1.length() < 0.001 or v2.length() < 0.001:
		return
	v1 = v1.normalized()
	v2 = v2.normalized()
	if v1.dot(v2) > 0.99999:
		return
	var turned := Basis(Quaternion(v1, v2)) * global.basis
	skeleton.set_bone_pose_rotation(bone, _local_rotation(bone, turned))


## The local rotation that gives a bone the wanted orientation in the skeleton's space.
func _local_rotation(bone: int, wanted: Basis) -> Quaternion:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	return (parent_basis.inverse() * wanted).get_rotation_quaternion()


## How points in the skeleton's space map into this node's (the model's) space.
func _skeleton_to_model() -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = skeleton
	while n != self and n != null:
		t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


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
