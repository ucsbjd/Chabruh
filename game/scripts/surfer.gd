class_name Surfer
extends Node2D
## The surfer: a jointed paper doll of flat shapes, seen from behind and slightly from the side,
## riding toward the screen's left in a regular stance (left foot forward). It replaces the step 3
## stand-in. Every shape is built once; poses only move and rotate the joints, so nothing redraws.
##
## `set_pose()` eases every joint to a pose from PoseLibrary. Legs are solved from where the ankles
## should be (usually pinned to the board), so feet never slide off the board, mid-blend or not.
## Colours that never change come from the Palette consts; the violet shade and the warm sun-side
## rim light come from the mood through `surfer.gdshader`, so a mood fade never redraws anything.

const PaletteScript := preload("res://scripts/palette.gd")
const SURFER_SHADER := preload("res://shaders/surfer.gdshader")

## The surfer's nominal standing height in rig units. `place()` scales to a height in pixels.
const STANDING_HEIGHT := 1.0
## Seconds a pose takes to ease in.
const BLEND_SECONDS := 0.15

# Body proportions (rig units), from the back-view reference frames.
const THIGH := 0.25
const SHIN := 0.24
const UPPER_ARM := 0.17
const FOREARM := 0.15
const TORSO := 0.30
const HIP_X := 0.082
const SHOULDER_X := 0.175
const BOARD_HALF := 0.56
const BOARD_WIDTH := 0.105

const HAIR := Color("#2A1F2D")
const PINK := Color("#FF3D8B")
const AQUA := Color("#59D5C1")
const FIN := Color("#1B1730")

var _material_shade := ShaderMaterial.new()
var _material_rim := ShaderMaterial.new()

var _board := Node2D.new()
var _hips := Node2D.new()
var _torso := Node2D.new()
var _torso_shape := Node2D.new()
var _head := Node2D.new()
var _hair := Node2D.new()
var _arm_nodes := {}    # "l"/"r" -> [upper arm, forearm]
var _leg_nodes := {}    # "l"/"r" -> [thigh, shin, foot]

var _pose_name := ""
var _from: Dictionary = {}
var _to: Dictionary = {}
var _values: Dictionary = {}
var _blend := 1.0
var _blend_seconds := BLEND_SECONDS
var _clock := 0.0


func _init() -> void:
	# Everything is attached here, not in _ready, so a surfer that is never started cannot orphan nodes.
	_material_shade.shader = SURFER_SHADER
	_material_shade.set_shader_parameter("is_rim", 0.0)
	_material_rim.shader = SURFER_SHADER
	_material_rim.set_shader_parameter("is_rim", 1.0)
	_build_board()
	add_child(_hips)
	_build_body()
	set_pose("trim", 0.0)


func _ready() -> void:
	# Looked up by path, not by name: the test runner compiles this script before autoloads exist.
	get_node("/root/Palette").changed.connect(_apply_mood)
	_apply_mood()


func _process(delta: float) -> void:
	_clock += delta
	if _blend < 1.0:
		_blend = minf(_blend + delta / maxf(_blend_seconds, 0.0001), 1.0)
		var eased := smoothstep(0.0, 1.0, _blend)
		for key: String in _to:
			_values[key] = lerpf(_from[key], _to[key], eased)
	_apply(_values)


## The two materials that take the mood's shade and rim colours.
func materials() -> Array[ShaderMaterial]:
	return [_material_shade, _material_rim]


func _apply_mood() -> void:
	var mood: MoodData = get_node("/root/Palette").current
	for material in materials():
		material.set_shader_parameter("surfer_shade", mood.surfer_shade)
		material.set_shader_parameter("surfer_rim", mood.surfer_rim)


## Eases to the named pose over `seconds` (zero snaps). Unknown names are ignored.
func set_pose(pose_name: String, seconds := BLEND_SECONDS) -> void:
	if not PoseLibrary.has_pose(pose_name):
		return
	_pose_name = pose_name
	_from = _values.duplicate() if not _values.is_empty() else PoseLibrary.complete(pose_name)
	_to = PoseLibrary.complete(pose_name)
	_blend_seconds = seconds
	if seconds <= 0.0:
		_values = _to.duplicate()
		_blend = 1.0
	else:
		_blend = 0.0
	_apply(_values)


