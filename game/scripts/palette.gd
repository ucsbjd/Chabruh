extends Node
## Every colour in the game lives here, as five moods that cross-fade. Read colours from
## `Palette.current`; it is already blended while a fade is running. The sunset mood is sampled
## from the key frames (storyboardimages/kling/kling-04 and kling-05); golden and neon keep the wave
## a saturated jade green and change the light around it. Dusk and the bioluminescent night are where
## a long session ends up (SolarClock): the sun goes down, and at night the water itself glows.

signal changed

const FADE_SECONDS := 1.5
const MOOD_ORDER: Array[String] = ["golden", "sunset", "neon", "dusk", "bioluminescent"]
const DEFAULT_MOOD := "sunset"

const MOODS := {
	"golden": {
		"sky_top": "#7C86C8", "sky_violet": "#C09ACB", "sky_pink": "#F0B0A8", "sky_peach": "#FFCFA0",
		"sky_horizon": "#FFE7B8", "sun": "#FFE08A", "sun_low": "#FFAA60", "sun_glow": "#FFD590",
		"haze": "#FFE0B8", "sea_horizon": "#FFD9A2", "sea_deep": "#2B7FA6", "sun_glint": "#FFF3C8",
		"ridge_far": "#D3A8B8", "ridge_mid": "#9A6E9E", "palm": "#5A3A70",
		"wave_shadow": "#123F4A", "wave_deep": "#1B6461", "wave_mid": "#2E8F78", "wave_light": "#4DBB8A",
		"wave_glint": "#A8EBC0", "wave_sunlit": "#EEF59A", "wave_rim": "#FFF0A0", "hollow_dark": "#123A55", "hollow_glow": "#7FE8B8",
		"foam_lit": "#FFF8EA", "foam_shade": "#B7A4D0",
		"surfer_skin": "#E0A070", "surfer_shorts": "#FF8A70", "surfer_board": "#FFF3D8", "surfer_hair": "#F0D088",
		"surfer_ink": "#3A2A3A", "surfer_trim": "#46C8B8", "surfer_stripe_a": "#FF6F8E", "surfer_stripe_b": "#FFE070",
		"surfer_light": "#FFE8B8", "surfer_shade": "#7A6AAA", "surfer_rim": "#FFF0B0",
		"surfer_veil_deep": "#145A5E", "surfer_veil_lit": "#8FF0D0",
		"swell_top": "#2F8F96", "swell_deep": "#1C5F72", "swell_line": "#A8F0DC",
		"glow": "#FFDDA0", "glow_strength": 0.36, "grade_top": "#A890C8", "grade_bottom": "#FFC27A",
		"grade_strength": 0.06, "vignette": "#4A3A6A", "vignette_strength": 0.22, "grain_strength": 0.025,
		"scanline_strength": 0.03, "spray_rim": "#FFE08A",
	},
	"sunset": {
		"sky_top": "#290756", "sky_violet": "#6B3380", "sky_pink": "#B45984", "sky_peach": "#E8836F",
		"sky_horizon": "#F0A878", "sun": "#EBA565", "sun_low": "#E56F80", "sun_glow": "#F08A70",
		"haze": "#C58380", "sea_horizon": "#D8808A", "sea_deep": "#1F5E75", "sun_glint": "#F5C890",
		"ridge_far": "#9A4F8E", "ridge_mid": "#6E3A86", "palm": "#5A2F7A",
		"wave_shadow": "#0C2B4C", "wave_deep": "#135153", "wave_mid": "#1C776B", "wave_light": "#25A078",
		"wave_glint": "#7FE3B8", "wave_sunlit": "#D4F07A", "wave_rim": "#E8D27A", "hollow_dark": "#14214A", "hollow_glow": "#3CC9A0",
		"foam_lit": "#FDE9DE", "foam_shade": "#606296",
		"surfer_skin": "#D98A62", "surfer_shorts": "#FF6F61", "surfer_board": "#F6E7D0", "surfer_hair": "#E3BE72",
		"surfer_ink": "#2A1B2E", "surfer_trim": "#3FD0C4", "surfer_stripe_a": "#FF3D8B", "surfer_stripe_b": "#FFD95A",
		"surfer_light": "#FFD9A0", "surfer_shade": "#606296", "surfer_rim": "#FFD27A",
		"surfer_veil_deep": "#0E4450", "surfer_veil_lit": "#59D5C1",
		"swell_top": "#256E7D", "swell_deep": "#14485A", "swell_line": "#59D5C1",
		"glow": "#F08A70", "glow_strength": 0.28, "grade_top": "#6B3380", "grade_bottom": "#E8836F",
		"grade_strength": 0.07, "vignette": "#290756", "vignette_strength": 0.35, "grain_strength": 0.03,
		"scanline_strength": 0.05, "spray_rim": "#FFD27A",
	},
	"neon": {
		"sky_top": "#0A0626", "sky_violet": "#35107A", "sky_pink": "#D0239C", "sky_peach": "#FF6B8E",
		"sky_horizon": "#FFB36B", "sun": "#FF8FC8", "sun_low": "#FF3D8B", "sun_glow": "#FF4FA0",
		"haze": "#A8409E", "sea_horizon": "#FF6FA8", "sea_deep": "#120B4A", "sun_glint": "#FF9ACB",
		"ridge_far": "#4B1C80", "ridge_mid": "#25105A", "palm": "#0E0828",
		"wave_shadow": "#0A1044", "wave_deep": "#0A4F7A", "wave_mid": "#0FA3A3", "wave_light": "#2BE0B0",
		"wave_glint": "#9CFFE0", "wave_sunlit": "#C4FFB0", "wave_rim": "#FF8FD0", "hollow_dark": "#080430", "hollow_glow": "#2FE8E8",
		"foam_lit": "#FFE8F6", "foam_shade": "#8C6CFF",
		"surfer_skin": "#D9809A", "surfer_shorts": "#FF5A9E", "surfer_board": "#FFE8F6", "surfer_hair": "#FFD0F0",
		"surfer_ink": "#1B1730", "surfer_trim": "#28F0E0", "surfer_stripe_a": "#B040FF", "surfer_stripe_b": "#C6F135",
		"surfer_light": "#FFB0F0", "surfer_shade": "#5B2BD0", "surfer_rim": "#7FFFEA",
		"surfer_veil_deep": "#0A3A6A", "surfer_veil_lit": "#5CFFF0",
		"swell_top": "#0E7FB0", "swell_deep": "#0B1E70", "swell_line": "#FF4FA0",
		"glow": "#FF4FA0", "glow_strength": 0.45, "grade_top": "#5B2BD0", "grade_bottom": "#FF3D8B",
		"grade_strength": 0.12, "vignette": "#0A0626", "vignette_strength": 0.5, "grain_strength": 0.04,
		"scanline_strength": 0.07, "spray_rim": "#FF8FD0",
	},
	# The sun has gone below the horizon: deep purple twilight, and the neon gear pops.
	"dusk": {
		"sky_top": "#120A33", "sky_violet": "#2E1466", "sky_pink": "#6A2A8C", "sky_peach": "#B0458F",
		"sky_horizon": "#E2689A", "sun": "#FF7FB8", "sun_low": "#E0457F", "sun_glow": "#C23E8A",
		"haze": "#6E3A8C", "sea_horizon": "#9C4A92", "sea_deep": "#0E1648", "sun_glint": "#FF9CCB",
		"ridge_far": "#3A1A6A", "ridge_mid": "#22104A", "palm": "#100828",
		"wave_shadow": "#08123A", "wave_deep": "#0B3A5E", "wave_mid": "#11707F", "wave_light": "#1FA592",
		"wave_glint": "#7FF0D0", "wave_sunlit": "#A8F5B8", "wave_rim": "#FF7FC8", "hollow_dark": "#070A2E", "hollow_glow": "#33D9D0",
		"foam_lit": "#F4E6FF", "foam_shade": "#6A55C8",
		"surfer_skin": "#C47A90", "surfer_shorts": "#FF4F9A", "surfer_board": "#F2E6FF", "surfer_hair": "#E8C8F0",
		"surfer_ink": "#17122C", "surfer_trim": "#3FF0E0", "surfer_stripe_a": "#B44CFF", "surfer_stripe_b": "#C6F135",
		"surfer_light": "#E8A8F0", "surfer_shade": "#4A2BA8", "surfer_rim": "#8FFFF0",
		"surfer_veil_deep": "#0A2E5A", "surfer_veil_lit": "#5CF0F0",
		"swell_top": "#12507E", "swell_deep": "#0A1A52", "swell_line": "#C04CC0",
		"glow": "#D04AA8", "glow_strength": 0.4, "grade_top": "#3A1A8A", "grade_bottom": "#C83A8A",
		"grade_strength": 0.12, "vignette": "#070420", "vignette_strength": 0.55, "grain_strength": 0.045,
		"scanline_strength": 0.07, "spray_rim": "#C6F135",
	},
	# Night, the reward for a long flowing session: a deep midnight sea where everything the water does glows electric
	# aqua and lime (the foam, the spray, the crest, the lace on the sea).
	"bioluminescent": {
		"sky_top": "#090418", "sky_violet": "#160C2E", "sky_pink": "#2A1B4E", "sky_peach": "#3B2860",
		"sky_horizon": "#4A3470", "sun": "#3B2860", "sun_low": "#3B2860", "sun_glow": "#1E3A5A",
		"haze": "#241A44", "sea_horizon": "#2A2450", "sea_deep": "#0A192F", "sun_glint": "#6CFFE0",
		"ridge_far": "#1A1236", "ridge_mid": "#100A26", "palm": "#06040F",
		"wave_shadow": "#051622", "wave_deep": "#092738", "wave_mid": "#0D3B4C", "wave_light": "#14606A",
		"wave_glint": "#2CEAA3", "wave_sunlit": "#2CEAA3", "wave_rim": "#4FFFB0", "hollow_dark": "#030A18", "hollow_glow": "#2CEAA3",
		"foam_lit": "#B8FFF1", "foam_shade": "#2B2D6E",
		"surfer_skin": "#8A7AA0", "surfer_shorts": "#C6F135", "surfer_board": "#B8FFF1", "surfer_hair": "#9A90C0",
		"surfer_ink": "#0A0818", "surfer_trim": "#59D5C1", "surfer_stripe_a": "#59D5C1", "surfer_stripe_b": "#C6F135",
		"surfer_light": "#9FE8E0", "surfer_shade": "#1E1A4A", "surfer_rim": "#4FFFB0",
		"surfer_veil_deep": "#062A3A", "surfer_veil_lit": "#2CEAA3",
		"swell_top": "#0D2A44", "swell_deep": "#0A192F", "swell_line": "#59D5C1",
		"glow": "#2CEAA3", "glow_strength": 0.3, "grade_top": "#160C2E", "grade_bottom": "#0D3B4C",
		"grade_strength": 0.1, "vignette": "#02010A", "vignette_strength": 0.6, "grain_strength": 0.05,
		"scanline_strength": 0.06, "spray_rim": "#C6F135",
	},
}

