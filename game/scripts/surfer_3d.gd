class_name Surfer3D
extends Node3D
## The real-time surfer: a skinned model (tools/foundry/export_surfer_glb.py makes surfer.glb) that lives inside the
## wave's own 3D stage, so the lip and the mist can pass in front of him and the camera can move around him.
##
## The board and the body move separately, as in the J-Bay footage: the board lies on the water and rolls onto its rail,
## while the body balances over it, its axis along the rider's `balance` (from the feet to the centre of mass), and the
## legs take up the difference. So the board can swing up and down a steep face while he stays close to upright.
##
## Baked poses (one-frame animations, board level) give the body its overall shape: spine, hips, head. They are never
## played; the bones are blended by weights that follow their targets on a short spring, so any pose can be interrupted.
## On top of that the body is driven from the rider's physical state:
##  - the whole body tilts over the feet to the balance direction;
##  - the hips pivot toward the nose and the weight moves over the front foot as he drops down the face;
##  - the lead chain (the J-Bay and Ethan Ewing footage): the front (left) arm points where he is about to go, the head
##    looks there with it, the chest follows, then the hips and the board;
##  - the back (right) arm is the anchor: its forearm runs along the board, hand toward the nose; it swings out behind
##    as a counterweight while he extends, over his head along the board at the lip, and drags in the water (throwing
##    spray) in a big bottom turn;
##  - in the heart of a deep bottom turn the torso folds over until the head is down by the hips;
##  - on a floater both arms push forward over the nose;
##  - the two moves off the top follow the gold-standard slow-motion clip (storyboardimages/move_refs, docs/balance.md
##    "Gold standard"): hitting the lip, the front arm reaches up the board as he climbs, goes straight up over his head
##    as the board pivots on its tail while the back arm holds out level behind and he sits back over the tail, then
##    comes down to point where he drops; in a cutback the back arm points out behind as he rises, goes straight up as
##    the front hand reaches down to the rail by the front foot in the turn-in, then sweeps forward over the nose as his
##    body opens to the beach and the front hand trails by the water; facing back he stands tall pointing the front arm
##    at the whitewater; and as the foam knocks the board back his head swings round first and he folds over the front
##    knee, the front hand reaching down toward where he is going and the back elbow up;
##  - both legs and both arms are solved with a two-bone solver, so the feet stay planted whatever the hips do.
## In the model's own space: -X is the nose (down the line), -Z is the chest (toward the wave), +Y is up.

