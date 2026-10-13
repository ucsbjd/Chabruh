class_name SurferSprites
extends RefCounted
## The surfer's sprite animations: what exists, how many frames, how fast, and how the frames are laid out.
## The frames are PNGs made by tools/sprites/extract_sprites.py (see docs/sprite-pipeline.md), which prints
## the numbers below for a new clip. To add an animation: drop its frames in FOLDER as `<name>_00.png` and up,
## add a line to ANIMATIONS, ORDER and LABELS, and look at it with ?gallery.

const FOLDER := "res://assets/sprites/surfer/"

## Every frame of every animation is this big, with the board's centre on ANCHOR (in frame pixels).
const FRAME_SIZE := Vector2(468.0, 360.0)
const ANCHOR := Vector2(203.2, 355.3)
## The height of a frame in meters, so the surfer can be scaled to a 1.8 m person: the tallest pose in a frame
## (standing up with the board under the feet) is just under this.
const FRAME_METERS := 1.85
const PERSON_METERS := 1.8

## frames: how many PNGs; fps: playback speed; ping_pong: play forward then backward, so a clip that does not
## end where it started still loops without a jump. format: "flat" is a finished picture (the Kling frames);
## "toon" is the foundry's packed pair of passes (twice the frame width, see shaders/surfer_toon.gdshader and
## docs/foundry.md), tinted by the mood.
const ANIMATIONS := {
	"ride": {"frames": 35, "fps": 12.0, "ping_pong": true, "format": "flat"},
	"placeholder": {"frames": 8, "fps": 8.0, "ping_pong": false, "format": "toon"},
}

## The order the gallery and the P key step through.
const ORDER: Array[String] = ["ride", "placeholder"]

const LABELS := {
	"ride": "ride",
	"placeholder": "placeholder (toon)",
}


static func has_animation(animation_name: String) -> bool:
	return ANIMATIONS.has(animation_name)


static func is_toon(animation_name: String) -> bool:
	return ANIMATIONS.has(animation_name) and ANIMATIONS[animation_name].format == "toon"


static func frame_path(animation_name: String, index: int) -> String:
	return "%s%s_%02d.png" % [FOLDER, animation_name, index]


## Frame pixels that make a 1.8 m person, which is what `Surfer.place()` scales by.
static func person_pixels() -> float:
	return FRAME_SIZE.y * PERSON_METERS / FRAME_METERS