## The blended look right now. Shaders and shapes read from this.
var current: MoodData
var mood_name := DEFAULT_MOOD

var _from: MoodData
var _to: MoodData
var _fade := 1.0
# The two moods of the running blend, built once, so a continuous blend does not parse the table every frame.
var _blend_names: Array[String] = ["", ""]
var _blend_moods := [null, null]


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


## Sets the look to `t` of the way from mood `from_name` to mood `to_name`, at once (the solar clock calls this as the
## sun goes down; it is already smooth, so there is no fade).
func blend(from_name: String, to_name: String, t: float) -> void:
	if not MOODS.has(from_name) or not MOODS.has(to_name):
		return
	var a := _blend_end(0, from_name)
	var b := _blend_end(1, to_name)
	current = a if t <= 0.0 else (b if t >= 1.0 else a.mixed_with(b, t))
	mood_name = from_name if t < 0.5 else to_name
	_from = current
	_to = current
	_fade = 1.0
	set_process(false)
	changed.emit()


## The MoodData for mood `name` at end `slot` (0 from, 1 to) of the running blend, built only when it changes.
func _blend_end(slot: int, name: String) -> MoodData:
	if _blend_names[slot] != name:
		_blend_names[slot] = name
		_blend_moods[slot] = build(name)
	return _blend_moods[slot]


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


func _exit_tree() -> void:
	# Let go of the cached moods before the engine tears scripts down at exit, or MoodData's script leaks.
	_blend_moods = [null, null]
	_blend_names = ["", ""]
	current = null
	_from = null
	_to = null