const MODEL := "res://assets/models/surfer.glb"
const BASE_POSE := "trim"
const PALM_PRINT := "res://assets/textures/palm_print.png"
## Seconds for a pose weight to close most of the way to its target.
const BLEND_TIME := 0.12
## The lead chain: seconds for the front arm, the head and the chest to close most of the way on a new heading. The
## centre of mass (the rider's lean) and then the board come after.
const ARM_LEAD_TIME := 0.06
const HEAD_LEAD_TIME := 0.09
const CHEST_LEAD_TIME := 0.22
## Chest and head bones that turn into the coming move, root to tip, and how much of the lead each takes.
const CHEST_BONES := [["spine02", 0.2], ["spine01", 0.25]]
const HEAD_BONES := [["neck01", 0.3], ["neck02", 0.3], ["head", 0.4]]
## He looks at a spot this far ahead of the nose (meters, about one and a half boards) along the way he is about to go:
## up the face in a bottom turn, down it at the lip; never down at the water at his feet. The head and neck turn at
## most this far (radians) from where the pose has them.
const LOOK_AHEAD := 2.8
const LOOK_MAX := 1.3
## The board sits this far forward under him (meters), so his front foot is where the orange stripe meets the yellow
## and his back foot where the aqua meets the white tail; its nose and tail, in the model's space.
const BOARD_SHIFT := 0.19
## On a floater the board rides up onto the top of the wave: this much of the way from the face toward the crest, and
## this much of the way from the face's tilt toward level.
const FLOAT_LIFT := 0.6
const FLOAT_LEVEL := 0.5
const BOARD_NOSE := Vector3(-0.95 - BOARD_SHIFT, 0.0, 0.0)
const BOARD_TAIL := Vector3(0.95 - BOARD_SHIFT, 0.0, 0.0)
## The front arm points along the heading he is asked for, this much down the wave (a share of straight down), never
## swung further than this from the nose (radians), reaching this far from the shoulder (meters).
const AIM_DOWN := 0.3
const AIM_SWING := 1.9
const POINT_REACH := 0.5
## In the heart of a deep bottom turn the torso folds over this far (radians, spread down the spine) toward the wave and
## a little toward the nose, so his head drops to his hips.
const FOLD_MAX := 0.6
const FOLD_TOWARD := Vector3(-0.35, 0.0, -0.94)
const FOLD_BONES := [["spine05", 0.3], ["spine04", 0.25], ["spine03", 0.2], ["spine02", 0.15], ["spine01", 0.1]]
## The gold standard's torso: hitting the lip he lays back toward the tail and a little toward the beach (LAYBACK, a
## share of FOLD_MAX, toward LAYBACK_TOWARD) as the board pivots; knocked back in a cutback he folds forward over the
## front knee (REBOUND_FOLD toward REBOUND_TOWARD).
const LAYBACK := 0.55
const LAYBACK_TOWARD := Vector3(0.94, 0.0, 0.34)
const REBOUND_FOLD := 0.9
## A whip stands the board's nose up this far (radians) over WHIP_TIME seconds, and lays him back toward the tail.
const WHIP_NOSE_UP := 0.55
const WHIP_TIME := 0.06
const REBOUND_TOWARD := Vector3(-0.9, 0.0, -0.44)
## Where the hands go in the two moves off the top (the gold standard). Relative to the shoulder, in his body's own
## frame (up along his balance, so "straight up" is over his head however the board is tilted on the face; -X toward
## the nose, -Z his chest): the front hand reaching up the board on the climb to the lip, straight up overhead in the
## snap, pointing along the nose facing back in a cutback; the back hand out level behind, straight up in a cutback's
## turn-in, low at his side facing back, the elbow up behind in the rebound. On the board (the model's space): the front
## hand on the rail by the front foot in the turn-in. Along the wave: in the carve the back arm sweeps out at head height
## the way he came (SWEEP_REACH along the line, SWEEP_LIFT up) and the front hand trails down by the water toward the
## curl (TRAIL_DOWN, TRAIL_BACK).
const LIP_REACH_HAND := Vector3(-0.42, 0.18, -0.12)
const ARM_UP := Vector3(-0.06, 0.6, 0.06)
const BACK_OUT := Vector3(0.56, 0.0, 0.1)
const BACK_UP := Vector3(0.04, 0.6, 0.06)
const SWEEP_REACH := 0.52
const SWEEP_LIFT := 0.18
const TRAIL_DOWN := 0.6
const TRAIL_BACK := 0.22
const BACK_LOW := Vector3(0.08, -0.48, 0.12)
const BACK_ELBOW_UP := Vector3(0.22, 0.2, 0.18)
const POINT_BACK := Vector3(-0.58, 0.02, 0.06)
const FRONT_RAIL := Vector3(-0.62, 0.05, 0.24)
## In a cutback he looks this far ahead of the board round the turn (radians), not all the way to where it ends.
const CUT_LOOK_LEAD := 0.9
## Seconds for the move weights to close most of the way: the rider's phases switch at once, the body does not.
const MOVE_BLEND := 0.1
const REBOUND_HOLD := 0.5            # ...and the fold after the foam knocks the board back eases off over this long
## In a full stall the board's nose lifts this far (radians), turning about the tail.
const NOSE_LIFT := 0.16
## In a big bottom turn the back hand trails in the water here (the model's space: behind the back foot, on the wave
## side, at the water) and throws spray while it is within this distance of the face (meters).
const DRAG_POINT := Vector3(0.62, -0.02, -0.42)
const DRAG_TOUCH := 0.25
## Hip pivot toward the nose when the nose points straight down the face, radians, and the weight shift over the front foot, meters.
const DIVE_YAW := 1.0
const DIVE_SHIFT := 0.12
## From just behind the back foot (the pivot of a turn) to the middle of the board, meters.
const PIVOT_TO_CENTRE := 0.48
## The board's half width at its middle, and how far under the surface its ends and rails may go (meters).
const BOARD_HALF_WIDTH := 0.25
const BOARD_DIP := 0.03
## How far the turning lean (radians) has to go for a turn pose to show fully.
const CARVE_FULL := 0.6
## How far the hips sink below the deepest baked pose when he is fully compressed, meters (the footage's drive along the
## bottom has the hips near knee height).
const HIP_SINK := 0.12
## Where the body's weight sits, as shares of a few joints (the legs and arms are left out: they bend around it).
const MASS := [["root", 0.4], ["spine03", 0.3], ["spine01", 0.2], ["head", 0.1]]
const LEGS := [["upperleg02.L", "lowerleg01.L", "foot.L", -1.0], ["upperleg02.R", "lowerleg01.R", "foot.R", 1.0]]
## Poses that take the hands and feet from the baked pose instead of the procedural arms and the deck: sitting astride
## the board in the lull (feet in the water, hands on the rails) and curled up in the tumble (arms round the head).
## While one shows, the balance tilt, the hip pivot, the fold, the lead chain and the head aim give way to it, and it
## eases in and out over FREE_BLEND_TIME (seconds), slower than the riding poses.
const FREE_POSES := ["sit", "tumble"]
const FREE_BLEND_TIME := 0.35
## The riding poses of step 12: how much of the snap pose shows while the board pivots at the lip, and of the air pose
## (knees drawn up under him) as he floats down after the release.
const SNAP_SHARE := 0.7
const AIR_SHARE := 0.6
const ARMS := [["upperarm02.L", "lowerarm01.L", "wrist.L", -1.0], ["upperarm02.R", "lowerarm01.R", "wrist.R", 1.0]]

var material := ShaderMaterial.new()
## His figure seen through the lip curtain, drawn as the next pass of `material`.
var veil := ShaderMaterial.new()
var skeleton: Skeleton3D
var _poses := {}  # pose name -> {bone index -> [position, rotation]}
var _targets := {}
var _weights := {}
var _arm_aim := Vector3(-0.96, -0.29, 0.0)  # where the front arm points, in the model's space
var _look_point := BOARD_NOSE + Vector3(-LOOK_AHEAD, 0.0, 0.0)  # where he is looking, in the model's space
var _barrel := 0.0  # 0 to 1: how deep in the tube he is (he makes himself small)
var _compact := 0.0  # 0 to 1: knees together, in the tube or round in a cutback
var _head_lead := 0.0  # radians the head is already turned into the coming move
var _chest_lead := 0.0  # ...and the chest, a little later
var _fold := 0.0  # 0 to 1: how far the torso folds over in a deep bottom turn
var _arm := {"point": 0.0, "wings": 0.0, "top": 0.0, "drag": 0.0, "floater": 0.0, "fold": 0.0, "barrel": 0.0,
	"lip_reach": 0.0, "lip_up": 0.0, "cut_rail": 0.0, "cut_sweep": 0.0, "cut_point": 0.0, "rebound": 0.0}  # what each arm is doing