func pose_name() -> String:
	return _pose_name


## Stands the surfer with their feet at `feet` (control pixels), `pixels_tall` pixels high.
func place(feet: Vector2, pixels_tall: float) -> void:
	position = feet
	scale = Vector2.ONE * (pixels_tall / STANDING_HEIGHT)


## Tilts the whole surfer to sit on a sloping wave face, in degrees (positive lifts the nose).
func set_ground_angle(degrees: float) -> void:
	rotation = deg_to_rad(degrees)


## Where the board is, as a transform in the surfer's own space.
func board_transform() -> Transform2D:
	return _board.transform


## The ankle of a leg in the board's own space, for checking feet stand on the deck.
func ankle_on_board(side: String) -> Vector2:
	return _board.transform.affine_inverse() * _ankle_in_root(side)


# --- applying a pose --------------------------------------------------------------------------

func _apply(v: Dictionary) -> void:
	var sway: float = v.sway
	var bob := sin(_clock * 1.9) * 0.006 * sway
	var lean := sin(_clock * 1.3 + 1.0) * 1.4 * sway
	var swing := sin(_clock * 1.6) * 2.6 * sway

	_board.position = Vector2(v.board_x, v.board_y + bob * 0.6)
	_board.rotation = deg_to_rad(v.board_rot + sin(_clock * 1.1) * 0.8 * sway)
	_board.scale = Vector2(v.board_len, v.board_depth)

	_hips.position = Vector2(v.hips_x, v.hips_y + bob)
	_hips.rotation = deg_to_rad(v.hips_rot)

	var torso_up: float = v.torso_len
	_torso.position = Vector2(0.0, -0.02)
	_torso.rotation = deg_to_rad(v.torso_rot + lean)
	_torso_shape.scale = Vector2(v.torso_w, torso_up)
	var torso_world := deg_to_rad(v.hips_rot + v.torso_rot + lean)
	var top := -TORSO * torso_up
	_head.position = Vector2(0.0, top - 0.004)
	_head.rotation = deg_to_rad(v.head_rot)
	_hair.position = Vector2(v.head_look * 0.024, -0.004)

	var width: float = v.torso_w
	_pose_arm("l", Vector2(-SHOULDER_X * width, top + 0.035), v.arm_l_sh + swing, v.arm_l_el, torso_world)
	_pose_arm("r", Vector2(SHOULDER_X * width, top + 0.035), v.arm_r_sh - swing, v.arm_r_el, torso_world)

	var pin: float = v.feet_pin
	_pose_leg("l", Vector2(v.foot_l_x, v.foot_l_y), pin, v.knee_l, v.foot_l_rot)
	_pose_leg("r", Vector2(v.foot_r_x, v.foot_r_y), pin, v.knee_r, v.foot_r_rot)


func _pose_arm(side: String, shoulder: Vector2, shoulder_deg: float, elbow_deg: float, torso_world: float) -> void:
	var arm: Array = _arm_nodes[side]
	(arm[0] as Node2D).position = shoulder
	(arm[0] as Node2D).rotation = deg_to_rad(shoulder_deg) - torso_world
	(arm[1] as Node2D).rotation = deg_to_rad(elbow_deg)


func _pose_leg(side: String, ankle_target: Vector2, pin: float, knee: float, foot_rot_deg: float) -> void:
	var target := ankle_target.lerp(_board.transform * ankle_target, pin)
	var hip := _hips.transform * Vector2(-HIP_X if side == "l" else HIP_X, 0.025)
	var angles := solve_leg(hip, target, side == "l", knee >= 0.0)
	var leg: Array = _leg_nodes[side]
	var hips_rot := _hips.rotation
	(leg[0] as Node2D).position = Vector2(-HIP_X if side == "l" else HIP_X, 0.025)
	(leg[0] as Node2D).rotation = angles.x - hips_rot
	(leg[1] as Node2D).rotation = angles.y - angles.x
	var foot_world := deg_to_rad(foot_rot_deg) + pin * _board.rotation
	(leg[2] as Node2D).rotation = foot_world - angles.y


