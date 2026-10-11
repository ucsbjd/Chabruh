extends Node
## Every colour in the game lives here, as three moods that cross-fade. Read colours from
## `Palette.current`; it is already blended while a fade is running.

signal changed

const FADE_SECONDS := 1.5
const MOOD_ORDER: Array[String] = ["golden", "sunset", "neon"]
const DEFAULT_MOOD := "sunset"

const MOODS := {
	"golden": {
		"sky_top": "#6E9AD0", "sky_violet": "#B3A3D6", "sky_pink": "#F6B6B2", "sky_peach": "#FFD3A0",
		"sky_horizon": "#FFEBBE", "sun": "#FFF3C8", "sun_low": "#FFC070", "sun_glow": "#FFD590",
		"haze": "#FFE3B8", "sea_horizon": "#FFD9A2", "sea_deep": "#2B7FA6", "sun_glint": "#FFF3C8",
		"ridge_far": "#C7A5BC", "ridge_mid": "#8A6AA0", "palm": "#4A3468",
		"wave_shadow": "#2A4F8A", "wave_deep": "#0F8196", "wave_mid": "#2ACBBC", "wave_light": "#94F7DA",
		"wave_glint": "#F4FFE2", "hollow_dark": "#233E7C", "hollow_glow": "#86F2C6",
		"foam_lit": "#FFF9EA", "foam_shade": "#D9BCE8",
		"swell_top": "#22ADB2", "swell_deep": "#1B5B88", "swell_line": "#AAF6E0",
		"glow": "#FFDDA0", "glow_strength": 0.40, "grade_top": "#9A80C4", "grade_bottom": "#FFC27A",
		"grade_strength": 0.08, "vignette": "#3A2A5A", "vignette_strength": 0.26, "grain_strength": 0.03,
	},
	"sunset": {
		"sky_top": "#2B1B5E", "sky_violet": "#7B3FA0", "sky_pink": "#E8559A", "sky_peach": "#FF9A6B",
		"sky_horizon": "#FFD79A", "sun": "#FFE3A3", "sun_low": "#FF7A8A", "sun_glow": "#FFB47A",
		"haze": "#F6B7B0", "sea_horizon": "#F29AA6", "sea_deep": "#2E3F8F", "sun_glint": "#FFE3A3",
		"ridge_far": "#A862A8", "ridge_mid": "#6A3A8E", "palm": "#331A55",
		"wave_shadow": "#25306B", "wave_deep": "#0B7C8C", "wave_mid": "#19C9C0", "wave_light": "#7AF2E0",
		"wave_glint": "#D8FFF0", "hollow_dark": "#1A1550", "hollow_glow": "#4FE3D0",
		"foam_lit": "#FFF4E6", "foam_shade": "#C7A8E0",
		"swell_top": "#139AA8", "swell_deep": "#17357A", "swell_line": "#7AF2E0",
		"glow": "#FFB47A", "glow_strength": 0.35, "grade_top": "#7B3FA0", "grade_bottom": "#FF9A6B",
		"grade_strength": 0.10, "vignette": "#1B1730", "vignette_strength": 0.38, "grain_strength": 0.035,
	},
	"neon": {
		"sky_top": "#0A0626", "sky_violet": "#35107A", "sky_pink": "#D0239C", "sky_peach": "#FF6B8E",
		"sky_horizon": "#FFB36B", "sun": "#FFC2E4", "sun_low": "#FF3D8B", "sun_glow": "#FF4FA0",
		"haze": "#A8409E", "sea_horizon": "#FF6FA8", "sea_deep": "#120B4A", "sun_glint": "#FF9ACB",
		"ridge_far": "#4B1C80", "ridge_mid": "#25105A", "palm": "#0E0828",
		"wave_shadow": "#130C52", "wave_deep": "#0A5C92", "wave_mid": "#12B9D9", "wave_light": "#5CF5F0",
		"wave_glint": "#CCFFFF", "hollow_dark": "#090433", "hollow_glow": "#2FE8E8",
		"foam_lit": "#FFE8F6", "foam_shade": "#B08CFF",
		"swell_top": "#0E82B4", "swell_deep": "#0B1E70", "swell_line": "#FF4FA0",
		"glow": "#FF4FA0", "glow_strength": 0.50, "grade_top": "#5B2BD0", "grade_bottom": "#FF3D8B",
		"grade_strength": 0.14, "vignette": "#0A0626", "vignette_strength": 0.50, "grain_strength": 0.045,
	},
}

## The blended look right now. Shaders and shapes read from this.
var current: MoodData
var mood_name := DEFAULT_MOOD

var _from: MoodData
var _to: MoodData
var _fade := 1.0


func _ready() -> void:
	var requested := UrlParams.get_value("mood")
	select(requested if MOODS.has(requested) else DEFAULT_MOOD, true)


func _process(delta: float) -> void:
	_fade = minf(_fade + delta / FADE_SECONDS, 1.0)
	current = _to if _fade >= 1.0 else _from.mixed_with(_to, smoothstep(0.0, 1.0, _fade))
	if _fade >= 1.0:
		set_process(false)
	changed.emit()


## Switches to a mood by name, fading unless `instant`.
func select(name: String, instant := false) -> void:
	if not MOODS.has(name):
		return
	mood_name = name
	_from = current if current != null and not instant else build(name)
	_to = build(name)
	_fade = 1.0 if instant else 0.0
	current = _to if instant else _from
	set_process(not instant)
	changed.emit()


## Moves to the next mood in MOOD_ORDER.
func cycle() -> void:
	select(MOOD_ORDER[(MOOD_ORDER.find(mood_name) + 1) % MOOD_ORDER.size()])


## Builds a MoodData from the table above.
static func build(name: String) -> MoodData:
	var mood := MoodData.new()
	for property: String in MOODS[name]:
		var value: Variant = MOODS[name][property]
		mood.set(property, Color(value) if value is String else value)
	return mood
