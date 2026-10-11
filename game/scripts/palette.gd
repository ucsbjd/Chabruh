extends Node
## Every colour in the game lives here, as three moods that cross-fade. Read colours from
## `Palette.current`; it is already blended while a fade is running. The sunset mood is sampled
## from the key frames (storyboardimages/kling/kling-04 and kling-05); the others keep the wave
## a saturated jade green and change the light around it.

signal changed

const FADE_SECONDS := 1.5
const MOOD_ORDER: Array[String] = ["golden", "sunset", "neon"]
const DEFAULT_MOOD := "sunset"

const MOODS := {
	"golden": {
		"sky_top": "#7C86C8", "sky_violet": "#C09ACB", "sky_pink": "#F0B0A8", "sky_peach": "#FFCFA0",
		"sky_horizon": "#FFE7B8", "sun": "#FFE08A", "sun_low": "#FFAA60", "sun_glow": "#FFD590",
		"haze": "#FFE0B8", "sea_horizon": "#FFD9A2", "sea_deep": "#2B7FA6", "sun_glint": "#FFF3C8",
		"ridge_far": "#D3A8B8", "ridge_mid": "#9A6E9E", "palm": "#5A3A70",
		"wave_shadow": "#123F4A", "wave_deep": "#1B6461", "wave_mid": "#2E8F78", "wave_light": "#4DBB8A",
		"wave_glint": "#A8EBC0", "wave_rim": "#FFF0A0", "hollow_dark": "#123A55", "hollow_glow": "#7FE8B8",
		"foam_lit": "#FFF8EA", "foam_shade": "#B7A4D0",
		"swell_top": "#2F8F96", "swell_deep": "#1C5F72", "swell_line": "#A8F0DC",
		"glow": "#FFDDA0", "glow_strength": 0.36, "grade_top": "#A890C8", "grade_bottom": "#FFC27A",
		"grade_strength": 0.06, "vignette": "#4A3A6A", "vignette_strength": 0.22, "grain_strength": 0.025,
		"scanline_strength": 0.03,
	},
	"sunset": {
		"sky_top": "#290756", "sky_violet": "#6B3380", "sky_pink": "#B45984", "sky_peach": "#E8836F",
		"sky_horizon": "#F0A878", "sun": "#EBA565", "sun_low": "#E56F80", "sun_glow": "#F08A70",
		"haze": "#C58380", "sea_horizon": "#D8808A", "sea_deep": "#1F5E75", "sun_glint": "#F5C890",
		"ridge_far": "#9A4F8E", "ridge_mid": "#6E3A86", "palm": "#5A2F7A",
		"wave_shadow": "#0C2B4C", "wave_deep": "#135153", "wave_mid": "#1C776B", "wave_light": "#25A078",
		"wave_glint": "#7FE3B8", "wave_rim": "#E8D27A", "hollow_dark": "#14214A", "hollow_glow": "#3CC9A0",
		"foam_lit": "#FDE9DE", "foam_shade": "#606296",
		"swell_top": "#256E7D", "swell_deep": "#14485A", "swell_line": "#59D5C1",
		"glow": "#F08A70", "glow_strength": 0.28, "grade_top": "#6B3380", "grade_bottom": "#E8836F",
		"grade_strength": 0.07, "vignette": "#290756", "vignette_strength": 0.35, "grain_strength": 0.03,
		"scanline_strength": 0.05,
	},
	"neon": {
		"sky_top": "#0A0626", "sky_violet": "#35107A", "sky_pink": "#D0239C", "sky_peach": "#FF6B8E",
		"sky_horizon": "#FFB36B", "sun": "#FF8FC8", "sun_low": "#FF3D8B", "sun_glow": "#FF4FA0",
		"haze": "#A8409E", "sea_horizon": "#FF6FA8", "sea_deep": "#120B4A", "sun_glint": "#FF9ACB",
		"ridge_far": "#4B1C80", "ridge_mid": "#25105A", "palm": "#0E0828",
		"wave_shadow": "#0A1044", "wave_deep": "#0A4F7A", "wave_mid": "#0FA3A3", "wave_light": "#2BE0B0",
		"wave_glint": "#9CFFE0", "wave_rim": "#FF8FD0", "hollow_dark": "#080430", "hollow_glow": "#2FE8E8",
		"foam_lit": "#FFE8F6", "foam_shade": "#8C6CFF",
		"swell_top": "#0E7FB0", "swell_deep": "#0B1E70", "swell_line": "#FF4FA0",
		"glow": "#FF4FA0", "glow_strength": 0.45, "grade_top": "#5B2BD0", "grade_bottom": "#FF3D8B",
		"grade_strength": 0.12, "vignette": "#0A0626", "vignette_strength": 0.5, "grain_strength": 0.04,
		"scanline_strength": 0.07,
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