var _move := {"lip_reach": 0.0, "lip_up": 0.0, "cut_rail": 0.0, "cut_sweep": 0.0, "cut_point": 0.0, "rebound": 0.0}  # the move phases, smoothed
var _layback := 0.0  # 0 to 1: laid back over the tail as the board pivots at the lip
var _whip := 0.0  # 0 to 1: the board stood up on its tail in a snap or a rebound
var _rebound_fold := 0.0  # 0 to 1: folded forward over the front knee as the board is knocked back
var _t_crest := Vector3.LEFT  # down the line, along the face here
var _t_face := Vector3.UP  # up the face here
## Where the back hand is dragging in the water (world position) and how much spray it throws, 0 to 1.
var hand_spray_point := Vector3.ZERO
var hand_spray := 0.0
var _dive := 0.0  # 0 to 1: how far the nose points down the face
var _tuck := 0.0  # 0 to 1: the back knee drops in toward the front leg
var _balance := Vector3.UP  # from the feet to the centre of mass, in the model's space
var _sink := 0.0  # 0 to 1: how far the hips sink toward the deck beyond the poses
var _driven := false  # true once follow() steps the pose each frame, so _process does not step it twice
var _clock := 0.0
var _foot_target := {}  # side -> where the ankle stays, in the model's space (found from the trim pose)
var _foot_basis := {}   # side -> how the foot sits flat on the deck, in skeleton space
var _hand_rest := {}    # side -> where the hand rests relative to its shoulder, in the model's space
var _free := 0.0        # 0 to 1: how far a free pose (sitting, the tumble) has taken over from riding
var _down_sit := 0.0    # what set_down() asked for
## Testing: hold this baked pose fully over whatever he is doing (capture.gd's pose: event, for the contact sheet of
## every pose); "" lets the ride pick the poses.
var held_pose := ""
var _down_curl := 0.0
var _pose_hand := {}    # free pose -> side -> [wrist, elbow] under that pose, in the model's space
var _pose_leg := {}     # free pose -> side -> [ankle, knee, foot basis in skeleton space] under that pose


