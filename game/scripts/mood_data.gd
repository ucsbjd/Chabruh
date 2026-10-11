class_name MoodData
extends Resource
## One complete look: every colour the scene uses, plus a few strengths. Shader uniforms share
## these property names, so world.gd feeds them without any per-shader mapping.

@export_group("Sky and sea")
@export var sky_top := Color.BLACK
@export var sky_violet := Color.BLACK
@export var sky_pink := Color.BLACK
@export var sky_peach := Color.BLACK
@export var sky_horizon := Color.BLACK
@export var sun := Color.BLACK
@export var sun_low := Color.BLACK
@export var sun_glow := Color.BLACK
@export var haze := Color.BLACK
@export var sea_horizon := Color.BLACK
@export var sea_deep := Color.BLACK
@export var sun_glint := Color.BLACK

@export_group("Land")
@export var ridge_far := Color.BLACK
@export var ridge_mid := Color.BLACK
@export var palm := Color.BLACK

@export_group("Wave")
@export var wave_shadow := Color.BLACK
@export var wave_deep := Color.BLACK
@export var wave_mid := Color.BLACK
@export var wave_light := Color.BLACK
@export var wave_glint := Color.BLACK
## Thin warm line along the crest.
@export var wave_rim := Color.BLACK
@export var hollow_dark := Color.BLACK
@export var hollow_glow := Color.BLACK
@export var foam_lit := Color.BLACK
@export var foam_shade := Color.BLACK

@export_group("Surfer")
## Violet shade on the side of the surfer away from the sun, and the warm light on the side toward it.
@export var surfer_shade := Color.BLACK
@export var surfer_rim := Color.BLACK

@export_group("Foreground swell")
@export var swell_top := Color.BLACK
@export var swell_deep := Color.BLACK
@export var swell_line := Color.BLACK

@export_group("Finish")
@export var glow := Color.BLACK
@export var glow_strength := 0.0
@export var grade_top := Color.BLACK
@export var grade_bottom := Color.BLACK
@export var grade_strength := 0.0
@export var vignette := Color.BLACK
@export var vignette_strength := 0.0
@export var grain_strength := 0.0
@export var scanline_strength := 0.0

static var _names := PackedStringArray()


## Names of every colour and strength above, in declaration order.
static func property_names() -> PackedStringArray:
	if _names.is_empty():
		for info in MoodData.new().get_property_list():
			if info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				_names.append(info.name)
	return _names


## A new mood that is `t` of the way from this one to `other`.
func mixed_with(other: MoodData, t: float) -> MoodData:
	var result := MoodData.new()
	for property in property_names():
		var from: Variant = get(property)
		var to: Variant = other.get(property)
		result.set(property, from.lerp(to, t) if from is Color else lerpf(from, to, t))
	return result