## Two-bone leg solve in the surfer's space. Returns the thigh's angle and the shin's angle, both from
## straight down (positive toward the screen's left). `outward` bends the knee away from the other
## leg; otherwise it bends inward.
static func solve_leg(hip: Vector2, ankle: Vector2, is_left: bool, outward: bool) -> Vector2:
	var to_ankle := ankle - hip
	var reach := clampf(to_ankle.length(), absf(THIGH - SHIN) + 0.002, THIGH + SHIN - 0.002)
	var aim := atan2(-to_ankle.x, to_ankle.y)
	var bend := acos(clampf((THIGH * THIGH + reach * reach - SHIN * SHIN) / (2.0 * THIGH * reach), -1.0, 1.0))
	var side := (1.0 if is_left else -1.0) * (1.0 if outward else -1.0)
	var thigh := aim + side * bend
	var knee := hip + Vector2(-sin(thigh), cos(thigh)) * THIGH
	var shin_vector := (hip + to_ankle.normalized() * reach) - knee
	var shin := atan2(-shin_vector.x, shin_vector.y)
	return Vector2(thigh, shin)


func _ankle_in_root(side: String) -> Vector2:
	var leg: Array = _leg_nodes[side]
	var thigh_node := leg[0] as Node2D
	var shin_node := leg[1] as Node2D
	var knee := _hips.transform * (thigh_node.position + thigh_node.transform.basis_xform(Vector2(0.0, THIGH)))
	var shin_world_angle := _hips.rotation + thigh_node.rotation + shin_node.rotation
	return knee + Vector2(-sin(shin_world_angle), cos(shin_world_angle)) * SHIN


# --- building the shapes ----------------------------------------------------------------------

func _build_board() -> void:
	add_child(_board)
	var outline := PackedVector2Array()
	var steps := 24
	for i in steps + 1:
		var u := i / float(steps)
		outline.append(Vector2(lerpf(-BOARD_HALF, BOARD_HALF, u), -_board_half_width(u)))
	for i in range(steps, -1, -1):
		var u := i / float(steps)
		outline.append(Vector2(lerpf(-BOARD_HALF, BOARD_HALF, u), _board_half_width(u) * 0.8))

	var fin := Polygon2D.new()
	fin.polygon = PackedVector2Array([Vector2(0.36, 0.0), Vector2(0.50, 0.0), Vector2(0.45, 0.085), Vector2(0.40, 0.07)])
	fin.color = FIN
	fin.antialiased = true
	_board.add_child(fin)

	var deck := Polygon2D.new()
	deck.polygon = outline
	deck.color = PaletteScript.BOARD
	deck.antialiased = true
	_board.add_child(deck)

	# The 80s graphic: a pink and an aqua chevron band near the nose, and a thin stringer line.
	_clipped(_board, outline, PackedVector2Array([Vector2(-0.34, -0.1), Vector2(-0.27, -0.1), Vector2(-0.20, 0.1), Vector2(-0.27, 0.1)]), PINK)
	_clipped(_board, outline, PackedVector2Array([Vector2(-0.25, -0.1), Vector2(-0.20, -0.1), Vector2(-0.13, 0.1), Vector2(-0.18, 0.1)]), AQUA)
	_clipped(_board, outline, PackedVector2Array([Vector2(-0.5, -0.006), Vector2(0.52, -0.006), Vector2(0.52, 0.006), Vector2(-0.5, 0.006)]), AQUA)
	_overlay(_board, Geometry2D.intersect_polygons(outline, _box(-1.0, 0.02, 1.0, 1.0)), _material_shade)


func _board_half_width(u: float) -> float:
	return BOARD_WIDTH * pow(u, 0.55) * sqrt(maxf(1.0 - pow(u, 7.0), 0.0))