func _init() -> void:
	material.shader = load("res://shaders/surfer3d.gdshader") as Shader
	veil.shader = load("res://shaders/surfer_veil.gdshader") as Shader
	material.next_pass = veil
	material.set_shader_parameter("palm_print", load(PALM_PRINT))
	var scene := (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(scene)
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = material
		(mesh as MeshInstance3D).layers = WaveStage.SURFER_LAYER  # (drawn by the wave's camera and, alone, into the spray's mask)
		if mesh.name == "Board":
			(mesh as MeshInstance3D).position.x -= BOARD_SHIFT
	skeleton = scene.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var player := scene.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for pose_name in player.get_animation_list():
		_poses[String(pose_name)] = _read_pose(player.get_animation(pose_name))
		_weights[String(pose_name)] = 0.0
		_targets[String(pose_name)] = 0.0
	player.get_parent().remove_child(player)
	player.free()
	# The exporter leaves out the bones a pose keeps at rest; fill them in, so every pose (the base one above all) holds
	# every bone any pose moves, and the blend always covers it.
	var moved := {}
	for pose: Dictionary in _poses.values():
		moved.merge(pose)
	for pose: Dictionary in _poses.values():
		for bone: int in moved:
			if not pose.has(bone):
				pose[bone] = [skeleton.get_bone_rest(bone).origin, skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()]
	for pose_name: String in FREE_POSES:
		if _poses.has(pose_name):
			_measure_free_pose(pose_name)
	_apply()
	var to_model := _skeleton_to_model()
	for leg in LEGS:
		var foot := skeleton.find_bone(leg[2])
		_foot_target[leg[3]] = to_model * _global(foot).origin
		_foot_basis[leg[3]] = _global(foot).basis
	for arm in ARMS:
		_hand_rest[arm[3]] = Vector3(arm[3] * 0.22, -0.40, -0.12)  # hanging relaxed (the baked right arm points up, so it is not used)
	_pose_body()


func pose_names() -> Array:
	return _poses.keys()


## Down in the water (world.gd, from RideCycle): sitting astride the board through the lull, curled up in the tumble.
## The riding poses give way to them from the next follow(). Call it every frame (with zeros while riding).
func set_down(sit: float, curl: float) -> void:
	_down_sit = clampf(sit, 0.0, 1.0)
	_down_curl = clampf(curl, 0.0, 1.0)


func _apply_down() -> void:
	var riding := 1.0 - maxf(_down_sit, _down_curl)
	for pose_name: String in _targets:
		if not pose_name in FREE_POSES:
			_targets[pose_name] *= riding
	set_target("sit", _down_sit)
	set_target("tumble", _down_curl)
	if held_pose != "":
		for pose_name: String in _targets:
			_targets[pose_name] = 1.0 if pose_name == held_pose else 0.0


## Sets how strongly a pose should show (0 to 1); the surfer eases toward it. The base pose is always underneath.
func set_target(pose_name: String, weight_value: float) -> void:
	if _targets.has(pose_name):
		_targets[pose_name] = clampf(weight_value, 0.0, 1.0)


func target(pose_name: String) -> float:
	return _targets.get(pose_name, 0.0)


func weight(pose_name: String) -> float:
	return _weights.get(pose_name, 0.0)


func _process(delta: float) -> void:
	if not _driven:
		step(delta)


## Moves the pose weights toward their targets by `delta` seconds and re-poses the bones.
func step(delta: float) -> void:
	_clock += delta
	var k := 1.0 - exp(-delta / BLEND_TIME)
	var k_free := 1.0 - exp(-delta / FREE_BLEND_TIME)
	_free = 0.0
	for pose_name: String in _weights:
		var free := pose_name in FREE_POSES
		_weights[pose_name] = lerpf(_weights[pose_name], _targets[pose_name], k_free if free else k)
		if free:
			_free += _weights[pose_name]
	_free = minf(_free, 1.0)
	_apply()
	_pose_body()


## Stands the surfer on the wave at (d, u), heading down the line, the board flat on the face and the body upright.
func stand_on(model: WaveModel, d: float, u: float) -> void:
	_place(model, d, u, 0.0, 0.0)
	_balance = (transform.basis.inverse() * Vector3.UP).normalized()


## Drives the surfer from the rider's physical state: where he is and which way his nose points, the board rolled
## onto its rail, the body balanced over it, the baked poses blended by how he is moving, and the arms and head following.
func follow(rider: Rider, model: WaveModel, delta: float) -> void:
	_driven = true
	# A floater: high on the face, running along it, not turning hard.
	var floater := smoothstep(0.86, 0.94, rider.u) * (1.0 - clampf(absf(rider.theta) / 0.5, 0.0, 1.0)) * (1.0 - clampf(absf(rider.omega) / 1.5, 0.0, 1.0))
	# A whip (the snap at the lip, the cutback's rebound) stands the board up on its tail: nose high, his weight over the
	# back foot, pivoting against it.
	var whip := 1.0 if rider.snapping or rider.rebounding else 0.0
	_whip = lerpf(_whip, whip, 1.0 - exp(-delta / WHIP_TIME))
	_place(model, rider.d, rider.u, rider.theta, rider.rail_roll, maxf(rider.stall * NOSE_LIFT, _whip * WHIP_NOSE_UP), floater)
	_balance = (transform.basis.inverse() * rider.balance).normalized()
	# Turn poses come from the lean that turns him: toward the wave low on the face (bottom turn), toward the beach
	# high on it (top turn). The bottom turn's deep hip hinge also shows when he is deeply compressed low on the face,
	# which is the moment just before the turn (the footage's drive along the bottom).
	var hinge := maxf(clampf(rider.carve / CARVE_FULL, 0.0, 1.0) * 0.6, clampf((rider.compression - 0.3) / 0.4, 0.0, 1.0))
	var bottom := hinge * clampf(1.0 - rider.u, 0.2, 1.0)
	var top := clampf(-rider.carve / CARVE_FULL, 0.0, 1.0) * clampf(rider.u, 0.3, 1.0)
	var barrel := model.barrel_amount_at(rider.d, rider.u)
	_dive = clampf(-rider.theta / 0.9, 0.0, 1.0)
	var crouch := rider.compression * (1.0 - barrel * 0.5)
	# The gold standard's lip hit: sitting back over the tail, chest open, as the board pivots; then the knees come up
	# under him as he floats down. In the tube he is compact; on a floater taller, weight centred.
	var snapping := 1.0 if rider.snapping else 0.0
	var snap := snapping * SNAP_SHARE
	var air := rider.afloat * (1.0 - snapping) * AIR_SHARE
	# The poses are layered on the trim pose; keep their total at one so no joint is pushed past a baked pose.
	var total := bottom + top + crouch + snap + air + barrel + floater
	var scale := 1.0 / maxf(total, 1.0)
	set_target("bottom_turn", bottom * scale)
	set_target("top_turn", top * scale)
	set_target("crouch", crouch * scale)
	set_target("snap", snap * scale)
	set_target("air", air * scale)
	set_target("barrel", barrel * scale)
	set_target("floater", floater * scale)
	_sink = rider.compression
	_fold = smoothstep(0.45, 0.9, rider.compression) * clampf((1.0 - rider.u) / 0.5, 0.0, 1.0) * (1.0 - barrel * 0.5)
	_follow_moves(rider, delta)
	_layback = maxf(_move.lip_up * smoothstep(0.6, 0.85, rider.u), _whip)
	_rebound_fold = _move.rebound * (1.0 - _whip)
	# In the tube, settling by the curl, and knocked back in a cutback, he makes himself compact: the knees come together.
	_compact = maxf(maxf(barrel, _move.rebound * 0.8), rider.tuck * 0.7)
	_tuck = maxf(bottom, _compact)
	_barrel = barrel
	_follow_lead(rider, delta)
	_set_arms(rider, top, crouch)
	_arm.floater = floater * (1.0 - _arm.top)
	_apply_down()
	step(delta)
	_find_hand_drag(model, rider)


## The lead chain. The front arm swings first to point along the heading he is asked for (a little down the wave), the
## head turns with it, the chest follows a beat later; the rider's lean and then the board come after.
func _follow_lead(rider: Rider, delta: float) -> void:
	var aim_world := (_t_crest * cos(rider.aim) + _t_face * sin(rider.aim)).normalized() + Vector3.DOWN * AIM_DOWN
	var aim := (transform.basis.inverse() * aim_world).normalized()
	# Keep it where an arm can point: never swung further than AIM_SWING from the nose (0 is the nose, positive the wave).
	var yaw := clampf(atan2(-aim.z, -aim.x), -AIM_SWING, AIM_SWING)
	var flat := Vector2(aim.x, aim.z).length()
	aim = Vector3(-cos(yaw) * flat, aim.y, -sin(yaw) * flat).normalized()
	_arm_aim = _arm_aim.slerp(aim, 1.0 - exp(-delta / ARM_LEAD_TIME)).normalized()
	# The head looks where the front arm points, at a spot on the face ahead of the nose; carving round a cutback, a
	# little ahead of the board round the turn, where it is going next.
	var looking := rider.aim
	if rider.cutting_back and not rider.rebounding:
		looking = maxf(rider.theta - CUT_LOOK_LEAD, -Rider.CUTBACK_REACH)
	var ahead := (transform.basis.inverse() * (_t_crest * cos(looking) + _t_face * sin(looking))).normalized()
	var look_yaw := clampf(atan2(-ahead.z, -ahead.x), -AIM_SWING, AIM_SWING)
	var look := BOARD_NOSE + Vector3(-cos(look_yaw), clampf(ahead.y, -0.5, 0.5), -sin(look_yaw)) * LOOK_AHEAD
	_look_point = _look_point.lerp(look, 1.0 - exp(-delta / HEAD_LEAD_TIME))
	_head_lead = lerpf(_head_lead, rider.lead, 1.0 - exp(-delta / HEAD_LEAD_TIME))
	_chest_lead = lerpf(_chest_lead, rider.lead, 1.0 - exp(-delta / CHEST_LEAD_TIME))


## What each arm is doing, as weights the arm solver blends in _place_hands(). Read from the footage:
##  - point: the front arm points into the coming move, the more the further the board still has to turn;
##  - wings: extending out of a turn, climbing, or light, the arms spread (the back one out behind as a counterweight);
##  - top: at the lip and in a top turn the back arm goes over the head with its forearm along the board;
##  - drag: in a big bottom turn, deep and carving, the back hand trails in the water;
##  - fold: deep in the bottom turn the front hand reaches down toward the nose rail;
##  - floater: riding along the top, the front arm pushes forward over the nose and the back arm reaches out behind;
##  - barrel: deep in the tube he makes himself small, both arms forward, the back forearm along the board.
func _set_arms(rider: Rider, top: float, crouch: float) -> void:
	var climbing := clampf(rider.theta / 0.5, 0.0, 1.0)
	var extending := clampf(-rider.compression_vel / 0.5, 0.0, 1.0)
	_arm.point = 0.3 + 0.7 * clampf(absf(rider.aim - rider.theta) / 0.4, 0.0, 1.0)
	_arm.wings = maxf(maxf(climbing, extending), clampf((0.9 - rider.load_g) / 0.3, 0.0, 1.0)) * (1.0 - crouch)
	_arm.top = maxf(top, smoothstep(0.75, 0.92, rider.u) * clampf(-rider.omega / 1.5, 0.0, 1.0))
	_arm.drag = clampf((rider.carve - 0.25) / 0.3, 0.0, 1.0) * smoothstep(0.4, 0.65, rider.compression) * clampf((0.65 - rider.u) / 0.25, 0.0, 1.0)
	_arm.fold = _fold
	_arm.barrel = _barrel
	for phase: String in _move:
		_arm[phase] = _move[phase]
	# (coming down after hitting the lip, the front arm points where he drops; the carved top turn's back arm over the head
	# gives way to the gold standard's moves)
	_arm.point = maxf(_arm.point, rider.afloat * (1.0 - _move.lip_up))
	_arm.top *= 1.0 - maxf(_move.lip_up, maxf(_move.cut_rail, _move.cut_sweep))


## The phases of the two moves off the top, from the rider's state, each eased in and out over MOVE_BLEND so the
## body never snaps between them (the gold standard, docs/balance.md):
##  - lip_reach: driving steeply up into the lip, the front arm reaches up the board;
##  - lip_up: at the lip as the board pivots, the front arm straight up and the back arm out level behind; it holds
##    while he is still up there coming round;
##  - cut_rail, cut_sweep, cut_point: a cutback's turn-in, carve and facing back, by how far round the board is;
##  - rebound: the foam knocking the board back.
func _follow_moves(rider: Rider, delta: float) -> void:
	var at_lip := maxf(1.0 if rider.snapping else 0.0, rider.release)
	var want := {
		"lip_reach": smoothstep(0.5, 0.8, rider.u) * clampf((rider.theta - 0.7) / 0.4, 0.0, 1.0) * (1.0 - at_lip),
		"lip_up": maxf(at_lip, rider.afloat * smoothstep(0.65, 0.88, rider.u)),
		"cut_rail": 0.0, "cut_sweep": 0.0, "cut_point": 0.0,
		"rebound": 1.0 if rider.rebounding else 0.0,
	}
	if (rider.cutting_back or rider.cutback_coming) and not rider.rebounding:
		var round := smoothstep(-0.4, -1.1, rider.theta)
		var back := smoothstep(-1.9, -2.4, rider.theta)
		want.cut_rail = 1.0 - round
		want.cut_sweep = round * (1.0 - back)
		want.cut_point = back
	var k := 1.0 - exp(-delta / MOVE_BLEND)
	for phase: String in _move:
		# (knocked back off the foam he stays folded a moment after the board has come round, compact in the foam)
		var easing := k if phase != "rebound" or want[phase] > _move[phase] else 1.0 - exp(-delta / REBOUND_HOLD)
		_move[phase] = lerpf(_move[phase], want[phase], easing)


## The board: on the face, its nose along the heading, rolled about its own length onto a rail (positive puts the
## toe-side rail, the one nearest the wave, down, so the deck faces into a bottom turn).
## `nose_up` lifts the nose (radians) about the tail, as in a stall.
func _place(model: WaveModel, d: float, u: float, theta: float, roll: float, nose_up := 0.0, lift := 0.0) -> void:
	var normal := model.surface_normal(d, u).normalized().slerp(Vector3.UP, lift * FLOAT_LEVEL)
	var t_crest := Vector3(-1.0, 0.0, 0.0)  # down the line
	var t_face := t_crest.cross(normal).normalized()  # up the face, toward the lip (and into the wave)
	t_crest = normal.cross(t_face).normalized()
	_t_crest = t_crest
	_t_face = t_face
	var forward := (t_crest * cos(theta) + t_face * sin(theta)).normalized()
	# The model's nose points down its -X and its chest toward -Z; its +X is the tail.
	var along := -forward
	var basis := Basis(along, normal, along.cross(normal)) * Basis(Vector3.RIGHT, -roll) * Basis(Vector3.BACK, -nose_up)
	# The board turns about the back foot, like a pivot turn: the tail stays on the spot being ridden and the nose
	# swings round to point where he is going, so the board centre sits ahead of the pivot along the board.
	var pivot := model.surface_point(d, u).lerp(model.crest_point(d), lift * FLOAT_LIFT)
	transform = Transform3D(basis, pivot - basis.x * PIVOT_TO_CENTRE)
	# Fibreglass floats: a straight board on a concave face, rolled onto its rail or pitched, would cut into the water
	# at its ends, so lift it along the face's normal until no end or rail is more than BOARD_DIP under.
	var dip := 0.0
	var face_length := maxf(model.face_length_at(d, u), 0.5)
	for corner: Vector3 in [BOARD_NOSE, BOARD_TAIL, Vector3(-BOARD_SHIFT, 0.0, BOARD_HALF_WIDTH), Vector3(-BOARD_SHIFT, 0.0, -BOARD_HALF_WIDTH)]:
		var p := transform * corner
		var off := p - pivot
		var d_p := d + off.dot(t_crest)
		var u_p := clampf(u + off.dot(t_face) / face_length, 0.0, 1.0)
		var q := model.surface_point(d_p, u_p)
		dip = maxf(dip, (q - p).dot(model.surface_normal(d_p, u_p)) - BOARD_DIP)
	if dip > 0.0:
		transform.origin += normal * dip


## Blends the baked poses into the bones and adds the head-and-chest lead.
func _apply() -> void:
	_apply_baked()
	_apply_lead()


## Blends the baked poses into the bones.
func _apply_baked() -> void:
	var base: Dictionary = _poses.get(BASE_POSE, {})
	# (only the poses showing: every pose holds every bone, so looping them all costs a lot each frame)
	var showing: Array[Dictionary] = []
	var weights: Array[float] = []
	for pose_name: String in _weights:
		var w: float = _weights[pose_name]
		if w > 0.001 and pose_name != BASE_POSE:
			showing.append(_poses[pose_name])
			weights.append(w)
	for bone: int in base:
		var bone_position: Vector3 = base[bone][0]
		var bone_rotation: Quaternion = base[bone][1]
		for k in showing.size():
			var held: Array = showing[k][bone]
			bone_position = bone_position.lerp(held[0], weights[k])
			bone_rotation = bone_rotation.slerp(held[1], weights[k])
		skeleton.set_bone_pose_position(bone, bone_position)
		skeleton.set_bone_pose_rotation(bone, bone_rotation)


## Where a free pose puts the wrists, elbows, ankles and knees (the model's space), so they can be reached for while
## the pose blends in.
func _measure_free_pose(pose_name: String) -> void:
	_weights[pose_name] = 1.0
	_apply_baked()
	var to_model := _skeleton_to_model()
	_pose_hand[pose_name] = {}
	_pose_leg[pose_name] = {}
	for arm in ARMS:
		_pose_hand[pose_name][arm[3]] = [to_model * _global(skeleton.find_bone(arm[2])).origin, to_model * _global(skeleton.find_bone(arm[1])).origin]
	for leg in LEGS:
		var foot := skeleton.find_bone(leg[2])
		_pose_leg[pose_name][leg[3]] = [to_model * _global(foot).origin, to_model * _global(skeleton.find_bone(leg[1])).origin, _global(foot).basis]
	_weights[pose_name] = 0.0


## Pivots the hips toward the nose, balances the body over the feet, then plants the feet and reaches the hands.
func _pose_body() -> void:
	var to_model := _skeleton_to_model()
	var to_skeleton := to_model.affine_inverse()
	_apply_hips(to_model)
	var sink := _sink * (1.0 - _free)
	if sink > 0.001:  # the knees take it: the leg solver below bends them to keep the feet on the deck
		var root := skeleton.find_bone("root")
		skeleton.set_bone_pose_position(root, skeleton.get_bone_pose_position(root) + to_skeleton.basis * Vector3(0.0, -HIP_SINK * sink, 0.0))
	_apply_fold(to_skeleton)
	_apply_balance(to_model)
	for leg in LEGS:
		var side: float = leg[3]
		var target: Vector3 = _foot_target[side]
		# The knees point toward the wave and the nose; the back knee tucks in toward the front leg in a deep turn.
		# In the tube the knees also come together, front knee back and back knee forward, to make him small.
		var knee_dir := Vector3(-0.1 - (_tuck * 0.5 if side > 0.0 else -0.45 * _compact), 0.4, -0.9)
		var pole := target + knee_dir
		var sole: Basis = _foot_basis[side]
		for pose_name: String in _pose_leg:  # sitting, the feet hang in the water where the pose has them
			var w: float = _weights[pose_name]
			if w > 0.001:
				var leg_pose: Array = _pose_leg[pose_name][side]
				target = target.lerp(leg_pose[0], w)
				pole = pole.lerp(leg_pose[1], w)
				sole = sole.slerp(leg_pose[2], w)
		_solve_two_bone(leg[0], leg[1], leg[2], to_skeleton * target, to_skeleton * pole)
		var foot := skeleton.find_bone(leg[2])
		skeleton.set_bone_pose_rotation(foot, _local_rotation(foot, sole))
	_place_hands(to_model, to_skeleton)
	_aim_head(to_model)


## The board's tail and the front foot, in the world (the spray comes off both).
func tail_point() -> Vector3:
	return transform * BOARD_TAIL


func front_foot_point() -> Vector3:
	return transform * (_skeleton_to_model() * _global(skeleton.find_bone("foot.L")).origin)


## Solves both arms toward their hand targets, from the weights set in _set_arms(). Hands are placed relative to their
## shoulders (so crouching and twisting never stretch the arms), in the model's space (-X nose, +Y up, -Z the wave).
func _place_hands(to_model: Transform3D, to_skeleton: Transform3D) -> void:
	var sway := Vector3(sin(_clock * 1.3), sin(_clock * 1.7 + 1.0), sin(_clock * 0.9 + 2.0)) * 0.025
	var chest_turn := Basis(Vector3.UP, _dive * DIVE_YAW)
	var body := _body_frame()
	var line := (transform.basis.inverse() * _t_crest)  # down the line, the way he came before a cutback
	line = (line - body.y * line.dot(body.y)).normalized()
	for arm in ARMS:
		var side: float = arm[3]
		var shoulder: Vector3 = to_model * _global(skeleton.find_bone(arm[0])).origin
		var hand: Vector3
		var elbow: Vector3
		if side < 0.0:  # the front arm leads
			hand = chest_turn * (_hand_rest[side] + sway + Vector3(-0.12, -0.10, -0.12) * _sink)
			hand = hand.lerp(_arm_aim * POINT_REACH, _arm.point)
			hand = hand.lerp(Vector3(-0.34, -0.14, -0.02), _arm.wings * (1.0 - _arm.point) * 0.7)
			hand = hand.lerp(Vector3(-0.30, -0.55, -0.25), _arm.fold)
			hand = hand.lerp(Vector3(-0.48, -0.12, -0.14), _arm.floater)
			hand = hand.lerp(Vector3(-0.45, -0.28, -0.18), _arm.barrel)
			elbow = Vector3(-0.25, -0.15, 0.55)
			hand = hand.lerp(body * LIP_REACH_HAND, _arm.lip_reach)
			hand = hand.lerp(body * ARM_UP, _arm.lip_up)
			elbow = elbow.lerp(body * Vector3(-0.2, 0.3, 0.4), _arm.lip_up)
			hand = hand.lerp(FRONT_RAIL - shoulder, _arm.cut_rail)
			hand = hand.lerp(-body.y * TRAIL_DOWN - line * TRAIL_BACK, _arm.cut_sweep)
			hand = hand.lerp(body * POINT_BACK, _arm.cut_point)
			hand = hand.lerp(_arm_aim * 0.45 - body.y * 0.4, _arm.rebound)
		else:  # the back arm is the anchor
			hand = chest_turn * (Vector3(-0.08, -0.40, -0.24) - sway)
			elbow = Vector3(0.45, -0.10, 0.35)
			hand = hand.lerp(Vector3(0.52, -0.06, 0.04), _arm.wings)
			elbow = elbow.lerp(Vector3(0.20, -0.25, 0.50), _arm.wings)
			hand = hand.lerp(Vector3(-0.06, 0.50, -0.02), _arm.top)
			elbow = elbow.lerp(Vector3(0.30, 0.50, 0.15), _arm.top)
			hand = hand.lerp(DRAG_POINT - shoulder, _arm.drag)
			elbow = elbow.lerp(Vector3(0.30, 0.20, 0.40), _arm.drag)
			hand = hand.lerp(Vector3(0.55, 0.05, 0.06), _arm.floater)
			elbow = elbow.lerp(Vector3(0.25, -0.20, 0.50), _arm.floater)
			hand = hand.lerp(Vector3(-0.35, -0.32, -0.20), _arm.barrel)
			elbow = elbow.lerp(Vector3(0.45, -0.10, 0.35), _arm.barrel)
			hand = hand.lerp(body * BACK_OUT, maxf(_arm.lip_reach, _arm.lip_up))
			elbow = elbow.lerp(body * Vector3(0.3, -0.2, 0.4), maxf(_arm.lip_reach, _arm.lip_up))
			hand = hand.lerp(body * BACK_UP, _arm.cut_rail)
			elbow = elbow.lerp(body * Vector3(0.25, 0.4, 0.3), _arm.cut_rail)
			hand = hand.lerp(line * SWEEP_REACH + body.y * SWEEP_LIFT, _arm.cut_sweep)
			elbow = elbow.lerp(line * 0.2 + body.y * 0.3 + body.z * 0.4, _arm.cut_sweep)
			hand = hand.lerp(body * BACK_LOW, _arm.cut_point)
			elbow = elbow.lerp(body * Vector3(0.35, -0.2, 0.35), _arm.cut_point)
			hand = hand.lerp(body * BACK_ELBOW_UP, _arm.rebound)
			elbow = elbow.lerp(body * Vector3(0.4, 0.4, 0.3), _arm.rebound)
		for pose_name: String in _pose_hand:  # sitting the hands rest on the rails; tumbling they hold the head
			var w: float = _weights[pose_name]
			if w > 0.001:
				hand = hand.lerp(_pose_hand[pose_name][side][0] - shoulder, w)
				elbow = elbow.lerp(_pose_hand[pose_name][side][1] - shoulder, w)
		_solve_two_bone(arm[0], arm[1], arm[2], to_skeleton * (shoulder + hand), to_skeleton * (shoulder + elbow))


## His body's own frame in the model's space: the board's frame tilted the way _apply_balance tilts his body (the
## shortest turn from the board's up to his balance), so up is along his balance, -X toward the nose and -Z his chest.
## With the board flat under an upright body it is the model's frame; with the board straight up the face at the lip
## and him upright, his up runs along the board and his chest still faces the wave.
func _body_frame() -> Basis:
	return Basis(Quaternion(Vector3.UP, _balance.normalized()))


## Folds the torso over, root to tip, so in a deep bottom turn the head drops toward the hips; the balance step after
## it moves the hips back to keep the weight over the feet.
func _apply_fold(to_skeleton: Transform3D) -> void:
	# (the bottom turn's fold toward the wave, the lip's lay-back toward the tail and the rebound's fold over the front
	# knee add up to one bend of the spine)
	var lean := FOLD_TOWARD.normalized() * _fold + LAYBACK_TOWARD.normalized() * _layback * LAYBACK + REBOUND_TOWARD.normalized() * _rebound_fold * REBOUND_FOLD
	var amount := minf(lean.length(), 1.0) * (1.0 - _free)
	if amount < 0.001:
		return
	var axis := (to_skeleton.basis * Vector3.UP.cross(lean.normalized())).normalized()
	for entry in FOLD_BONES:
		var bone := skeleton.find_bone(entry[0])
		if bone < 0:
			continue
		var parent_basis := _global(skeleton.get_bone_parent(bone)).basis
		var bend := Basis(axis, amount * FOLD_MAX * entry[1])
		skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * bend * parent_basis).get_rotation_quaternion() * skeleton.get_bone_pose_rotation(bone))


