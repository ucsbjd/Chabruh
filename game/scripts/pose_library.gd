class_name PoseLibrary
extends RefCounted
## Every pose the surfer can strike, as plain data. A pose lists only what differs from DEFAULT, and
## `complete()` fills in the rest, so every pose always has every joint (the blend relies on that).
##
## The surfer is drawn from behind and slightly to the side, travelling toward the screen's left.
## Sizes are in rig units: 1.0 is the surfer's standing height. y is up when negative.
##
## Angles are degrees. 0 hangs straight down; positive swings toward the screen's left (the way the
## surfer travels), negative toward the right, and 180 is straight up. Elbow and knee angles are
## relative to the limb above. Torso and head angles lean the other way round: positive leans to
## the right (back over the tail), negative leans forward over the nose.
##
##   hips_x, hips_y, hips_rot      where the pelvis is, and how it tilts
##   torso_rot, torso_len, torso_w lean, vertical squash (bending away from us), and width (twisting)
##   head_rot, head_look           tilt, and where the face turns (-1 right, +1 left)
##   arm_l_*, arm_r_*              shoulder and elbow of the arm on the screen's left (the front arm) and right
##   foot_l_*, foot_r_*            where each ankle goes, in board space when feet_pin is 1 and in
##                                 the surfer's own space when it is 0. The legs solve themselves
##   knee_l, knee_r                which way each knee bends: 1 outward (the usual), -1 inward
##   foot_l_rot, foot_r_rot        extra ankle roll
##   board_*                       the board's offset, tilt (positive lifts the nose), length
##                                 squash (turning away or toward us) and depth squash (rolling onto a rail)
##   sway                          how much the idle sway shows (0 in the air)

const DEFAULT := {
	"hips_x": 0.0, "hips_y": -0.545, "hips_rot": 0.0,
	"torso_rot": 0.0, "torso_len": 1.0, "torso_w": 1.0,
	"head_rot": 0.0, "head_look": 0.3,
	"arm_l_sh": 18.0, "arm_l_el": 8.0, "arm_r_sh": -18.0, "arm_r_el": -8.0,
	"foot_l_x": -0.14, "foot_l_y": -0.06, "foot_r_x": 0.14, "foot_r_y": -0.06,
	"feet_pin": 1.0, "knee_l": 1.0, "knee_r": 1.0, "foot_l_rot": 0.0, "foot_r_rot": 0.0,
	"board_x": 0.0, "board_y": 0.0, "board_rot": 0.0, "board_len": 1.0, "board_depth": 1.3,
	"sway": 1.0,
}

## Poses in the order the gallery shows them: the paddle-out first, then the ride, then the falls.
const ORDER: Array[String] = [
	"walk_in", "paddle", "pop_up", "trim", "bottom_turn", "top_turn",
	"cutback", "barrel", "air", "floater", "wipeout",
]

const LABELS := {
	"walk_in": "walk-in", "paddle": "paddle", "pop_up": "pop-up", "trim": "trim",
	"bottom_turn": "bottom turn", "top_turn": "top turn", "cutback": "cutback",
	"barrel": "barrel", "air": "air", "floater": "floater", "wipeout": "wipeout",
}

