class_name Surfer
extends Node2D
## The surfer: a sprite animation of an original character (bare tanned torso, bright 80s board shorts and a
## rainbow shortboard) seen from behind and slightly from the side, riding toward the screen's left.
## The frames come from the sprite pipeline (tools/sprites, docs/sprite-pipeline.md); what exists is listed
## in SurferSprites. The board's centre is this node's origin, so `place()` puts the board on the wave.

## Frame pixels in a 1.8 m person: `place()` scales the sprite so that many pixels become `pixels_tall`.
static var STANDING_HEIGHT := SurferSprites.person_pixels()

var _sprite := AnimatedSprite2D.new()
var _pose_name := ""


func _init() -> void:
	# Everything is attached here, not in _ready, so a surfer that is never started cannot orphan nodes.
	_sprite.centered = false
	_sprite.offset = -SurferSprites.ANCHOR
	_sprite.sprite_frames = _build_frames()
	add_child(_sprite)
	set_pose(SurferSprites.ORDER[0])


## Plays the named animation from its start. Unknown names are ignored.
func set_pose(pose_name: String) -> void:
	if not SurferSprites.has_animation(pose_name) or pose_name == _pose_name:
		return
	_pose_name = pose_name
	_sprite.play(pose_name)


func pose_name() -> String:
	return _pose_name


## How many frames the current animation plays through, counting the way back of a ping-pong.
func frame_count() -> int:
	return _sprite.sprite_frames.get_frame_count(_pose_name)


## Stands the surfer with the board's centre at `feet` (control pixels) and a 1.8 m person `pixels_tall` high.
func place(feet: Vector2, pixels_tall: float) -> void:
	position = feet
	scale = Vector2.ONE * (pixels_tall / STANDING_HEIGHT)


## Tilts the whole surfer to sit on a sloping wave face, in degrees (positive lifts the nose).
func set_ground_angle(degrees: float) -> void:
	rotation = deg_to_rad(degrees)


static func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for animation_name: String in SurferSprites.ANIMATIONS:
		var info: Dictionary = SurferSprites.ANIMATIONS[animation_name]
		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, info.fps)
		frames.set_animation_loop(animation_name, true)
		var count: int = info.frames
		for i in count:
			frames.add_frame(animation_name, load(SurferSprites.frame_path(animation_name, i)) as Texture2D)
		if info.ping_pong:
			# Back the way it came, without repeating the two end frames.
			for i in range(count - 2, 0, -1):
				frames.add_frame(animation_name, frames.get_frame_texture(animation_name, i))
	return frames