## Where the back hand is, and how much spray it throws: only while it is dragging and actually down at the face.
func _find_hand_drag(model: WaveModel, rider: Rider) -> void:
	hand_spray = 0.0
	if _arm.drag < 0.2:
		return
	var wrist: Vector3 = _skeleton_to_model() * _global(skeleton.find_bone("wrist.R")).origin
	hand_spray_point = transform * wrist
	var above := (hand_spray_point - model.surface_point(rider.d, rider.u)).dot(model.surface_normal(rider.d, rider.u))
	if above < DRAG_TOUCH:
		hand_spray = _arm.drag * clampf(rider.speed * 1.5, 0.3, 1.0)


func _apply_hips(to_model: Transform3D) -> void:
	var root := skeleton.find_bone("root")
	var dive := _dive * (1.0 - _free)
	if root < 0 or dive < 0.001:
		return
	var up := (to_model.basis.inverse() * Vector3.UP).normalized()
	var swing := Basis(up, dive * DIVE_YAW)  # positive turns the chest from the wave toward the nose
	var global := _global(root)
	var pivot := (_global(skeleton.find_bone("upperleg02.L")).origin + _global(skeleton.find_bone("upperleg02.R")).origin) / 2.0
	var shift := to_model.basis.inverse() * (Vector3(-DIVE_SHIFT, -0.04, 0.0) * dive)
	var turned := Transform3D(swing * global.basis, pivot + swing * (global.origin - pivot) + shift)
	skeleton.set_bone_pose_position(root, turned.origin)
	skeleton.set_bone_pose_rotation(root, turned.basis.get_rotation_quaternion())