func _build_body() -> void:
	var pelvis := PackedVector2Array([Vector2(-0.135, -0.01), Vector2(0.135, -0.01), Vector2(0.165, 0.06), Vector2(0.145, 0.13), Vector2(-0.145, 0.13), Vector2(-0.165, 0.06)])
	for side in ["r", "l"]:
		_build_leg(side)
	_part(_hips, pelvis, PaletteScript.SUIT_SECONDARY)

	_hips.add_child(_torso)
	_torso.add_child(_torso_shape)
	var torso := PackedVector2Array([
		Vector2(-0.085, -TORSO), Vector2(0.085, -TORSO), Vector2(0.165, -TORSO + 0.025), Vector2(0.215, -TORSO + 0.075),
		Vector2(0.20, -0.17), Vector2(0.16, -0.08), Vector2(0.135, 0.03),
		Vector2(-0.135, 0.03), Vector2(-0.16, -0.08), Vector2(-0.20, -0.17), Vector2(-0.215, -TORSO + 0.075), Vector2(-0.165, -TORSO + 0.025),
	])
	_part(_torso_shape, torso, PaletteScript.SUIT_PRIMARY, Vector2.ZERO, false)
	# Colour-blocking, like the board: a pink chevron across the back.
	_clipped(_torso_shape, torso, _chevron(-0.16, -0.05, 0.24, 0.045), PaletteScript.SUIT_ACCENT)
	_clipped(_torso_shape, torso, _box(-0.003, -TORSO + 0.04, 0.003, -0.03), PaletteScript.SUIT_PRIMARY.darkened(0.32))
	_shade_and_rim(_torso_shape, torso)
	_build_arm("r")
	_build_arm("l")

	_torso.add_child(_head)
	_part(_head, _capsule(0.05, 0.03, 0.028), PaletteScript.SKIN, Vector2(0.0, -0.03), false)
	_head.add_child(_hair)
	_part(_hair, _ellipse(0.066, 0.073, 18), HAIR, Vector2(0.0, -0.076))
	var face := _ellipse(0.058, 0.066, 18)
	var face_part := Polygon2D.new()
	face_part.polygon = _moved(face, Vector2(0.0, -0.066))
	face_part.color = PaletteScript.SKIN
	face_part.antialiased = true
	_head.add_child(face_part)
	_head.move_child(face_part, 1)


func _build_arm(side: String) -> void:
	var upper := Node2D.new()
	var forearm := Node2D.new()
	_torso.add_child(upper)
	upper.add_child(forearm)
	forearm.position = Vector2(0.0, UPPER_ARM)
	var sleeve_length := UPPER_ARM * 0.58
	# Order: bare forearm and hand first, then the upper arm's skin, then the lime sleeve on top.
	_part(forearm, _capsule(FOREARM, 0.046, 0.036), PaletteScript.SKIN)
	_part(forearm, _ellipse(0.046, 0.058, 10), PaletteScript.SKIN, Vector2(0.0, FOREARM + 0.034), false)
	_part(upper, _capsule(UPPER_ARM, 0.058, 0.048), PaletteScript.SKIN)
	var sleeve := _capsule(sleeve_length, 0.072, 0.063)
	_part(upper, sleeve, PaletteScript.SUIT_PRIMARY, Vector2.ZERO, false)
	_clipped(upper, sleeve, _box(-0.1, sleeve_length - 0.022, 0.1, sleeve_length + 0.1), PaletteScript.SUIT_ACCENT)
	_shade_and_rim(upper, sleeve)
	_arm_nodes[side] = [upper, forearm]


func _build_leg(side: String) -> void:
	var thigh := Node2D.new()
	var shin := Node2D.new()
	var foot := Node2D.new()
	_hips.add_child(thigh)
	thigh.add_child(shin)
	shin.add_child(foot)
	shin.position = Vector2(0.0, THIGH)
	foot.position = Vector2(0.0, SHIN)
	_part(shin, _capsule(SHIN, 0.056, 0.040), PaletteScript.SKIN)
	_part(shin, _capsule(SHIN * 0.34, 0.070, 0.062), PaletteScript.SUIT_SECONDARY)
	_part(foot, _foot_outline(), PaletteScript.SKIN, Vector2(-0.01, 0.026), false)
	var thigh_outline := _capsule(THIGH, 0.092, 0.070)
	_part(thigh, thigh_outline, PaletteScript.SUIT_SECONDARY, Vector2.ZERO, false)
	var outside := -1.0 if side == "l" else 1.0
	_clipped(thigh, thigh_outline, _box(minf(outside * 0.105, outside * 0.058), 0.02, maxf(outside * 0.105, outside * 0.058), THIGH - 0.01), PaletteScript.SUIT_ACCENT)
	_shade_and_rim(thigh, thigh_outline)
	_leg_nodes[side] = [thigh, shin, foot]