const POSES := {
	"walk_in": {
		"hips_y": -0.535, "hips_rot": 3.0, "torso_rot": 3.0, "head_look": 0.4,
		"feet_pin": 0.0, "foot_l_x": -0.07, "foot_l_y": -0.04, "foot_r_x": 0.15, "foot_r_y": -0.10,
		"arm_l_sh": 32.0, "arm_l_el": 18.0, "arm_r_sh": -42.0, "arm_r_el": -30.0,
		"board_x": 0.0, "board_y": -0.42, "board_rot": 10.0, "board_len": 0.98, "board_depth": 1.1,
	},
	"paddle": {
		"hips_x": 0.14, "hips_y": -0.15, "hips_rot": -4.0, "torso_rot": -70.0, "torso_len": 0.9, "head_rot": 52.0, "head_look": 1.0,
		"arm_l_sh": 112.0, "arm_l_el": -34.0, "arm_r_sh": -62.0, "arm_r_el": -22.0,
		"foot_l_x": 0.50, "foot_l_y": -0.10, "foot_r_x": 0.54, "foot_r_y": -0.085,
		"foot_l_rot": 30.0, "foot_r_rot": 40.0, "board_depth": 0.8, "sway": 0.5,
	},
	"pop_up": {
		"hips_x": 0.02, "hips_y": -0.40, "hips_rot": -6.0, "torso_rot": -40.0, "torso_len": 0.9, "head_look": 0.8,
		"arm_l_sh": 12.0, "arm_l_el": 10.0, "arm_r_sh": -20.0, "arm_r_el": 8.0,
		"foot_l_x": -0.26, "foot_l_y": -0.075, "foot_r_x": 0.10, "foot_r_y": -0.09,
		"knee_l": 1.0, "knee_r": 1.0, "foot_r_rot": -18.0, "board_depth": 1.1,
	},
	"trim": {
		"hips_x": -0.03, "hips_y": -0.40, "hips_rot": -5.0, "torso_rot": -14.0, "torso_len": 0.95, "torso_w": 0.95,
		"head_rot": -6.0, "head_look": 0.6,
		"arm_l_sh": 82.0, "arm_l_el": 6.0, "arm_r_sh": -34.0, "arm_r_el": -44.0,
		"foot_l_x": -0.27, "foot_r_x": 0.36, "board_rot": 2.0,
	},
	"bottom_turn": {
		"hips_x": -0.08, "hips_y": -0.30, "hips_rot": -8.0, "torso_rot": -46.0, "torso_len": 0.80, "torso_w": 0.85,
		"head_rot": -10.0, "head_look": 0.8,
		"arm_l_sh": 12.0, "arm_l_el": 18.0, "arm_r_sh": -70.0, "arm_r_el": -48.0,
		"foot_l_x": -0.22, "foot_r_x": 0.20, "board_rot": 3.0, "board_depth": 1.5,
	},
	"top_turn": {
		"hips_x": 0.05, "hips_y": -0.30, "hips_rot": 10.0, "torso_rot": 18.0, "torso_len": 0.86, "torso_w": 0.65,
		"head_rot": 8.0, "head_look": 1.0,
		"arm_l_sh": 112.0, "arm_l_el": 8.0, "arm_r_sh": -20.0, "arm_r_el": -26.0,
		"foot_l_x": -0.22, "foot_r_x": 0.17, "board_rot": 40.0, "board_len": 0.88, "board_depth": 1.5,
	},
	"cutback": {
		"hips_x": 0.04, "hips_y": -0.31, "hips_rot": 8.0, "torso_rot": 14.0, "torso_len": 0.86, "torso_w": 0.7,
		"head_rot": 6.0, "head_look": -0.4,
		"arm_l_sh": 52.0, "arm_l_el": 22.0, "arm_r_sh": -124.0, "arm_r_el": -10.0,
		"foot_l_x": -0.24, "foot_r_x": 0.18, "board_rot": 18.0, "board_len": 0.94, "board_depth": 1.5,
	},
	"barrel": {
		"hips_x": -0.03, "hips_y": -0.22, "hips_rot": -10.0, "torso_rot": -50.0, "torso_len": 0.76, "torso_w": 0.9,
		"head_rot": -6.0, "head_look": 1.0,
		"arm_l_sh": 22.0, "arm_l_el": 20.0, "arm_r_sh": -100.0, "arm_r_el": -16.0,
		"foot_l_x": -0.24, "foot_r_x": 0.18, "board_depth": 1.5,
	},
	"air": {
		"hips_x": 0.0, "hips_y": -0.36, "hips_rot": 10.0, "torso_rot": 6.0, "torso_len": 0.94, "torso_w": 0.8,
		"head_rot": 6.0, "head_look": 1.0,
		"arm_l_sh": 165.0, "arm_l_el": 10.0, "arm_r_sh": -98.0, "arm_r_el": -12.0,
		"foot_l_x": -0.20, "foot_r_x": 0.22, "board_rot": 54.0, "board_len": 0.86, "board_depth": 1.4,
		"board_y": 0.05, "sway": 0.0,
	},
	"floater": {
		"hips_x": -0.04, "hips_y": -0.30, "hips_rot": -4.0, "torso_rot": -42.0, "torso_len": 0.82,
		"head_rot": -8.0, "head_look": 0.8,
		"arm_l_sh": 10.0, "arm_l_el": 12.0, "arm_r_sh": -86.0, "arm_r_el": -30.0,
		"foot_l_x": -0.28, "foot_r_x": 0.22, "board_rot": 26.0, "board_depth": 1.4,
	},
	"wipeout": {
		"hips_x": 0.16, "hips_y": -0.22, "hips_rot": -70.0, "torso_rot": -82.0, "torso_len": 0.9, "torso_w": 0.85,
		"head_rot": -30.0, "head_look": -0.5,
		"arm_l_sh": 30.0, "arm_l_el": 40.0, "arm_r_sh": -140.0, "arm_r_el": -30.0,
		"feet_pin": 0.0, "foot_l_x": 0.34, "foot_l_y": -0.52, "foot_r_x": 0.52, "foot_r_y": -0.22,
		"foot_l_rot": 20.0, "foot_r_rot": -50.0,
		"board_x": -0.46, "board_y": -0.62, "board_rot": -38.0, "board_depth": 1.2, "sway": 0.0,
	},
}


## The pose with every key filled in. Unknown names give the default pose.
static func complete(pose_name: String) -> Dictionary:
	var result := DEFAULT.duplicate()
	if POSES.has(pose_name):
		result.merge(POSES[pose_name], true)
	return result


static func has_pose(pose_name: String) -> bool:
	return POSES.has(pose_name)