## Tilts the whole body over the feet so that its centre of mass sits along the balance direction. The tilt turns about
## the point between the feet on the deck, so the hips and chest move over the feet and the leg solver keeps the feet
## planted while the knees and ankles bend to take the angle. A pose that folds forward (the bottom turn's hip hinge)
## already carries its weight forward, so it is tilted less: the hips go back to keep the chest over the feet.
func _apply_balance(to_model: Transform3D) -> void:
	var root := skeleton.find_bone("root")
	if root < 0:
		return
	var to_skeleton := to_model.affine_inverse()
	var between_feet: Vector3 = (_foot_target[-1.0] + _foot_target[1.0]) * 0.5
	var pivot := to_skeleton * between_feet
	var carried := (_centre_of_mass() - pivot).normalized()
	var wanted := (to_skeleton.basis * _balance).normalized()
	if carried.angle_to(wanted) < 0.001 or _free > 0.999:
		return
	var tilt := Basis(Quaternion.IDENTITY.slerp(Quaternion(carried, wanted), 1.0 - _free))
	var global := _global(root)
	skeleton.set_bone_pose_position(root, pivot + tilt * (global.origin - pivot))
	skeleton.set_bone_pose_rotation(root, (tilt * global.basis).get_rotation_quaternion())


## Roughly where the body's weight is, in the skeleton's space: mostly the pelvis and the trunk, a little the head.
func _centre_of_mass() -> Vector3:
	var com := Vector3.ZERO
	for entry in MASS:
		com += _global(skeleton.find_bone(entry[0])).origin * entry[1]
	return com