func _foot_outline() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-0.10, 0.0), Vector2(-0.065, -0.038), Vector2(0.04, -0.04), Vector2(0.105, -0.016),
		Vector2(0.108, 0.02), Vector2(0.04, 0.036), Vector2(-0.065, 0.033)])


## A flat colour polygon, with a violet shade on its lower right and a warm rim on its upper left
## (both skipped for small shapes where they would only be noise).
func _part(parent: Node2D, outline: PackedVector2Array, colour: Color, offset := Vector2.ZERO, lit := true) -> Polygon2D:
	var shape := _moved(outline, offset)
	var polygon := Polygon2D.new()
	polygon.polygon = shape
	polygon.color = colour
	polygon.antialiased = true
	parent.add_child(polygon)
	if lit:
		_shade_and_rim(parent, shape)
	return polygon


func _clipped(parent: Node2D, outline: PackedVector2Array, band: PackedVector2Array, colour: Color) -> void:
	for piece in Geometry2D.intersect_polygons(outline, band):
		var polygon := Polygon2D.new()
		polygon.polygon = piece
		polygon.color = colour
		polygon.antialiased = true
		parent.add_child(polygon)


func _shade_and_rim(parent: Node2D, outline: PackedVector2Array) -> void:
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		bounds = bounds.expand(point)
	var big := 2.0
	# Shade: the part of the shape on its right, away from the sun.
	var shade_top := bounds.position.x + bounds.size.x * 0.74
	var shade_bottom := bounds.position.x + bounds.size.x * 0.46
	var shade_side := PackedVector2Array([Vector2(shade_top, bounds.position.y - 0.05), Vector2(big, bounds.position.y - 0.05), Vector2(big, bounds.end.y + 0.05), Vector2(shade_bottom, bounds.end.y + 0.05)])
	_overlay(parent, Geometry2D.intersect_polygons(outline, shade_side), _material_shade)
	# Rim: a thin sliver along the left edge and the top edge, toward the sun.
	var edge := maxf(minf(bounds.size.x, bounds.size.y) * 0.14, 0.006)
	_overlay(parent, Geometry2D.intersect_polygons(outline, _box(-big, -big, bounds.position.x + edge, big)), _material_rim)
	_overlay(parent, Geometry2D.intersect_polygons(outline, _box(-big, -big, big, bounds.position.y + edge)), _material_rim)


## A thick V pointing down: arms from (-half_width, y_edge) to the point at (0, y_point), `thickness` tall.
static func _chevron(y_edge: float, y_point: float, half_width: float, thickness: float) -> PackedVector2Array:
	var drop := y_point - y_edge
	return PackedVector2Array([Vector2(-half_width, y_edge), Vector2(0.0, y_edge + drop * 1.0), Vector2(half_width, y_edge),
		Vector2(half_width, y_edge + thickness), Vector2(0.0, y_edge + drop + thickness), Vector2(-half_width, y_edge + thickness)])


static func _box(left: float, top: float, right: float, bottom: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(left, top), Vector2(right, top), Vector2(right, bottom), Vector2(left, bottom)])


func _overlay(parent: Node2D, pieces: Array, material: ShaderMaterial) -> void:
	for piece: PackedVector2Array in pieces:
		if piece.size() < 3:
			continue
		var polygon := Polygon2D.new()
		polygon.polygon = piece
		polygon.color = Color.WHITE
		polygon.material = material
		polygon.antialiased = true
		parent.add_child(polygon)


## A tapered rounded limb running down from the origin: radius `top` at the top, `bottom` at the end.
static func _capsule(length: float, top: float, bottom: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := 6
	for i in steps + 1:
		var a := PI + PI * i / steps
		points.append(Vector2(cos(a) * top, sin(a) * top))
	for i in steps + 1:
		var a := PI * i / steps
		points.append(Vector2(cos(a) * bottom, length + sin(a) * bottom))
	return points


static func _ellipse(rx: float, ry: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		var a := TAU * i / count
		points.append(Vector2(cos(a) * rx, sin(a) * ry))
	return points


static func _moved(outline: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	if offset == Vector2.ZERO:
		return outline
	var result := PackedVector2Array()
	for point in outline:
		result.append(point + offset)
	return result