## Turns the upper back, then the neck and head, about the vertical, so he torques into a turn before the board has
## come round: the head with the front arm, the chest a beat later. The head also tips down to look where the front arm
## points (down the wave at the lip). Bones are visited root to tip so each sees its parent's final pose.
func _apply_lead() -> void:
	for entry in CHEST_BONES:
		_twist_bone(entry[0], Basis(Vector3.UP, -_chest_lead * (1.0 - _free) * entry[1]))


## Turns the neck and head, after everything else is posed, so his face points at the look point (the head bone faces
## along its own +Z). Whatever the torso does, folded in a bottom turn or laid back at the lip, he looks up the face
## or down it to where he is going, never at his feet.
func _aim_head(to_model: Transform3D) -> void:
	var head := skeleton.find_bone("head")
	if head < 0:
		return
	var pose := _global(head)
	var want := (to_model.affine_inverse() * _look_point - pose.origin).normalized()
	var turn := Quaternion(pose.basis.z.normalized(), want)
	var angle := turn.get_angle()
	if angle < 0.001:
		return
	if angle > LOOK_MAX:
		turn = Quaternion.IDENTITY.slerp(turn, LOOK_MAX / angle)
	turn = Quaternion.IDENTITY.slerp(turn, 1.0 - _free)  # (sitting or tumbling, the pose's own head)
	for entry in HEAD_BONES:
		_twist_bone(entry[0], Basis(Quaternion.IDENTITY.slerp(turn, entry[1])))


## Turns a bone about its own joint by a rotation given in the skeleton's space.
func _twist_bone(bone_name: String, world_twist: Basis) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := _global(parent).basis if parent >= 0 else Basis.IDENTITY
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
	var a := _global(r).origin
	var b := _global(m).origin
	var c := _global(t).origin
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
	_aim(m, _global(t).origin, a + dir * reach)


## Rotates a bone about its own joint so that the point `from` moves to the line toward `to`.
func _aim(bone: int, from: Vector3, to: Vector3) -> void:
	var global := _global(bone)
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
	var parent_basis := _global(parent).basis if parent >= 0 else Basis.IDENTITY
	return (parent_basis.inverse() * wanted).get_rotation_quaternion()


## A bone's pose in the skeleton's space, composed from the local poses up its parent chain. The engine's own
## get_bone_global_pose() only catches up once a frame, so right after a bone is set it still returns the old pose,
## and the solvers would work from last frame's joints.
func _global(bone: int) -> Transform3D:
	var t := Transform3D.IDENTITY
	var b := bone
	while b >= 0:
		var local := Basis(skeleton.get_bone_pose_rotation(b)) * Basis.from_scale(skeleton.get_bone_pose_scale(b))
		t = Transform3D(local, skeleton.get_bone_pose_position(b)) * t
		b = skeleton.get_bone_parent(b)
	return t


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
